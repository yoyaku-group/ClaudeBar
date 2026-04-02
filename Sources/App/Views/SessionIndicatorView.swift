import SwiftUI
import Domain

/// Displays the current Claude Code session status in the menu popover.
/// Shown when there's an active session (SessionMonitor.activeSession != nil).
struct SessionIndicatorView: View {
    let session: ClaudeSession

    @Environment(\.appTheme) private var theme
    private var isCLITheme: Bool { theme.id == "cli" }

    var body: some View {
        HStack(spacing: 10) {
            // Phase indicator dot
            Circle()
                .fill(phaseColor)
                .frame(width: isCLITheme ? 7 : 8, height: isCLITheme ? 7 : 8)
                .overlay(
                    Circle()
                        .fill(phaseColor.opacity(0.4))
                        .frame(width: isCLITheme ? 11 : 14, height: isCLITheme ? 11 : 14)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(isCLITheme ? "CLAUDE CODE" : "Claude Code")
                        .font(.system(size: 11, weight: .semibold, design: isCLITheme ? .monospaced : theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)
                        .tracking(isCLITheme ? 0.45 : 0)

                    Text(phaseLabel)
                        .font(.system(size: 9, weight: .bold, design: isCLITheme ? .monospaced : theme.fontDesign))
                        .foregroundStyle(isCLITheme ? theme.textPrimary : phaseLabelColor)
                        .tracking(isCLITheme ? 0.35 : 0)
                        .padding(.horizontal, isCLITheme ? 7 : 6)
                        .padding(.vertical, isCLITheme ? 3 : 2)
                        .background(
                            RoundedRectangle(cornerRadius: isCLITheme ? 5 : 999)
                                .fill(isCLITheme ? phaseColor.opacity(0.18) : phaseColor.opacity(0.15))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: isCLITheme ? 5 : 999)
                                .stroke(phaseColor.opacity(isCLITheme ? 0.75 : 0), lineWidth: isCLITheme ? 1 : 0)
                        )
                }

                HStack(spacing: 8) {
                    if session.completedTaskCount > 0 {
                        Label("\(session.completedTaskCount) tasks", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 9, weight: .medium, design: isCLITheme ? .monospaced : theme.fontDesign))
                            .foregroundStyle(theme.textSecondary)
                    }

                    if session.activeSubagentCount > 0 {
                        Label("\(session.activeSubagentCount) agents", systemImage: "person.2.fill")
                            .font(.system(size: 9, weight: .medium, design: isCLITheme ? .monospaced : theme.fontDesign))
                            .foregroundStyle(theme.textSecondary)
                    }

                    Text(session.durationDescription)
                        .font(.system(size: 9, weight: .medium, design: isCLITheme ? .monospaced : theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)

                    Spacer()

                    // Working directory (last path component)
                    Text(cwdShort)
                        .font(.system(size: 9, weight: .medium, design: isCLITheme ? .monospaced : theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }
                .tracking(isCLITheme ? 0.2 : 0)
            }
        }
        .padding(isCLITheme ? 11 : 12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                    .fill(theme.cardGradient)

                RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                    .stroke((isCLITheme ? theme.glassBorder : phaseColor).opacity(isCLITheme ? 0.9 : 0.3), lineWidth: 1)

                if isCLITheme {
                    RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                        .stroke(theme.accentSecondary.opacity(0.14), lineWidth: 1)
                }
            }
        )
    }

    // MARK: - Phase Display

    private var phaseLabel: String { session.phase.label }
    private var phaseColor: Color { session.phase.color }

    private var phaseLabelColor: Color {
        session.phase == .ended ? theme.textTertiary : session.phase.color
    }

    private var cwdShort: String {
        (session.cwd as NSString).lastPathComponent
    }
}
