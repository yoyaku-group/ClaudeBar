import Foundation

/// Models for the all-providers overview dashboard ("ce qu'il me reste").
///
/// The overview flattens every enabled provider — multi-account providers
/// contribute one row per account — into `ProviderSnapshot` rows whose sort
/// key is the worst window matching the user's window filter
/// (session 5h / weekly / all). One click switches which percentage drives
/// the ordering and the headline number.

/// Coarse classification of a quota window, derived from its `QuotaType`.
public enum WindowScope: String, Sendable, Hashable, CaseIterable {
    case session
    case weekly
    case other

    public init(quotaType: QuotaType) {
        switch quotaType {
        case .session:
            self = .session
        case .weekly:
            self = .weekly
        case .modelSpecific, .timeLimit:
            // Model-scoped and named windows inherit the closest bucket from
            // their declared duration: days → weekly, hours → session.
            switch quotaType.duration {
            case .days: self = .weekly
            case .hours: self = .session
            }
        }
    }
}

/// The one-click window selector (R11): which window's remaining percentage
/// the dashboard shows and sorts by.
public enum OverviewWindowFilter: String, Sendable, CaseIterable, Identifiable {
    case session
    case weekly
    case all

    public var id: String { rawValue }

    /// French UI label (rawValue is the stable storage key).
    public var displayName: String {
        switch self {
        case .session: return "Session 5h"
        case .weekly: return "Semaine"
        case .all: return "Tout"
        }
    }

    public func matches(_ scope: WindowScope) -> Bool {
        switch self {
        case .all: return true
        case .session: return scope == .session
        case .weekly: return scope == .weekly
        }
    }
}

/// Row ordering for the dashboard.
public enum OverviewSort: String, Sendable, CaseIterable, Identifiable {
    /// Worst remaining percentage first (default — "ce qu'il me reste").
    case percentRemaining
    /// Soonest reset first, relative ("3d 4h"), unknown resets last.
    case timeToReset

    public var id: String { rawValue }

    /// French UI label (rawValue is the stable storage key).
    public var displayName: String {
        switch self {
        case .percentRemaining: return "% restant"
        case .timeToReset: return "Reset"
        }
    }
}

/// A single quota window projected for the overview row.
public struct WindowSnapshot: Identifiable, Sendable, Hashable {
    /// Stable identity: provider | account | window title.
    public let id: String
    /// Short window title (e.g., "5h", "7d", "Fable 7d").
    public let title: String
    /// Percentage remaining (may be negative when over quota).
    public let percentRemaining: Double
    /// When the window resets, when known.
    public let resetsAt: Date?
    /// Relative compact reset ("3d", "4:59", "45m") computed at build time.
    public let compactReset: String?
    public let scope: WindowScope
    /// True for dollar-balance windows (rendered with currency, not %).
    public let isDollarBased: Bool
    public let formattedDollarRemaining: String?

    public init(
        id: String,
        title: String,
        percentRemaining: Double,
        resetsAt: Date?,
        compactReset: String?,
        scope: WindowScope,
        isDollarBased: Bool = false,
        formattedDollarRemaining: String? = nil
    ) {
        self.id = id
        self.title = title
        self.percentRemaining = percentRemaining
        self.resetsAt = resetsAt
        self.compactReset = compactReset
        self.scope = scope
        self.isDollarBased = isDollarBased
        self.formattedDollarRemaining = formattedDollarRemaining
    }
}

/// One dashboard row: a provider (or one account of a multi-account provider)
/// with all its quota windows.
public struct ProviderSnapshot: Identifiable, Sendable, Hashable {
    public let id: String
    public let providerId: String
    public let providerName: String
    /// Account discriminator ("Default", "Admin"…) — nil for single-account providers.
    public let accountLabel: String?
    public let windows: [WindowSnapshot]
    public let isSyncing: Bool
    public let errorMessage: String?

    /// The worst window matching `filter` (drives sort key + headline %).
    public func worstWindow(matching filter: OverviewWindowFilter) -> WindowSnapshot? {
        let candidates = windows.filter { filter.matches($0.scope) }
        return candidates.min { lhs, rhs in
            (lhs.isDollarBased ? 101 : lhs.percentRemaining)
                < (rhs.isDollarBased ? 101 : rhs.percentRemaining)
        }
    }

    /// Aggregate status across the windows matching `filter`.
    public func status(matching filter: OverviewWindowFilter) -> QuotaStatus {
        let candidates = windows.filter { filter.matches($0.scope) }
        let worst = candidates.map(\.percentRemaining).min()
        guard let worst else {
            return errorMessage != nil ? .depleted : .healthy
        }
        return QuotaStatus.from(percentRemaining: worst)
    }

    public init(
        id: String,
        providerId: String,
        providerName: String,
        accountLabel: String?,
        windows: [WindowSnapshot],
        isSyncing: Bool = false,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.providerId = providerId
        self.providerName = providerName
        self.accountLabel = accountLabel
        self.windows = windows
        self.isSyncing = isSyncing
        self.errorMessage = errorMessage
    }
}
