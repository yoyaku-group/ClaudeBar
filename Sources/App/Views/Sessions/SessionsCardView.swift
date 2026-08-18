import SwiftUI
import Domain

/// "Ce que j'utilise" card: live + 24h session counts per harness, and the
/// Claude lifecycle timeline (forks, compactions) — Ben's ask, 2026-08-18.
struct SessionsCardView: View {
    let tracker: HarUsageTracker
    let sessionMonitor: SessionMonitor

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(theme.font(size: 11))
                    .foregroundStyle(theme.textSecondary)
                Text("Sessions")
                    .font(theme.font(size: 12, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                if let liveClaude = tracker.liveClaude {
                    Text("\(liveClaude) live")
                        .font(theme.font(size: 10))
                        .foregroundStyle(theme.textTertiary)
                }
            }

            HStack(spacing: 0) {
                harnessCell("Claude", systemImage: "brain.head.profile",
                            live: tracker.liveClaude, day: tracker.counts24h?.claude)
                harnessCell("Codex", systemImage: "chevron.left.forwardslash.chevron.right",
                            live: tracker.liveCodex, day: tracker.counts24h?.codex)
                harnessCell("Kimi", systemImage: "k.square.fill",
                            live: nil, day: tracker.counts24h?.kimi)
                harnessCell("Qwen", systemImage: "q.square.fill",
                            live: nil, day: tracker.counts24h?.qwen)
            }

            if !sessionMonitor.recentNotableEvents.isEmpty {
                Divider().overlay(theme.glassBorder)
                ForEach(Array(sessionMonitor.recentNotableEvents.prefix(6).enumerated()), id: \.offset) { _, event in
                    timelineRow(event)
                }
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

    // MARK: - Cells

    private func harnessCell(_ name: String, systemImage: String, live: Int?, day: Int?) -> some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(theme.font(size: 13, weight: .semibold))
                .foregroundStyle(day.map { _ in theme.textPrimary } ?? theme.textTertiary)
            Text(name)
                .font(theme.font(size: 9))
                .foregroundStyle(theme.textTertiary)
            Text("24h")
                .font(theme.font(size: 8))
                .foregroundStyle(theme.textTertiary.opacity(0.6))
            Text(day.map(String.init) ?? "·")
                .font(theme.font(size: 13, weight: .bold))
                .foregroundStyle(theme.textPrimary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Timeline

    @ViewBuilder
    private func timelineRow(_ event: SessionEvent) -> some View {
        let label: String
        let icon: String
        switch event.eventName {
        case .preCompact:
            label = "Compaction…"
            icon = "arrow.down.circle"
        case .postCompact:
            label = "Compaction terminée"
            icon = "checkmark.circle"
        case .sessionStart where event.source == "fork":
            label = "Session forked"
            icon = "arrow.triangle.branch"
        default:
            label = event.eventName.rawValue
            icon = "circle"
        }
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(theme.font(size: 9))
                .foregroundStyle(theme.textTertiary)
            Text(label)
                .font(theme.font(size: 10, weight: .medium))
                .foregroundStyle(theme.textSecondary)
            Spacer()
            Text(event.receivedAt, style: .relative)
                .font(theme.font(size: 9))
                .foregroundStyle(theme.textTertiary)
        }
    }
}
