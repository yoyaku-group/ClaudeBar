import Foundation

/// Normalized, credential-free snapshot supplied by llm-router.
///
/// Percentages deliberately remain fractions here. Conversion to ClaudeBar's
/// 0...100 `UsageQuota` model happens once in `RouterBackedProvider`.
public struct RouterQuotaSnapshot: Sendable, Equatable {
    public let generatedAt: Date
    public let providers: [String: RouterProviderQuota]
    public let isStale: Bool
    public let fallbackError: String?

    public init(
        generatedAt: Date,
        providers: [String: RouterProviderQuota],
        isStale: Bool = false,
        fallbackError: String? = nil
    ) {
        self.generatedAt = generatedAt
        self.providers = providers
        self.isStale = isStale
        self.fallbackError = fallbackError
    }

    public func stale(after error: Error) -> Self {
        Self(
            generatedAt: generatedAt,
            providers: providers,
            isStale: true,
            fallbackError: error.localizedDescription
        )
    }
}

public struct RouterProviderQuota: Sendable, Equatable {
    public let providerId: String
    public let windows: [RouterQuotaWindow]
    public let error: String?
    public let source: String?
    public let capturedAt: Date
    public let accounts: [RouterAccountQuota]
    public let warnings: [String]

    public init(
        providerId: String,
        windows: [RouterQuotaWindow] = [],
        error: String? = nil,
        source: String? = nil,
        capturedAt: Date,
        accounts: [RouterAccountQuota] = [],
        warnings: [String] = []
    ) {
        self.providerId = providerId
        self.windows = windows
        self.error = error
        self.source = source
        self.capturedAt = capturedAt
        self.accounts = accounts
        self.warnings = warnings
    }
}

public struct RouterAccountQuota: Sendable, Equatable {
    public let alias: String
    public let windows: [RouterQuotaWindow]
    public let present: Bool
    public let error: String?
    public let source: String?
    public let active: Bool
    public let stale: Bool

    public init(
        alias: String,
        windows: [RouterQuotaWindow] = [],
        present: Bool = true,
        error: String? = nil,
        source: String? = nil,
        active: Bool = true,
        stale: Bool = false
    ) {
        self.alias = alias
        self.windows = windows
        self.present = present
        self.error = error
        self.source = source
        self.active = active
        self.stale = stale
    }
}

public struct RouterQuotaWindow: Sendable, Equatable {
    public let kind: String
    public let remainingFraction: Double?
    public let resetsAt: Date?
    public let note: String?

    public init(
        kind: String,
        remainingFraction: Double?,
        resetsAt: Date? = nil,
        note: String? = nil
    ) {
        self.kind = kind
        self.remainingFraction = remainingFraction
        self.resetsAt = resetsAt
        self.note = note
    }
}

public protocol RouterQuotaSnapshotProviding: Sendable {
    func isAvailable() async -> Bool
    func snapshot(forceRefresh: Bool) async throws -> RouterQuotaSnapshot
}

/// Providers can expose account-scoped warnings without fabricating quota
/// windows for missing, expired, or stale credentials.
@MainActor
public protocol GroupErrorReporting: Sendable {
    var lastGroupErrors: [String: String] { get }
}

public struct RouterQuotaIssue: Error, LocalizedError, Sendable, Equatable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}
