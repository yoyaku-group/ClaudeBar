import SwiftUI
import Domain
import Infrastructure

/// Machine-health card absorbing the SwiftBar `guardian.10s.sh` dots:
/// status, key metrics, findings, and the daemon's non-interactive actions.
/// Stale state (daemon mute > 3 min) renders as a warning — never green.
struct GuardianCardView: View {
    let tracker: HarUsageTracker

    @Environment(\.appTheme) private var theme

    private var state: GuardianStateReader.State? { tracker.guardian }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if let state {
                metricsGrid(state)
                if !state.findings.isEmpty {
                    Divider().overlay(theme.glassBorder)
                    ForEach(state.findings.prefix(4), id: \.rule) { finding in
                        HStack(spacing: 6) {
                            Image(systemName: finding.autoDone ? "checkmark.circle" : severityIcon(finding.severity))
                                .font(theme.font(size: 9))
                                .foregroundStyle(finding.autoDone ? theme.statusColor(for: .healthy) : severityColor(finding.severity))
                            Text(finding.message)
                                .font(theme.font(size: 10))
                                .foregroundStyle(theme.textSecondary)
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                }
            } else {
                Text("Gardien muet — état illisible")
                    .font(theme.font(size: 10))
                    .foregroundStyle(theme.textTertiary)
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

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "shield.lefthalf.filled")
                .font(theme.font(size: 11))
                .foregroundStyle(statusColor)
            Text("Machine")
                .font(theme.font(size: 12, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
            Spacer()
            if let state {
                Text(headerBadge(state))
                    .font(theme.font(size: 10, weight: .semibold))
                    .foregroundStyle(statusColor)
            }
        }
    }

    private var statusColor: Color {
        guard let state else { return theme.statusColor(for: .warning) }
        if state.isStale { return theme.statusColor(for: .warning) }
        switch state.status {
        case "green": return theme.statusColor(for: .healthy)
        case "yellow": return theme.statusColor(for: .warning)
        default: return theme.statusColor(for: .critical)
        }
    }

    private func headerBadge(_ state: GuardianStateReader.State) -> String {
        if state.isStale {
            let minutes = Int(Date().timeIntervalSince(state.capturedAt) / 60)
            return "muet (\(minutes)min)"
        }
        return state.status
    }

    private func metricsGrid(_ state: GuardianStateReader.State) -> some View {
        let m = state.metrics
        return HStack(spacing: 0) {
            metricCell("swap", value: m.swapUsedPct.map { String(format: "%.0f%%", $0) })
            metricCell("load", value: m.load1PerCore.map { String(format: "%.1f/c", $0) })
            metricCell("RAM", value: m.ramFreePct.map { String(format: "%.0f%%", $0) })
            metricCell("zombies", value: m.zombies.map(String.init))
        }
    }

    private func metricCell(_ label: String, value: String?) -> some View {
        VStack(spacing: 2) {
            Text(value ?? "·")
                .font(theme.font(size: 12, weight: .bold))
                .foregroundStyle(theme.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(theme.font(size: 8))
                .foregroundStyle(theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func severityIcon(_ severity: String) -> String {
        severity == "red" ? "exclamationmark.triangle.fill" : "exclamationmark.circle"
    }

    private func severityColor(_ severity: String) -> Color {
        severity == "red" ? theme.statusColor(for: .critical) : theme.statusColor(for: .warning)
    }
}
