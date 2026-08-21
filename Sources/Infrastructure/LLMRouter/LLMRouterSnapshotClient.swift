import Foundation
import Domain

/// Narrow execution seam for the versioned llm-router snapshot command.
public protocol LLMRouterCommandRunning: Sendable {
    func run(executable: String, arguments: [String], timeout: TimeInterval) async throws -> Data
}

/// Process-backed command runner used by the production snapshot client.
public final class LLMRouterProcessRunner: LLMRouterCommandRunning, @unchecked Sendable {
    public init() {}

    public func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        if process.isRunning {
            process.terminate()
            throw RouterQuotaIssue("llm-router status timed out after \(Int(timeout))s")
        }

        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            let detail = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = detail.flatMap { $0.isEmpty ? nil : ": \($0)" } ?? ""
            throw RouterQuotaIssue("llm-router status exited \(process.terminationStatus)\(suffix)")
        }
        return output
    }
}

/// Single-reader client for llm-router's public quota snapshot v2 contract.
///
/// All router-backed provider instances share one actor. Concurrent refreshes
/// coalesce onto one subprocess, short-interval refreshes reuse the decoded
/// snapshot, and a command failure falls back to the last validated value with
/// explicit stale metadata.
public actor LLMRouterSnapshotClient: RouterQuotaSnapshotProviding {
    public typealias ExecutableResolver = @Sendable () -> String?
    public typealias Clock = @Sendable () -> Date

    private struct InFlight {
        let id: UUID
        let task: Task<RouterQuotaSnapshot, Error>
    }

    private let runner: any LLMRouterCommandRunning
    private let executableResolver: ExecutableResolver
    private let timeout: TimeInterval
    private let cacheTTL: TimeInterval
    private let forcedCoalescingWindow: TimeInterval
    private let clock: Clock

    private var cachedSnapshot: RouterQuotaSnapshot?
    private var cachedAt: Date?
    private var inFlight: InFlight?

    public init(
        runner: any LLMRouterCommandRunning = LLMRouterProcessRunner(),
        executableResolver: @escaping ExecutableResolver = LLMRouterSnapshotClient.resolveExecutable,
        timeout: TimeInterval = 60,
        cacheTTL: TimeInterval = 30,
        forcedCoalescingWindow: TimeInterval = 1,
        clock: @escaping Clock = Date.init
    ) {
        self.runner = runner
        self.executableResolver = executableResolver
        self.timeout = timeout
        self.cacheTTL = cacheTTL
        self.forcedCoalescingWindow = forcedCoalescingWindow
        self.clock = clock
    }

    public func isAvailable() async -> Bool {
        guard let executable = executableResolver() else { return false }
        return FileManager.default.isExecutableFile(atPath: executable)
    }

    public func snapshot(forceRefresh: Bool) async throws -> RouterQuotaSnapshot {
        if let inFlight {
            return try await inFlight.task.value
        }

        let now = clock()
        if let cachedSnapshot, let cachedAt {
            let age = now.timeIntervalSince(cachedAt)
            let allowedAge = forceRefresh ? forcedCoalescingWindow : cacheTTL
            if age >= 0, age < allowedAge {
                return cachedSnapshot
            }
        }

        guard let executable = executableResolver() else {
            let error = RouterQuotaIssue("llm-router executable was not found")
            if let cachedSnapshot { return cachedSnapshot.stale(after: error) }
            throw error
        }

        let runner = self.runner
        let timeout = self.timeout
        let requestId = UUID()
        let task = Task<RouterQuotaSnapshot, Error> {
            let data = try await runner.run(
                executable: executable,
                arguments: ["status", "--format", "json-v2"],
                timeout: timeout
            )
            return try Self.parse(data)
        }
        inFlight = InFlight(id: requestId, task: task)

        do {
            let decoded = try await task.value
            if inFlight?.id == requestId { inFlight = nil }
            cachedSnapshot = decoded
            cachedAt = clock()
            return decoded
        } catch {
            if inFlight?.id == requestId { inFlight = nil }
            if let cachedSnapshot { return cachedSnapshot.stale(after: error) }
            throw error
        }
    }

    public static func resolveExecutable() -> String? {
        if let configured = ProcessInfo.processInfo.environment["LLM_ROUTER_BIN"],
           FileManager.default.isExecutableFile(atPath: configured) {
            return configured
        }
        return BinaryLocator.findInCommonPaths("llm-router")
            ?? BinaryLocator.which("llm-router")
    }

    static func parse(_ data: Data) throws -> RouterQuotaSnapshot {
        let wire: SnapshotWire
        do {
            wire = try JSONDecoder().decode(SnapshotWire.self, from: data)
        } catch {
            throw RouterQuotaIssue("Invalid llm-router snapshot v2 JSON: \(error.localizedDescription)")
        }

        guard wire.schemaVersion == 2 else {
            throw RouterQuotaIssue("Unsupported llm-router snapshot schema \(wire.schemaVersion); expected 2")
        }
        let generatedAt = try parseDate(wire.generatedAt, field: "generated_at")

        var providers: [String: RouterProviderQuota] = [:]
        for (key, provider) in wire.providers {
            guard !provider.providerId.isEmpty else {
                throw RouterQuotaIssue("Provider \(key) has an empty provider_id")
            }
            guard provider.providerId == key else {
                throw RouterQuotaIssue("Provider key \(key) does not match provider_id \(provider.providerId)")
            }
            try validateFraction(provider.effectiveHeadroom, field: "\(key).effective_headroom")
            guard provider.capturedAt.isFinite else {
                throw RouterQuotaIssue("\(key).captured_at must be finite")
            }
            guard provider.ageSeconds.isFinite, provider.ageSeconds >= 0 else {
                throw RouterQuotaIssue("\(key).age_seconds must be non-negative")
            }
            guard ["fresh", "usable", "stale", "unknown"].contains(provider.confidence) else {
                throw RouterQuotaIssue("\(key).confidence has an unsupported value")
            }

            let windows = try provider.windows.enumerated().map { index, window in
                try makeWindow(window, field: "\(key).windows[\(index)]")
            }
            let accounts = try provider.accounts.enumerated().map { index, account in
                guard !account.alias.isEmpty else {
                    throw RouterQuotaIssue("\(key).accounts[\(index)].alias must not be empty")
                }
                let accountWindows = try account.windows.enumerated().map { windowIndex, window in
                    try makeWindow(
                        window,
                        field: "\(key).accounts[\(index)].windows[\(windowIndex)]"
                    )
                }
                return RouterAccountQuota(
                    alias: account.alias,
                    windows: accountWindows,
                    present: account.present,
                    error: account.error,
                    source: account.source,
                    active: account.active,
                    stale: account.stale
                )
            }
            providers[key] = RouterProviderQuota(
                providerId: provider.providerId,
                windows: windows,
                error: provider.error,
                source: provider.source,
                capturedAt: Date(timeIntervalSince1970: provider.capturedAt),
                accounts: accounts,
                warnings: provider.warnings
            )
        }

        guard !providers.isEmpty else {
            throw RouterQuotaIssue("llm-router snapshot v2 contains no providers")
        }
        return RouterQuotaSnapshot(generatedAt: generatedAt, providers: providers)
    }

    private static func makeWindow(_ wire: WindowWire, field: String) throws -> RouterQuotaWindow {
        guard !wire.kind.isEmpty else {
            throw RouterQuotaIssue("\(field).kind must not be empty")
        }
        try validateFraction(wire.remainingPct, field: "\(field).remaining_pct")
        let reset = try wire.resetsAt.map { try parseDate($0, field: "\(field).resets_at") }
        return RouterQuotaWindow(
            kind: wire.kind,
            remainingFraction: wire.remainingPct,
            resetsAt: reset,
            note: wire.note
        )
    }

    private static func validateFraction(_ value: Double?, field: String) throws {
        guard let value else { return }
        guard value.isFinite, (0...1).contains(value) else {
            throw RouterQuotaIssue("\(field) must be a fraction between 0 and 1")
        }
    }

    private static func parseDate(_ value: String, field: String) throws -> Date {
        do {
            return try Date.ISO8601FormatStyle().parse(value)
        } catch {
            throw RouterQuotaIssue("\(field) is not a valid ISO-8601 date")
        }
    }
}

