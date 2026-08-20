import SwiftUI
import Domain
import Infrastructure

/// Kimi provider configuration card for SettingsView.
struct KimiConfigCard: View {
    let monitor: QuotaMonitor

    @State private var settings = AppSettings.shared
    @Environment(\.appTheme) private var theme

    @State private var kimiConfigExpanded: Bool = false
    @State private var kimiProbeMode: KimiProbeMode = .api

    var body: some View {
        DisclosureGroup(isExpanded: $kimiConfigExpanded) {
            Divider()
                .background(theme.glassBorder)
                .padding(.vertical, 12)

            kimiConfigForm
        } label: {
            kimiConfigHeader
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        kimiConfigExpanded.toggle()
                    }
                }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    theme.glassBorder, theme.glassBorder.opacity(0.5)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .onAppear {
            kimiProbeMode = settings.kimi.kimiProbeMode()
        }
    }

    private var kimiConfigHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [theme.accentPrimary.opacity(0.2), theme.accentSecondary.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)

                Image(systemName: "terminal")
                    .font(theme.font(size: 12, weight: .semibold))
                    .foregroundStyle(theme.accentPrimary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Kimi Configuration")
                    .font(theme.font(size: 14, weight: .bold))
                    .foregroundStyle(theme.textPrimary)

                Text("Data fetching method")
                    .font(theme.font(size: 10, weight: .medium))
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer()
        }
    }

    private var kimiConfigForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("PROBE MODE")
                    .font(theme.font(size: 9, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
                    .tracking(0.5)

                Picker("", selection: $kimiProbeMode) {
                    ForEach(KimiProbeMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: kimiProbeMode) { _, newValue in
                    settings.kimi.setKimiProbeMode(newValue)
                    Task {
                        await monitor.refresh(providerId: "kimi")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "terminal")
                        .font(theme.font(size: 10))
                        .foregroundStyle(kimiProbeMode == .cli ? theme.accentPrimary : theme.textTertiary)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("CLI Mode")
                            .font(theme.font(size: 10, weight: .semibold))
                            .foregroundStyle(kimiProbeMode == .cli ? theme.textPrimary : theme.textSecondary)

                        Text("Uses kimi CLI with /usage command. Requires kimi installed.")
                            .font(theme.font(size: 9, weight: .medium))
                            .foregroundStyle(theme.textTertiary)
                    }
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "network")
                        .font(theme.font(size: 10))
                        .foregroundStyle(kimiProbeMode == .api ? theme.accentPrimary : theme.textTertiary)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("API Mode")
                            .font(theme.font(size: 10, weight: .semibold))
                            .foregroundStyle(kimiProbeMode == .api ? theme.textPrimary : theme.textSecondary)

                        Text("Calls Kimi API directly. Uses browser cookie authentication.")
                            .font(theme.font(size: 9, weight: .medium))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
            }
        }
    }
}
