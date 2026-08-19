import SwiftUI
import Domain

/// One dashboard row: a provider (or one account of a multi-account provider)
/// with its worst filtered window as the headline, plus two stacked bars
/// comparing the Session 5h and Weekly 7d windows at a glance (Ben 2026-08-19).
/// Never mixes absolute dates — resets are relative only.
struct ProviderSnapshotRow: View {
    let snapshot: ProviderSnapshot
    let filter: OverviewWindowFilter

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    /// Session (5h) window for this provider, if any.
    private var sessionWindow: WindowSnapshot? {
        snapshot.windows.first { $0.scope == .session }
    }

    /// Weekly (7d) window for this provider, if any.
    private var weeklyWindow: WindowSnapshot? {
        snapshot.windows.first { $0.scope == .weekly }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if snapshot.errorMessage != nil {
                errorBadge
            } else if snapshot.isSyncing {
                Text("Syncing…")
                    .font(theme.font(size: 11, weight: .medium))
                    .foregroundStyle(theme.textTertiary)
            } else {
                WindowBarView(
                    window: sessionWindow,
                    scopeLabel: "5h",
                    isPrimary: filter == .session || filter == .all
                )
                WindowBarView(
                    window: weeklyWindow,
                    scopeLabel: "7d",
                    isPrimary: filter == .weekly || filter == .all
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.glassBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(theme.glassBorder, lineWidth: 1)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            ProviderIconView(providerId: snapshot.providerId, size: 22, showGlow: false)

            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.providerName)
                    .font(theme.font(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                if let account = snapshot.accountLabel {
                    Text(account)
                        .font(theme.font(size: 10, weight: .medium))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }
                // Email shown only for multi-account providers so two Claude
                // profiles are unambiguous at a glance (Ben 2026-08-19).
                if let email = snapshot.accountEmail {
                    Text(email)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(theme.textTertiary.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)

            headline
        }
    }

    /// The big "what's left" number for the filtered window.
    @ViewBuilder
    private var headline: some View {
        if let worst = snapshot.worstWindow(matching: filter) {
            let status = QuotaStatus.from(percentRemaining: worst.percentRemaining)
            if worst.isDollarBased, let dollars = worst.formattedDollarRemaining {
                Text(dollars)
                    .font(theme.font(size: 15, weight: .bold))
                    .foregroundStyle(theme.statusColor(for: status))
            } else {
                Text("\(Int(worst.percentRemaining.rounded()))%")
                    .font(theme.font(size: 15, weight: .bold))
                    .foregroundStyle(theme.statusColor(for: status))
            }
        } else if snapshot.errorMessage == nil && !snapshot.isSyncing {
            Text("—")
                .font(theme.font(size: 15, weight: .bold))
                .foregroundStyle(theme.textTertiary)
        }
    }

    // MARK: - Error

    private var errorBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(theme.font(size: 10))
                .foregroundStyle(theme.statusWarning)
            Text(snapshot.errorMessage ?? "Unavailable")
                .font(theme.font(size: 11, weight: .medium))
                .foregroundStyle(theme.textTertiary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

/// One horizontal quota bar with its scope label, remaining %, and relative
/// reset time. Used twice per provider row (5h + 7d). When `window` is nil,
/// renders a muted stub bar so the row height stays consistent across
/// providers regardless of how many windows they expose. `isPrimary` drives
/// the 0.5 opacity that anchors the user's R11 filter choice without hiding
/// the comparison data.
struct WindowBarView: View {
    let window: WindowSnapshot?
    let scopeLabel: String
    let isPrimary: Bool

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(scopeLabel)
                    .font(theme.font(size: 10, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
                    .frame(width: 22, alignment: .leading)

                if let window {
                    if window.isDollarBased, let dollars = window.formattedDollarRemaining {
                        Text(dollars)
                            .font(theme.font(size: 11, weight: .semibold))
                            .foregroundStyle(theme.statusColor(for: QuotaStatus.from(percentRemaining: window.percentRemaining)))
                    } else {
                        Text("\(Int(window.percentRemaining.rounded()))%")
                            .font(theme.font(size: 11, weight: .semibold))
                            .foregroundStyle(theme.statusColor(for: QuotaStatus.from(percentRemaining: window.percentRemaining)))
                    }

                    Text(window.compactReset ?? "·")
                        .font(theme.font(size: 11))
                        .foregroundStyle(theme.textTertiary)
                        .monospacedDigit()
                        .frame(minWidth: 34, alignment: .trailing)
                } else {
                    Text("—")
                        .font(theme.font(size: 11, weight: .medium))
                        .foregroundStyle(theme.textTertiary)
                }

                Spacer(minLength: 0)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(theme.progressTrack)
                    if let window, !window.isDollarBased {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(theme.progressGradient(for: window.percentRemaining))
                            .frame(width: max(4, geo.size.width * min(max(window.percentRemaining, 0), 100) / 100))
                    } else if window == nil {
                        // 2 % stub so the track is visible without claiming a value.
                        RoundedRectangle(cornerRadius: 3)
                            .fill(theme.textTertiary.opacity(0.3))
                            .frame(width: max(4, geo.size.width * 0.02))
                    }
                }
            }
            .frame(height: 5)
        }
        .opacity(isPrimary ? 1.0 : 0.5)
    }
}
