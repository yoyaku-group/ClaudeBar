import SwiftUI
import Domain

/// A simple overlay that shows the referral link with copy functionality.
struct SharePassOverlay: View {
    let pass: ClaudePass
    let onDismiss: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @State private var copied = false
    private var isCLITheme: Bool { theme.id == "cli" }

    var body: some View {
        ZStack {
            // Dimmed background
            (isCLITheme ? CLITheme.black : Color.black).opacity(isCLITheme ? 0.68 : 0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }

            // Card
            VStack(spacing: 14) {
                // Header
                HStack {
                    Image(systemName: "gift.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isCLITheme ? theme.statusWarning : theme.accentPrimary)

                    Text(isCLITheme ? "SHARE CLAUDE CODE" : "Share Claude Code")
                        .font(.system(size: 14, weight: .bold, design: isCLITheme ? .monospaced : theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)
                        .tracking(isCLITheme ? 0.45 : 0)

                    Spacer()

                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }

                // Referral Link
                HStack(spacing: 8) {
                    Text(pass.referralURL.absoluteString)
                        .font(.system(size: 11, weight: .medium, design: isCLITheme ? .monospaced : theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Button {
                        copyToClipboard()
                    } label: {
                        Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(copied ? theme.statusHealthy : theme.accentPrimary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isCLITheme ? AnyShapeStyle(theme.cardGradient) : AnyShapeStyle(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isCLITheme ? theme.glassBorder.opacity(0.9) : Color.clear, lineWidth: 1)
                        )
                )

                // Action buttons
                HStack(spacing: 10) {
                    Button {
                        copyToClipboard()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11, weight: .semibold))
                            Text(copied ? "Copied!" : "Copy Link")
                                .font(.system(size: 11, weight: .medium, design: isCLITheme ? .monospaced : theme.fontDesign))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            Capsule()
                                .fill(theme.accentGradient)
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        NSWorkspace.shared.open(pass.referralURL)
                        onDismiss()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "safari")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Open")
                                .font(.system(size: 11, weight: .medium, design: isCLITheme ? .monospaced : theme.fontDesign))
                        }
                        .foregroundStyle(theme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: isCLITheme ? 10 : 999)
                                .fill(theme.glassBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: isCLITheme ? 10 : 999)
                                        .stroke(theme.glassBorder, lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Help text
                Text("Share a free week of Claude Code with friends")
                    .font(.system(size: 10, weight: .semibold, design: isCLITheme ? .monospaced : theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
                    .tracking(isCLITheme ? 0.15 : 0)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isCLITheme ? AnyShapeStyle(theme.cardGradient) : AnyShapeStyle(theme.glassBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(theme.glassBorder, lineWidth: 1)
                    )
                    .shadow(color: (isCLITheme ? theme.accentSecondary : Color.black).opacity(isCLITheme ? 0.12 : 0.4), radius: isCLITheme ? 10 : 20, y: isCLITheme ? 4 : 10)
            )
            .padding(.horizontal, 24)
        }
        .transition(.opacity)
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pass.referralURL.absoluteString, forType: .string)

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            copied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeOut(duration: 0.3)) {
                copied = false
            }
        }
    }
}

// MARK: - Preview

#Preview("SharePassOverlay") {
    ZStack {
        DarkTheme().backgroundGradient

        SharePassOverlay(
            pass: ClaudePass(
                referralURL: URL(string: "https://claude.ai/referral/DJ_kWX90Xw")!
            ),
            onDismiss: {}
        )
    }
    .frame(width: 380, height: 400)
}
