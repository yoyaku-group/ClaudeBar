import Foundation
import Domain

/// Probe that surfaces quotas from the local `llm-router` state — the
/// ecosystem's quota SSOT (rules/81: one meter, many consumers).
///
/// Data source: `llm-router status --format json` (~2-5 s subprocess, uv tool).
/// One call returns every provider's windows — including Qwen's CGU-mandated
/// manual quota (NO API polling for Qwen, ever) and GLM via the sanctioned
/// usage plugin. Claude and Codex are excluded here because ClaudeBar probes
/// them natively; native Zai/MiniMax wins over their llm-router rows when
/// those providers are enabled.
///
/// The subprocess is expensive for a menu bar app, so results are cached for
/// five minutes per probe call chain (panel refreshes within the window are
/// served from cache).
public final class LLMRouterStateProbe: UsageProbe, GroupErrorReporting, @unchecked Sendable {

    /// Slugs owned by this probe (claude/codex are native ClaudeBar providers).
    private static let ownedSlugs = [
        "qwen_personal_pro": "Qwen",
        "glm_pro": "GLM",
        "minimax_max": "MiniMax",
        "kimi": "Kimi",
        "bedrock": "Bedrock",
        "local": "Local",
    ]

    private let cliPath: String
    private let timeout: TimeInterval
    private let clock: () -> Date
    /// Slugs whose rows are covered by a native ClaudeBar provider (skipped
    /// here so the overview never shows duplicates).
    private let skipSlugs: Set<String>

    /// Cache state (guarded by self — probe() is called from concurrent
    /// task-group refreshes).
    private var cachedAt: Date?
    private var cachedSnapshot: UsageSnapshot?
    private let lock = NSLock()

    /// Per-provider-group errors from the last successful `status` run
    /// (e.g. Kimi "CLI credential is expired"). Surfaced as row badges —
    /// never as fake quota numbers.
    public private(set) var lastGroupErrors: [String: String] = [:]

    public init(
        cliPath: String = (("~/.local/bin/llm-router" as NSString).expandingTilde as String),
        timeout: TimeInterval = 15,
        skipSlugs: Set<String> = [],
        clock: @escaping () -> Date = Date.init
    ) {
        self.cliPath = cliPath
        self.timeout = timeout
        self.skipSlugs = skipSlugs
        self.clock = clock
    }

    public func isAvailable() async -> Bool {
        FileManager.default.isExecutableFile(atPath: cliPath)
    }

    public func probe() async throws -> UsageSnapshot {
        lock.lock()
        if let cachedAt, let cachedSnapshot,
           clock().timeIntervalSince(cachedAt) < Self.cacheTTL {
            lock.unlock()
            return cachedSnapshot
        }
        lock.unlock()

        let json = try await runCLI()
        let (snapshot, groupErrors) = try Self.parse(json, skipSlugs: skipSlugs)
        lock.lock()
        cachedAt = clock()
        cachedSnapshot = snapshot
        lastGroupErrors = groupErrors
        lock.unlock()
        return snapshot
    }

    /// Cache window — llm-router's own freshest source refreshes every ~120 s;
    /// a menu bar app does not need better than 5-minute granularity here.
    static let cacheTTL: TimeInterval = 300

    // MARK: - Subprocess

    private func runCLI() async throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["status", "--format", "json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        if process.isRunning {
            process.terminate()
            throw ProbeError.executionFailed("llm-router status timed out after \(Int(timeout))s")
        }
        guard process.terminationStatus == 0 else {
            throw ProbeError.executionFailed("llm-router status exited \(process.terminationStatus)")
        }
        return pipe.fileHandleForReading.readDataToEndOfFile()
    }

    // MARK: - Parsing

    struct ProviderStatus: Decodable {
        let windows: [Window]?
        let error: String?
    }

    struct Window: Decodable {
        let kind: String?
        let remainingPct: Double?
        let resetsAt: String?
        let note: String?
    }

    static func parse(_ data: Data, skipSlugs: Set<String> = []) throws -> (UsageSnapshot, [String: String]) {
        let decoded = try JSONDecoder().decode([String: ProviderStatus].self, from: data)
        let iso8601 = ISO8601DateFormatter()

        var quotas: [UsageQuota] = []
        var groupErrors: [String: String] = [:]
        for (slug, status) in decoded.sorted(by: { $0.key < $1.key }) {
            guard let displayName = ownedSlugs[slug], !skipSlugs.contains(slug) else { continue }
            if let windows = status.windows, !windows.isEmpty {
                for window in windows {
                    let pct = window.remainingPct ?? 0
                    let resetsAt = window.resetsAt.flatMap { iso8601.date(from: $0) }
                    let quotaType = quotaType(forKind: window.kind)
                    quotas.append(UsageQuota(
                        percentRemaining: pct,
                        quotaType: quotaType,
                        providerId: "llm-router",
                        resetsAt: resetsAt,
                        resetText: nil,
                        group: displayName,
                        compactTitle: compactTitle(forKind: window.kind)
                    ))
                }
            } else if let error = status.error, !error.isEmpty {
                // No windows, provider errored (e.g. Kimi creds expired) —
                // surface as a badge, never as invented quota numbers.
                groupErrors[displayName] = error
            }
        }

        return (UsageSnapshot(providerId: "llm-router", quotas: quotas, capturedAt: Date()), groupErrors)
    }

    static func quotaType(forKind kind: String?) -> QuotaType {
        switch kind ?? "" {
        case let k where k.contains("hour"): return .session
        case let k where k.contains("week") || k.contains("seven"): return .weekly
        case let k where k.contains("scoped"):
            return .modelSpecific("scoped")
        default: return .timeLimit(kind ?? "fenêtre")
        }
    }

    static func compactTitle(forKind kind: String?) -> String? {
        switch kind ?? "" {
        case let k where k.contains("hour"): return "5h"
        case let k where k.contains("week") || k.contains("seven"): return "7d"
        case let k where k.contains("manual"): return "manuel"
        default: return nil
        }
    }
}
