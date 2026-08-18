import SwiftUI
import Domain

/// One dashboard row: a provider (or one account of a multi-account provider)
/// with its worst filtered window as the headline, a progress bar, and one
/// compact line per window showing remaining % and relative time-to-reset
/// ("3d", "4:59"). Never mixes absolute dates — resets are relative only.
struct ProviderSnapshotRow: View {
    let snapshot: ProviderSnapshot
    let filter: OverviewWindowFilter

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    private var visibleWindows: [WindowSnapshot] {
        snapshot.windows.filter { filter.matches($0.scope) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let worst = snapshot.worstWindow(matching: filter), !worst.isDollarBased {
                progressBar(percent: worst.percentRemaining)
            }
            if snapshot.errorMessage != nil {
                errorBadge
            } else if snapshot.isSyncing {
                Text("Syncing…")
                    .font(theme.font(size: 11, weight: .medium))
                    .foregroundStyle(theme.textTertiary)
            } else {
                windowLines
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

    // MARK: - Progress

    private func progressBar(percent: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.primary.opacity(0.08))
                RoundedRectangle(cornerRadius: 3)
                    .fill(theme.progressGradient(for: percent))
                    .frame(width: max(4, geo.size.width * min(max(percent, 0), 100) / 100))
            }
        }
        .frame(height: 5)
    }

    // MARK: - Windows

    /// One compact line per window: title · % left · relative reset.
    private var windowLines: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(visibleWindows) { window in
                HStack(spacing: 6) {
                    Text(window.title)
                        .font(theme.font(size: 11, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

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
                }
            }
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
