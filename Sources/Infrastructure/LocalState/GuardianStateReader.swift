import Foundation
import Domain

/// Reads the mac-guardian daemon's state snapshot
/// (`~/.claude/state/guardian/state.json`) — machine health, live session
/// counts, and findings — replacing the SwiftBar guardian dots.
///
/// The daemon (LaunchAgent `com.yoyaku.mac-guardian`, 60 s tick) stays the
/// writer; this reader only consumes. A snapshot older than the staleness
/// gate renders as a warning state, never green (plugin-parity rule: a mute
/// daemon must not look healthy).
public enum GuardianStateReader {

    public static let stateURL = URL(fileURLWithPath:
        (("~/.claude/state/guardian/state.json" as NSString).expandingTildeInPath as String)
    )

    /// Plugin-parity staleness gate (the SwiftBar plugin used 180 s).
    public static let stalenessLimit: TimeInterval = 180

    public struct State: Sendable, Equatable {
        public let status: String            // green | yellow | red | blind
        public let capturedAt: Date
        public let metrics: Metrics
        public let findings: [Finding]
        /// True when `capturedAt` is older than the staleness gate — the UI
        /// shows "muet (Nmin)" and never green.
        public let isStale: Bool

        public struct Metrics: Sendable, Equatable, Decodable {
            public let swapUsedPct: Double?
            public let ramFreePct: Double?
            public let load1: Double?
            public let load1PerCore: Double?
            public let runnable: Int?
            public let zombies: Int?
            public let liveClaude: Int?
            public let liveCodex: Int?
            public let limited: Int?

            enum CodingKeys: String, CodingKey {
                case swapUsedPct = "swap_used_pct"
                case ramFreePct = "ram_free_pct"
                case load1, load1PerCore = "load1_per_core"
                case runnable, zombies
                case liveClaude = "live_claude"
                case liveCodex = "live_codex"
                case limited
            }
        }

        public struct Finding: Sendable, Equatable, Decodable {
            public let rule: String
            public let severity: String
            public let message: String
            public let autoDone: Bool

            enum CodingKeys: String, CodingKey {
                case rule, severity, message
                case autoDone = "auto_done"
            }
        }
    }

    /// Reads and validates the snapshot. Returns nil when unreadable.
    public static func read(now: Date = Date()) -> State? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return decode(data, now: now)
    }

    public static func decode(_ data: Data, now: Date = Date()) -> State? {
        struct Payload: Decodable {
            let ts: Double
            let status: String
            let metrics: State.Metrics
            let findings: [State.Finding]?
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return nil
        }
        let capturedAt = Date(timeIntervalSince1970: payload.ts)
        return State(
            status: payload.status,
            capturedAt: capturedAt,
            metrics: payload.metrics,
            findings: payload.findings ?? [],
            isStale: now.timeIntervalSince(capturedAt) > stalenessLimit
        )
    }
}

/// Counts harness sessions by transcript freshness — the "traquer ce que
/// j'utilise" data point. One file-count per harness directory, throttled
/// and never run on the render path.
public enum HarTranscriptCounter {

    public struct Counts: Sendable, Equatable {
        public let claude: Int
        public let codex: Int
        public let kimi: Int
        public let qwen: Int
    }

    private static let home = FileManager.default.homeDirectoryForCurrentUser

    /// Directories whose `*.jsonl` transcripts touched within `window`
    /// count as active sessions for that harness.
    static var roots: [(dir: URL, key: WritableKeyPath<Counts, Int>)] {
        [
            (home.appendingPathComponent(".claude/projects"), \.claude),
            (home.appendingPathComponent(".codex/sessions"), \.codex),
            (home.appendingPathComponent(".kimi-code/sessions"), \.kimi),
            (home.appendingPathComponent(".qwen/projects"), \.qwen),
        ]
    }

    /// Counts transcripts modified within `window` (default 24 h) across the
    /// harness roots. Cheap enough at 5-minute cadence; never call per-frame.
    public static func countActive(within window: TimeInterval = 86_400, now: Date = Date()) -> Counts {
        var counts = Counts(claude: 0, codex: 0, kimi: 0, qwen: 0)
        let cutoff = now.addingTimeInterval(-window)
        for root in roots {
            counts[keyPath: root.key] = countJSONL(in: root.dir, modifiedAfter: cutoff)
        }
        return counts
    }

    /// Walks `dir` (two levels — enough for ~/.claude/projects/<munged-cwd>/
    /// and ~/.codex/sessions/YYYY/MM/) counting recent .jsonl files.
    static func countJSONL(in dir: URL, modifiedAfter cutoff: Date) -> Int {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var count = 0
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = values.contentModificationDate else { continue }
            if modified > cutoff { count += 1 }
        }
        return count
    }
}
