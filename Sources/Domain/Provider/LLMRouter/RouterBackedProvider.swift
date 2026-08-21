import Foundation
import Observation

/// A first-class ClaudeBar provider backed by one entry in llm-router's v2
/// snapshot. All instances share a single `RouterQuotaSnapshotProviding`
/// client, so a refresh cycle executes the expensive CLI command only once.
@MainActor
@Observable
public final class RouterBackedProvider: AIProvider, MultiAccountProvider, GroupErrorReporting, ClaudeSupplementProviding {
    public let id: String
    public let name: String
    public let cliCommand: String
    public let dashboardURL: URL?
    public let statusPageURL: URL?
    public let routerProviderId: String

    public var isEnabled: Bool {
        didSet { settingsRepository.setEnabled(isEnabled, forProvider: id) }
    }

    public private(set) var isSyncing = false
    public private(set) var snapshot: UsageSnapshot?
    public private(set) var lastError: Error?

    public private(set) var accounts: [ProviderAccount] = []
    public private(set) var activeAccount: ProviderAccount
    public private(set) var accountSnapshots: [String: UsageSnapshot] = [:]
    public private(set) var lastGroupErrors: [String: String] = [:]

    public private(set) var guestPass: ClaudePass?
    public private(set) var isFetchingPasses = false
    public private(set) var passError: Error?
    public var supportsGuestPasses: Bool { guestPassEnabled && passProbe != nil }

    private let source: any RouterQuotaSnapshotProviding
    private let settingsRepository: any MultiAccountSettingsRepository
    private let dailyUsageAnalyzer: (any DailyUsageAnalyzing)?
    private let passProbe: (any ClaudePassProbing)?
    private let guestPassEnabled: Bool

    public init(
        id: String,
        name: String,
        routerProviderId: String,
        cliCommand: String,
        dashboardURL: URL? = nil,
        statusPageURL: URL? = nil,
        source: any RouterQuotaSnapshotProviding,
        settingsRepository: any MultiAccountSettingsRepository,
        dailyUsageAnalyzer: (any DailyUsageAnalyzing)? = nil,
        passProbe: (any ClaudePassProbing)? = nil,
        guestPassEnabled: Bool = false
    ) {
        self.id = id
        self.name = name
        self.routerProviderId = routerProviderId
        self.cliCommand = cliCommand
        self.dashboardURL = dashboardURL
        self.statusPageURL = statusPageURL
        self.source = source
        self.settingsRepository = settingsRepository
        self.dailyUsageAnalyzer = dailyUsageAnalyzer
        self.passProbe = passProbe
        self.guestPassEnabled = guestPassEnabled
        self.isEnabled = settingsRepository.isEnabled(forProvider: id)
        self.activeAccount = ProviderAccount(providerId: id, label: name)
    }

    public func isAvailable() async -> Bool {
        await source.isAvailable()
    }

    @discardableResult
    public func refresh() async throws -> UsageSnapshot {
        try await refresh(.interactive)
    }

    @discardableResult
    public func refresh(_ kind: RefreshKind) async throws -> UsageSnapshot {
        isSyncing = true
        defer { isSyncing = false }

        do {
            let aggregate = try await source.snapshot(forceRefresh: true)
            guard let provider = aggregate.providers[routerProviderId] else {
                throw RouterQuotaIssue("llm-router snapshot is missing provider \(routerProviderId)")
            }
            rebuildState(from: provider, aggregate: aggregate)

            var activeSnapshot = accountSnapshots[activeAccount.accountId]
                ?? makeSnapshot(windows: provider.windows, capturedAt: provider.capturedAt)
            if id == "claude", case .interactive = kind {
                activeSnapshot = await attachDailyReport(to: activeSnapshot)
                accountSnapshots[activeAccount.accountId] = activeSnapshot
            }
            snapshot = activeSnapshot

            if activeSnapshot.quotas.isEmpty, let message = provider.error {
                lastError = RouterQuotaIssue(message)
            } else {
                lastError = nil
            }
            return activeSnapshot
        } catch {
            lastError = error
            throw error
        }
    }

    @discardableResult
    public func switchAccount(to accountId: String) -> Bool {
        guard let account = accounts.first(where: { $0.accountId == accountId }) else {
            return false
        }
        activeAccount = account
        settingsRepository.setActiveAccountId(accountId, forProvider: id)
        snapshot = accountSnapshots[accountId]
        return true
    }

    @discardableResult
    public func refreshAccount(_ accountId: String) async throws -> UsageSnapshot {
        _ = try await refresh(.interactive)
        guard let accountSnapshot = accountSnapshots[accountId] else {
            let message = lastGroupErrors[accountId] ?? "No quota available for account \(accountId)"
            throw RouterQuotaIssue(message)
        }
        return accountSnapshot
    }

    public func refreshAllAccounts() async {
        _ = try? await refresh(.interactive)
    }

    public func refreshAllAccounts(_ kind: RefreshKind) async {
        _ = try? await refresh(kind)
    }

    /// Account membership is owned by the upstream credential tools, not by
    /// ClaudeBar. Authentication actions therefore never mutate this roster.
    public func addAccount(_ config: ProviderAccountConfig) -> Bool { false }

    @discardableResult
    public func fetchPasses() async throws -> ClaudePass {
        guard let passProbe else { throw PassError.probeNotConfigured }
        isFetchingPasses = true
        defer { isFetchingPasses = false }
        do {
            let pass = try await passProbe.probe()
            guestPass = pass
            passError = nil
            return pass
        } catch {
            passError = error
            throw error
        }
    }