private struct SnapshotWire: Decodable {
    let schemaVersion: Int
    let generatedAt: String
    let providers: [String: ProviderWire]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case providers
    }
}

private struct ProviderWire: Decodable {
    let providerId: String
    let windows: [WindowWire]
    let error: String?
    let source: String?
    let grade: String?
    let capturedAt: Double
    let manual: Bool
    let accounts: [AccountWire]
    let warnings: [String]
    let effectiveHeadroom: Double?
    let confidence: String
    let ageSeconds: Double

    enum CodingKeys: String, CodingKey {
        case providerId = "provider_id"
        case windows, error, source, grade
        case capturedAt = "captured_at"
        case manual, accounts, warnings
        case effectiveHeadroom = "effective_headroom"
        case confidence
        case ageSeconds = "age_seconds"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        providerId = try container.decode(String.self, forKey: .providerId)
        windows = try container.decode([WindowWire].self, forKey: .windows)
        error = try container.decodeRequiredIfPresent(String.self, forKey: .error)
        source = try container.decodeRequiredIfPresent(String.self, forKey: .source)
        grade = try container.decodeRequiredIfPresent(String.self, forKey: .grade)
        capturedAt = try container.decode(Double.self, forKey: .capturedAt)
        manual = try container.decode(Bool.self, forKey: .manual)
        accounts = try container.decode([AccountWire].self, forKey: .accounts)
        warnings = try container.decode([String].self, forKey: .warnings)
        effectiveHeadroom = try container.decodeRequiredIfPresent(Double.self, forKey: .effectiveHeadroom)
        confidence = try container.decode(String.self, forKey: .confidence)
        ageSeconds = try container.decode(Double.self, forKey: .ageSeconds)
    }
}

