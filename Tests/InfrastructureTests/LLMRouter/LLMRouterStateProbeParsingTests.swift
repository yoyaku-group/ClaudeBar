import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

/// llm-router state probe parsing: fixture mirrors the live
/// `llm-router status --format json` shape captured 2026-08-18.
@Suite
struct LLMRouterStateProbeParsingTests {

    static let statusJSON = """
    {
      "claude": {"provider_id": "claude", "windows": [{"kind": "five_hour", "remaining_pct": 100.0}], "error": null, "source": "quota_broker", "grade": "B"},
      "codex": {"provider_id": "codex", "windows": [{"kind": "seven_day", "remaining_pct": 0.0, "resets_at": "2026-08-20T03:57:09Z"}], "error": null, "source": "quota_broker", "grade": "B"},
      "kimi": {"provider_id": "kimi", "windows": [], "error": "Kimi Code CLI credential is expired.", "source": "quota_broker", "grade": "B"},
      "qwen_personal_pro": {"provider_id": "qwen_personal_pro", "windows": [{"kind": "manual", "remaining_pct": 0.0, "limit": null, "unit": null, "resets_at": "2026-08-23T20:35:00+00:00", "note": "sync manuelle"}], "error": null, "source": "console-qwen-429-2026-08-17", "grade": "C"},
      "glm_pro": {"provider_id": "glm_pro", "windows": [], "error": "quota non parsé (rc=1)", "source": "glm_usage_plugin", "grade": "B"},
      "minimax_max": {"provider_id": "minimax_max", "windows": [{"kind": "five_hour", "remaining_pct": 100.0}, {"kind": "seven_day", "remaining_pct": 97.0, "resets_at": "2026-08-24T10:00:00+00:00"}], "error": null, "source": "minimax_remains_api", "grade": "A"},
      "bedrock": {"provider_id": "bedrock", "windows": [], "error": null, "source": "ledger", "grade": "C"}
    }
    """

    @Test("parse maps owned slugs to grouped quotas and skips claude/codex")
    func parseMapsOwnedSlugsToGroupedQuotas() throws {
        let data = Data(Self.statusJSON.utf8)
        let (snapshot, errors) = try LLMRouterStateProbe.parse(data)

        // claude + codex are native ClaudeBar providers — never surfaced here
        #expect(!snapshot.quotas.contains { $0.group == nil })
        let groups = Set(snapshot.quotas.compactMap(\.group))
        #expect(groups.contains("Qwen"))
        #expect(groups.contains("MiniMax"))
        #expect(!groups.contains("Claude"))
        #expect(!groups.contains("Codex"))

        // Qwen manual window: 0% + reset date, weekly scope (drives "Throttling")
        let qwen = snapshot.quotas.first { $0.group == "Qwen" }
        #expect(qwen?.percentRemaining == 0)
        #expect(qwen?.resetsAt != nil)
        #expect(qwen?.quotaType == .weekly)

        // Errored providers without windows → badges, no fake quotas
        #expect(errors["Kimi"] != nil)
        #expect(errors["GLM"] != nil)
        #expect(!snapshot.quotas.contains { $0.group == "Kimi" })
        #expect(!snapshot.quotas.contains { $0.group == "GLM" })

        // Bedrock with no windows and no error → nothing (not a badge, not a row)
        #expect(errors["Bedrock"] == nil)
    }

    @Test("parse honors skipSlugs for natively-enabled providers")
    func parseHonorsSkipSlugs() throws {
        let data = Data(Self.statusJSON.utf8)
        let (snapshot, _) = try LLMRouterStateProbe.parse(data, skipSlugs: ["minimax_max"])
        #expect(!snapshot.quotas.contains { $0.group == "MiniMax" })
        #expect(snapshot.quotas.contains { $0.group == "Qwen" })
    }

    @Test("compact titles derive short window labels")
    func compactTitlesDeriveShortWindowLabels() {
        #expect(LLMRouterStateProbe.compactTitle(forKind: "five_hour") == "5h")
        #expect(LLMRouterStateProbe.compactTitle(forKind: "seven_day") == "7d")
        #expect(LLMRouterStateProbe.compactTitle(forKind: "manual") == "manuel")
        #expect(LLMRouterStateProbe.quotaType(forKind: "five_hour") == .session)
        #expect(LLMRouterStateProbe.quotaType(forKind: "manual") == .weekly)
    }
}