    public func clearPassError() {
        passError = nil
    }

    private func rebuildState(from provider: RouterProviderQuota, aggregate: RouterQuotaSnapshot) {
        let localConfigs = settingsRepository.accounts(forProvider: id)
        let localByAlias = localAccountMap(localConfigs)
        var newAccounts: [ProviderAccount] = []
        var newSnapshots: [String: UsageSnapshot] = [:]
        var newErrors: [String: String] = [:]

        if provider.accounts.isEmpty {
            let account = ProviderAccount(providerId: id, label: name)
            newAccounts = [account]
            if !provider.windows.isEmpty {
                newSnapshots[account.accountId] = makeSnapshot(
                    windows: provider.windows,
                    capturedAt: provider.capturedAt
                )
            }
            if let error = provider.error {
                newErrors[account.accountId] = error
            }
        } else {
            for routerAccount in provider.accounts {
                let alias = routerAccount.alias.uppercased()
                let local = localByAlias[alias]
                let accountId = alias
                let account = ProviderAccount(
                    accountId: accountId,
                    providerId: id,
                    label: alias,
                    email: local?.email,
                    organization: local?.organization
                )
                newAccounts.append(account)

                if routerAccount.present, routerAccount.active, !routerAccount.windows.isEmpty {
                    newSnapshots[accountId] = makeSnapshot(
                        windows: routerAccount.windows,
                        capturedAt: provider.capturedAt,
                        email: local?.email,
                        organization: local?.organization
                    )
                }

                var messages: [String] = []
                if !routerAccount.present { messages.append("Expected account is missing") }
                if !routerAccount.active { messages.append("Account is disabled") }
                if routerAccount.stale { messages.append("Account reading is stale") }
                if let error = routerAccount.error { messages.append(error) }
                if !messages.isEmpty {
                    newErrors[accountId] = Array(Set(messages)).sorted().joined(separator: "; ")
                }
            }
        }

        if aggregate.isStale {
            let message = "Using last known llm-router snapshot"
                + (aggregate.fallbackError.map { ": \($0)" } ?? "")
            for account in newAccounts where newErrors[account.accountId] == nil {
                newErrors[account.accountId] = message
            }
        }

        accounts = newAccounts
        accountSnapshots = newSnapshots
        lastGroupErrors = newErrors

        let persisted = settingsRepository.activeAccountId(forProvider: id)
        let preferred = persisted.flatMap { wanted in
            newAccounts.first { $0.accountId == wanted && newSnapshots[wanted] != nil }
        }
        activeAccount = preferred
            ?? newAccounts.first { newSnapshots[$0.accountId] != nil }
            ?? newAccounts.first
            ?? ProviderAccount(providerId: id, label: name)
        settingsRepository.setActiveAccountId(activeAccount.accountId, forProvider: id)
    }

    private func localAccountMap(_ configs: [ProviderAccountConfig]) -> [String: ProviderAccountConfig] {
        var result: [String: ProviderAccountConfig] = [:]
        for config in configs {
            // Alias membership belongs to llm-router. Local account metadata is
            // joined only through an explicit alias binding so labels/emails can
            // never silently redefine the shared roster.
            guard let alias = config.probeConfig["routerAlias"]?.uppercased(),
                  !alias.isEmpty, result[alias] == nil else { continue }
            result[alias] = config
        }
        return result
    }

    private func makeSnapshot(
        windows: [RouterQuotaWindow],
        capturedAt: Date,
        email: String? = nil,
        organization: String? = nil
    ) -> UsageSnapshot {
        UsageSnapshot(
            providerId: id,
            quotas: windows.compactMap { window in
                guard let fraction = window.remainingFraction else { return nil }
                return UsageQuota(
                    percentRemaining: fraction * 100.0,
                    quotaType: Self.quotaType(for: window.kind),
                    providerId: id,
                    resetsAt: window.resetsAt,
                    resetText: window.note,
                    compactTitle: Self.compactTitle(for: window.kind)
                )
            },
            capturedAt: capturedAt,
            accountEmail: email,
            accountOrganization: organization
        )
    }

    private func attachDailyReport(to base: UsageSnapshot) async -> UsageSnapshot {
        guard let dailyUsageAnalyzer,
              let report = try? await dailyUsageAnalyzer.analyzeToday(),
              !report.today.isEmpty || !report.previous.isEmpty else {
            return base
        }
        return UsageSnapshot(
            providerId: base.providerId,
            quotas: base.quotas,
            capturedAt: base.capturedAt,
            accountEmail: base.accountEmail,
            accountOrganization: base.accountOrganization,
            loginMethod: base.loginMethod,
            accountTier: base.accountTier,
            costUsage: base.costUsage,
            bedrockUsage: base.bedrockUsage,
            dailyUsageReport: report,
            extensionMetrics: base.extensionMetrics
        )
    }

    static func quotaType(for kind: String) -> QuotaType {
        let normalized = kind.lowercased()
        if normalized.contains("week") || normalized.contains("seven") || normalized.contains("7d") {
            return .weekly
        }
        if normalized.contains("hour") || normalized.contains("5h") || normalized.contains("session") {
            return .session
        }
        if normalized.contains("scoped") || normalized.contains("model") {
            return .modelSpecific(kind)
        }
        return .timeLimit(kind)
    }

    static func compactTitle(for kind: String) -> String {
        switch quotaType(for: kind) {
        case .session: "5h"
        case .weekly: "7d"
        case .modelSpecific, .timeLimit: kind
        }
    }
}