private struct AccountWire: Decodable {
    let alias: String
    let windows: [WindowWire]
    let present: Bool
    let error: String?
    let source: String?
    let active: Bool
    let stale: Bool

    enum CodingKeys: String, CodingKey {
        case alias, windows, present, error, source, active, stale
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        alias = try container.decode(String.self, forKey: .alias)
        windows = try container.decode([WindowWire].self, forKey: .windows)
        present = try container.decode(Bool.self, forKey: .present)
        error = try container.decodeRequiredIfPresent(String.self, forKey: .error)
        source = try container.decodeRequiredIfPresent(String.self, forKey: .source)
        active = try container.decode(Bool.self, forKey: .active)
        stale = try container.decode(Bool.self, forKey: .stale)
    }
}

private struct WindowWire: Decodable {
    let kind: String
    let remainingPct: Double?
    let limit: Double?
    let unit: String?
    let resetsAt: String?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case kind
        case remainingPct = "remaining_pct"
        case limit, unit
        case resetsAt = "resets_at"
        case note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        remainingPct = try container.decodeRequiredIfPresent(Double.self, forKey: .remainingPct)
        limit = try container.decodeRequiredIfPresent(Double.self, forKey: .limit)
        unit = try container.decodeRequiredIfPresent(String.self, forKey: .unit)
        resetsAt = try container.decodeRequiredIfPresent(String.self, forKey: .resetsAt)
        note = try container.decodeRequiredIfPresent(String.self, forKey: .note)
    }
}

private extension KeyedDecodingContainer {
    func decodeRequiredIfPresent<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T? {
        guard contains(key) else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Required key \(key.stringValue) is missing"
                )
            )
        }
        return try decodeIfPresent(type, forKey: key)
    }
}
