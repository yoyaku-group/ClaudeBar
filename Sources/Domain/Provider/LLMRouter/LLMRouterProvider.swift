import Foundation
import Observation

/// Probes that aggregate several upstream providers can report per-group
/// errors (provider X errored → badge, no invented quota numbers).
public protocol GroupErrorReporting: Sendable {
    var lastGroupErrors: [String: String] { get }
}

/// llm-router provider — the ecosystem's quota SSOT surfaced as one row per
/// LLM identity (Qwen, GLM, MiniMax, Kimi, Bedrock). Claude/Codex are owned
/// by their native ClaudeBar providers; errored providers surface as row
/// badges via `groupErrors`, never as invented quota numbers.
@MainActor
@Observable
public final class LLMRouterProvider: AIProvider {
    public let id: String = "llm-router"
    public let name: String = "LLM Router"
    public let cliCommand: String = "llm-router"

    public var dashboardURL: URL? { nil }
    public var statusPageURL: URL? { nil }

    public var isEnabled: Bool {
        didSet {
            settingsRepository.setEnabled(isEnabled, forProvider: id)
        }
    }

    public private(set) var isSyncing: Bool = false
    public private(set) var snapshot: UsageSnapshot?
    public private(set) var lastError: Error?

    /// Per-provider-group errors from the last refresh (e.g. "Kimi" →
    /// "CLI credential is expired"). Read by the overview builder to render
    /// badges for providers whose windows are absent because they errored.
    public private(set) var groupErrors: [String: String] = [:]

    private let probe: any UsageProbe
    private let settingsRepository: any ProviderSettingsRepository

    public init(probe: any UsageProbe, settingsRepository: any ProviderSettingsRepository) {
        self.probe = probe
        self.settingsRepository = settingsRepository
        self.isEnabled = settingsRepository.isEnabled(forProvider: "llm-router")
    }

    public func isAvailable() async -> Bool {
        await probe.isAvailable()
    }

    @discardableResult
    public func refresh() async throws -> UsageSnapshot {
        isSyncing = true
        defer { isSyncing = false }

        do {
            let newSnapshot = try await probe.probe()
            snapshot = newSnapshot
            lastError = nil
            if let reporting = probe as? any GroupErrorReporting {
                groupErrors = reporting.lastGroupErrors
            }
            return newSnapshot
        } catch {
            lastError = error
            throw error
        }
    }
}
