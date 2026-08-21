import Foundation
import Testing
@testable import Domain
@testable import Infrastructure

@Suite("LLMRouterSnapshotClient")
struct LLMRouterSnapshotClientTests {
    @Test("v2 parser preserves normalized fractions")
    func preservesNormalizedFractions() throws {
        let snapshot = try LLMRouterSnapshotClient.parse(Self.payload())

        #expect(snapshot.providers["claude"]?.windows.first?.remainingFraction == 0.58)
        #expect(snapshot.providers["claude"]?.accounts.map(\.alias) == ["WEBMASTER", "TECH"])
        #expect(snapshot.providers["claude"]?.accounts[1].present == false)
    }

    @Test("concurrent provider refreshes execute one router command")
    func coalescesConcurrentCalls() async throws {
        let runner = StubRunner(results: [.success(Self.payload())], delay: .milliseconds(100))
        let client = LLMRouterSnapshotClient(
            runner: runner,
            executableResolver: { "/bin/echo" },
            forcedCoalescingWindow: 0
        )

        async let first = client.snapshot(forceRefresh: true)
        async let second = client.snapshot(forceRefresh: true)
        async let third = client.snapshot(forceRefresh: true)
        _ = try await (first, second, third)

        #expect(await runner.callCount == 1)
        #expect(await runner.lastArguments == ["status", "--format", "json-v2"])
    }

    @Test("failed refresh returns an explicitly stale last-good snapshot")
    func fallsBackToLastGoodSnapshot() async throws {
        let runner = StubRunner(results: [
            .success(Self.payload()),
            .failure(StubFailure.commandFailed),
        ])
        let client = LLMRouterSnapshotClient(
            runner: runner,
            executableResolver: { "/bin/echo" },
            forcedCoalescingWindow: 0
        )

        let fresh = try await client.snapshot(forceRefresh: true)
        let fallback = try await client.snapshot(forceRefresh: true)

        #expect(fresh.isStale == false)
        #expect(fallback.isStale == true)
        #expect(fallback.fallbackError?.contains("commandFailed") == true)
        #expect(fallback.providers == fresh.providers)
        #expect(await runner.callCount == 2)
    }

    @Test("percentages above one are rejected as contract drift")
    func rejectsWholePercentValues() {
        #expect(throws: RouterQuotaIssue.self) {
            try LLMRouterSnapshotClient.parse(Self.payload(remaining: 58))
        }
    }

    @Test("schema-required nullable fields cannot silently disappear")
    func rejectsMissingRequiredNullableField() throws {
        let valid = try #require(String(data: Self.payload(), encoding: .utf8))
        let missingGrade = valid.replacingOccurrences(of: "\"grade\": \"B\",", with: "")

        #expect(throws: RouterQuotaIssue.self) {
            try LLMRouterSnapshotClient.parse(Data(missingGrade.utf8))
        }
    }

    private static func payload(remaining: Double = 0.58) -> Data {
        Data(
            """
            {
              "schema_version": 2,
              "generated_at": "2026-08-21T00:00:00+00:00",
              "providers": {
                "claude": {
                  "provider_id": "claude",
                  "windows": [{
                    "kind": "five_hour",
                    "remaining_pct": \(remaining),
                    "limit": null,
                    "unit": null,
                    "resets_at": "2026-08-21T05:00:00Z",
                    "note": null
                  }],
                  "error": null,
                  "source": "quota_broker",
                  "grade": "B",
                  "captured_at": 1787263200,
                  "manual": false,
                  "accounts": [
                    {
                      "alias": "WEBMASTER",
                      "windows": [{
                        "kind": "five_hour",
                        "remaining_pct": \(remaining),
                        "limit": null,
                        "unit": null,
                        "resets_at": null,
                        "note": null
                      }],
                      "present": true,
                      "error": null,
                      "source": "claude-swap",
                      "active": true,
                      "stale": false
                    },
                    {
                      "alias": "TECH",
                      "windows": [],
                      "present": false,
                      "error": "compte attendu absent du relevé",
                      "source": null,
                      "active": false,
                      "stale": false
                    }
                  ],
                  "warnings": ["TECH: compte attendu absent du relevé"],
                  "effective_headroom": \(remaining),
                  "confidence": "fresh",
                  "age_seconds": 2
                }
              }
            }
            """.utf8
        )
    }
}

private enum StubFailure: Error, LocalizedError {
    case commandFailed

    var errorDescription: String? { "commandFailed" }
}

private actor StubRunner: LLMRouterCommandRunning {
    private var results: [Result<Data, Error>]
    private let delay: Duration?
    private(set) var callCount = 0
    private(set) var lastArguments: [String] = []

    init(results: [Result<Data, Error>], delay: Duration? = nil) {
        self.results = results
        self.delay = delay
    }

    func run(executable: String, arguments: [String], timeout: TimeInterval) async throws -> Data {
        callCount += 1
        lastArguments = arguments
        if let delay { try await Task.sleep(for: delay) }
        guard !results.isEmpty else { throw StubFailure.commandFailed }
        return try results.removeFirst().get()
    }
}
