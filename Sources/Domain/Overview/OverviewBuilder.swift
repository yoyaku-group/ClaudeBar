import Foundation

/// Pure projection from live providers to overview dashboard rows.
///
/// One row per provider; multi-account providers (e.g., Claude's isolated
/// config directories) contribute one row per account so each identity keeps
/// its own windows. Sort keys honor the window filter and sort mode selected
/// in the dashboard header.
public enum OverviewBuilder {

    // MARK: - Build

    public static func build(providers: [any AIProvider]) -> [ProviderSnapshot] {
        providers.flatMap { provider -> [ProviderSnapshot] in
            if let multi = provider as? any MultiAccountProvider, !multi.accounts.isEmpty {
                return multi.accounts.map { account in
                    guard let snapshot = multi.accountSnapshots[account.accountId] else {
                        // Account registered but never probed yet — keep the row
                        // visible with a syncing state instead of hiding it.
                        return ProviderSnapshot(
                            id: "\(provider.id)|\(account.accountId)",
                            providerId: provider.id,
                            providerName: provider.name,
                            accountLabel: account.displayName,
                            windows: [],
                            isSyncing: true
                        )
                    }
                    return row(
                        providerId: provider.id,
                        providerName: provider.name,
                        rowId: "\(provider.id)|\(account.accountId)",
                        accountLabel: multi.accounts.count > 1 ? account.displayName : nil,
                        snapshot: snapshot
                    )
                }
            }
            // Single-account provider: one row from the aggregate snapshot.
            guard let snapshot = provider.snapshot else {
                if provider.isSyncing {
                    return [ProviderSnapshot(
                        id: provider.id,
                        providerId: provider.id,
                        providerName: provider.name,
                        accountLabel: nil,
                        windows: [],
                        isSyncing: true
                    )]
                }
                return [ProviderSnapshot(
                    id: provider.id,
                    providerId: provider.id,
                    providerName: provider.name,
                    accountLabel: nil,
                    windows: [],
                    isSyncing: false,
                    errorMessage: provider.lastError?.localizedDescription
                )]
            }
            return [row(
                providerId: provider.id,
                providerName: provider.name,
                rowId: provider.id,
                accountLabel: nil,
                snapshot: snapshot
            )]
        }
    }

    /// Builds one row from a usage snapshot.
    private static func row(
        providerId: String,
        providerName: String,
        rowId: String,
        accountLabel: String?,
        snapshot: UsageSnapshot
    ) -> ProviderSnapshot {
        let windows = snapshot.quotas.map { quota in
            WindowSnapshot(
                id: "\(rowId)|\(quota.quotaType.displayName)|\(quota.group ?? "")",
                title: quota.compactTitle ?? quota.quotaType.shortLabel,
                percentRemaining: quota.percentRemaining,
                resetsAt: quota.resetsAt,
                compactReset: quota.compactResetTime,
                scope: WindowScope(quotaType: quota.quotaType),
                isDollarBased: quota.isDollarBased,
                formattedDollarRemaining: quota.formattedDollarRemaining
            )
        }
        return ProviderSnapshot(
            id: rowId,
            providerId: providerId,
            providerName: providerName,
            accountLabel: accountLabel,
            windows: windows
        )
    }

    // MARK: - Sort

    /// Sorts rows by the selected mode, using each row's worst window that
    /// matches the filter. Rows without matching windows sink to the bottom
    /// (they are still listed — never hidden).
    public static func sort(
        _ snapshots: [ProviderSnapshot],
        by mode: OverviewSort,
        filter: OverviewWindowFilter
    ) -> [ProviderSnapshot] {
        snapshots.sorted { lhs, rhs in
            let lhsKey = sortKey(lhs, mode: mode, filter: filter)
            let rhsKey = sortKey(rhs, mode: mode, filter: filter)
            return lhsKey < rhsKey
        }
    }

    /// Comparable sort key: nil sorts after every real value.
    private static func sortKey(
        _ snapshot: ProviderSnapshot,
        mode: OverviewSort,
        filter: OverviewWindowFilter
    ) -> (rank: Int, value: Double) {
        guard let worst = snapshot.worstWindow(matching: filter) else {
            return (1, 0) // no matching windows → bottom, stable-ish by id upstream
        }
        switch mode {
        case .percentRemaining:
            let value = worst.isDollarBased ? 101 : worst.percentRemaining
            return (0, value)
        case .timeToReset:
            guard let resetsAt = worst.resetsAt else {
                return (1, 0) // unknown reset → bottom with the no-window rows
            }
            return (0, resetsAt.timeIntervalSince1970)
        }
    }
}
