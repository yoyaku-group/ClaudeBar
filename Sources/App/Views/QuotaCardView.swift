import SwiftUI
import Domain

/// A card view displaying a single quota metric.
/// Directly uses the rich domain model - no ViewModel needed.
struct QuotaCardView: View {
    let quota: UsageQuota

    @Environment(\.appTheme) private var theme
    @State private var settings = AppSettings.shared
    private var isCLITheme: Bool { theme.id == "cli" }

    private var displayMode: UsageDisplayMode {
        settings.usageDisplayMode
    }

    /// Effective display mode: falls back to .used when pace is unknown
    private var effectiveDisplayMode: UsageDisplayMode {
        if displayMode == .pace && quota.pace == .unknown {
            return .used
        }
        return displayMode
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCLITheme ? 8 : 4) {
            HStack(alignment: .top, spacing: 8) {
                Text(quota.quotaType.displayName.uppercased())
                    .font(.system(size: 8, weight: .semibold, design: isCLITheme ? .monospaced : .default))
                    .foregroundStyle(theme.textSecondary)
                    .tracking(isCLITheme ? 0.8 : 0)

                Spacer(minLength: 6)

                Text(quotaBadgeText)
                    .badge(statusColor)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(quota.displayPercent(mode: effectiveDisplayMode)))")
                    .font(.system(size: isCLITheme ? 28 : 24, weight: .heavy, design: isCLITheme ? .monospaced : .rounded))
                    .foregroundStyle(theme.textPrimary)
                    .contentTransition(.numericText())

                Text("%")
                    .font(.system(size: isCLITheme ? 14 : 12, weight: .bold, design: isCLITheme ? .monospaced : .rounded))
                    .foregroundStyle(statusColor)

                Spacer(minLength: 6)

                Text(displayDescriptor)
                    .font(.system(size: 8, weight: .semibold, design: isCLITheme ? .monospaced : .default))
                    .foregroundStyle(theme.textSecondary)
                    .tracking(isCLITheme ? 0.35 : 0)
            }

            VStack(alignment: .leading, spacing: 2) {
                GeometryReader { geometry in
                    let progressPercent = quota.displayProgressPercent(mode: effectiveDisplayMode)
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: isCLITheme ? 3 : 2)
                            .fill(theme.progressTrack)
                            .frame(height: isCLITheme ? 6 : 4)

                        RoundedRectangle(cornerRadius: isCLITheme ? 3 : 2)
                            .fill(theme.progressGradient(for: progressPercent))
                            .frame(width: geometry.size.width * max(0, min(100, progressPercent)) / 100, height: isCLITheme ? 6 : 4)
                    }
                }
                .frame(height: isCLITheme ? 6 : 4)

                if let expectedPercent = quota.expectedProgressPercent(mode: effectiveDisplayMode) {
                    GeometryReader { geometry in
                        let tickX = geometry.size.width * max(0, min(100, expectedPercent)) / 100
                        Path { path in
                            path.move(to: CGPoint(x: tickX - 4, y: 5))
                            path.addLine(to: CGPoint(x: tickX + 4, y: 5))
                            path.addLine(to: CGPoint(x: tickX, y: 0))
                            path.closeSubpath()
                        }
                        .fill(isCLITheme ? theme.accentSecondary.opacity(0.85) : Color.secondary.opacity(0.6))
                    }
                    .frame(height: 6)
                }
            }

            HStack(spacing: 4) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(theme.textTertiary)

                Text(resetLabel)
                    .font(.system(size: 8, weight: .semibold, design: isCLITheme ? .monospaced : .default))
                    .foregroundStyle(theme.textTertiary)
                    .tracking(isCLITheme ? 0.2 : 0)
            }
        }
        .padding(isCLITheme ? 13 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: isCLITheme ? theme.cardCornerRadius : 8)
                    .fill(isCLITheme ? AnyShapeStyle(theme.cardGradient) : AnyShapeStyle(Color.primary.opacity(0.05)))

                RoundedRectangle(cornerRadius: isCLITheme ? theme.cardCornerRadius : 8)
                    .stroke((isCLITheme ? theme.glassBorder : statusColor).opacity(isCLITheme ? 0.9 : 0.12), lineWidth: 1)

                if isCLITheme {
                    RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                        .stroke(
                            LinearGradient(
                                colors: [theme.accentSecondary.opacity(0.12), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            }
        )
    }

    private var statusColor: Color {
        effectiveDisplayMode == .pace ? quota.pace.displayColor : quota.status.displayColor
    }

    private var displayDescriptor: String {
        switch effectiveDisplayMode {
        case .used:
            return "USED"
        case .remaining:
            return "REMAINING"
        case .pace:
            return "PACE"
        }
    }

    private var resetLabel: String {
        quota.resetTimestampDescription ?? quota.resetText ?? quota.resetDescription ?? "Reset unknown"
    }

    private var quotaBadgeText: String {
        effectiveDisplayMode == .pace && quota.pace != .unknown
            ? quota.pace.badgeText
            : quota.status.badgeText
    }
}
