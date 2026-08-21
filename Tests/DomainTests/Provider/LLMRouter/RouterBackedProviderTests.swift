import Foundation
import Testing
@testable import Domain

@Suite("RouterBackedProvider")
@MainActor
struct RouterBackedProviderTests {
    @Test("fraction is converted to ClaudeBar percent exactly once")
    func convertsFractionExactlyOnce() async throws {
        let provider = makeProvider(snapshot: Self.snapshot())

        let result = try await provider.refresh()

        #expect(result.quotas.first?.percentRemaining == 58)
        #expect(result.quotas.first?.percentRemaining != 0.58)
    }

    @Test("healthy account remains usable beside a missing expected account")
    func preservesHealthyAndMissingAccounts() async throws {
        let provider = makeProvider(snapshot: Self.snapshot())

        _ = try await provider.refresh()

        #expect(provider.accounts.map(\.accountId) == ["WEBMASTER", "TECH"])
        #expect(provider.accountSnapshots["WEBMASTER"]?.quotas.first?.percentRemaining == 58)
        #expect(provider.accountSnapshots["TECH"] == nil)
        #expect(provider.lastGroupErrors["TECH"]?.contains("missing") == true)
        #expect(provider.activeAccount.accountId == "WEBMASTER")
        #expect(provider.snapshot?.quotas.first?.percentRemaining == 58)
    }

    @Test("overview renders missing account as an error, never healthy syncing data")
    func overviewSurfacesMissingAccount() async throws {
        let provider = makeProvider(snapshot: Self.snapshot())
        _ = try await provider.refresh()

        let rows = OverviewBuilder.build(providers: [provider])
        let missing = rows.first { $0.id == "claude|TECH" }

        #expect(rows.first { $0.id == "claude|WEBMASTER" }?.windows.first?.percentRemaining == 58)
        #expect(missing?.windows.isEmpty == true)
        #expect(missing?.isSyncing == false)
        #expect(missing?.errorMessage?.contains("missing") == true)
        #expect(missing?.status(matching: .all) == .depleted)
    }

    @Test("last-good fallback is visible on every otherwise healthy account")
    func exposesStaleFallback() async throws {
        let stale = RouterQuotaSnapshot(
            generatedAt: Self.now,
            providers: Self.snapshot().providers,
            isStale: true,
            fallbackError: "router unavailable"
        )
        let provider = makeProvider(snapshot: stale)

        _ = try await provider.refresh()

        #expect(provider.lastGroupErrors["WEBMASTER"]?.contains("last known") == true)
        #expect(provider.lastGroupErrors["WEBMASTER"]?.contains("router unavailable") == true)
        #expect(provider.lastGroupErrors["TECH"]?.contains("missing") == true)
    }

    @Test("local email joins only through explicit routerAlias metadata")
    func joinsLocalMetadataOnlyWithExplicitAlias() async throws {
        let settings = FakeMultiAccountSettings(accounts: [
            ProviderAccountConfig(
                accountId: "misleading-WEBMASTER",
                label: "WEBMASTER",
                email: "wrong@yoyaku.fr"
            ),
            ProviderAccountConfig(
                accountId: "local-tech",
                label: "Local Tech",
                email: "tech@yoyaku.fr",
                probeConfig: ["routerAlias": "TECH"]
            ),
        ])
        let provider = makeProvider(snapshot: Self.snapshot(), settings: settings)

        _ = try await provider.refresh()

        #expect(provider.accounts.first { $0.accountId == "WEBMASTER" }?.email == nil)
        #expect(provider.accounts.first { $0.accountId == "TECH" }?.email == "tech@yoyaku.fr")
    }

    private func makeProvider(
        snapshot: RouterQuotaSnapshot,
        settings: FakeMultiAccountSettings = FakeMultiAccountSettings()
    ) -> RouterBackedProvider {
        RouterBackedProvider(
            id: "claude",
            name: "Claude",
            routerProviderId: "claude",
            cliCommand: "claude",
            source: StaticRouterSource(value: snapshot),
            settingsRepository: settings
        )
    }

    private static let now = Date(timeIntervalSince1970: 1_787_263_200)

    private static func snapshot() -> RouterQuotaSnapshot {
        let measured = RouterQuotaWindow(kind: "five_hour", remainingFraction: 0.58)
        return RouterQuotaSnapshot(
            generatedAt: now,
            providers: [
                "claude": RouterProviderQuota(
                    providerId: "claude",
                    windows: [measured],
                    source: "quota_broker",
                    capturedAt: now,
                    accounts: [
                        RouterAccountQuota(alias: "WEBMASTER", windows: [measured]),
                        RouterAccountQuota(
                            alias: "TECH",
                            present: false,
                            error: "compte attendu absent du relevé",
                            active: false
                        ),
                    ],
                    warnings: ["TECH: compte attendu absent du relevé"]
                )
            ]
        )
    }
}

private struct StaticRouterSource: RouterQuotaSnapshotProviding {
    let value: RouterQuotaSnapshot

    func isAvailable() async -> Bool { true }
    func snapshot(forceRefresh: Bool) async throws -> RouterQuotaSnapshot { value }
}

private final class FakeMultiAccountSettings: MultiAccountSettingsRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var configuredAccounts: [ProviderAccountConfig]
    private var activeId: String?
    private var enabled = true

    init(accounts: [ProviderAccountConfig] = []) {
        configuredAccounts = accounts
    }

    func isEnabled(forProvider id: String) -> Bool { lock.withLock { enabled } }
    func isEnabled(forProvider id: String, defaultValue: Bool) -> Bool { lock.withLock { enabled } }
    func setEnabled(_ enabled: Bool, forProvider id: String) { lock.withLock { self.enabled = enabled } }
    func customCardURL(forProvider id: String) -> String? { nil }
    func setCustomCardURL(_ url: String?, forProvider id: String) {}

    func accounts(forProvider id: String) -> [ProviderAccountConfig] {
        lock.withLock { configuredAccounts }
    }

    func addAccount(_ config: ProviderAccountConfig, forProvider id: String) {
        lock.withLock { configuredAccounts.append(config) }
    }

    func removeAccount(accountId: String, forProvider id: String) {
        lock.withLock { configuredAccounts.removeAll { $0.accountId == accountId } }
    }

    func updateAccount(_ config: ProviderAccountConfig, forProvider id: String) {
        lock.withLock {
            guard let index = configuredAccounts.firstIndex(where: { $0.accountId == config.accountId }) else { return }
            configuredAccounts[index] = config
        }
    }

    func activeAccountId(forProvider id: String) -> String? { lock.withLock { activeId } }
    func setActiveAccountId(_ accountId: String?, forProvider id: String) { lock.withLock { activeId = accountId } }
}
