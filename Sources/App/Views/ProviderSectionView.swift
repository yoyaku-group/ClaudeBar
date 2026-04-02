import SwiftUI
import Domain

/// A section showing all quotas for a single AI provider.
/// Uses the rich UsageSnapshot domain model directly.
struct ProviderSectionView: View {
    let snapshot: UsageSnapshot
    
    @Environment(\.appTheme) private var theme
    private var isCLITheme: Bool { theme.id == "cli" }

    var body: some View {
        VStack(alignment: .leading, spacing: isCLITheme ? 14 : 12) {
            // Header
            HStack(alignment: .center, spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: isCLITheme ? 7 : 8, height: isCLITheme ? 7 : 8)
                    .overlay(
                        Circle()
                            .stroke(statusColor.opacity(isCLITheme ? 0.85 : 0), lineWidth: isCLITheme ? 1 : 0)
                            .frame(width: isCLITheme ? 11 : 8, height: isCLITheme ? 11 : 8)
                    )

                Text(providerDisplayName)
                    .font(.system(size: isCLITheme ? 15 : 17, weight: .bold, design: isCLITheme ? .monospaced : .rounded))
                    .foregroundStyle(theme.textPrimary)
                    .tracking(isCLITheme ? 0.25 : 0)

                Spacer()

                if let email = snapshot.accountEmail {
                    Text(email)
                        .font(.system(size: 10, weight: .medium, design: isCLITheme ? .monospaced : .default))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.bottom, isCLITheme ? 2 : 0)

            // Quota grid
            LazyVGrid(columns: gridColumns, spacing: 8) {
                ForEach(snapshot.quotas, id: \.quotaType) { quota in
                    QuotaCardView(quota: quota)
                }
            }

            // Age indicator
            HStack(spacing: 6) {
                Text("Updated \(snapshot.ageDescription)")
                    .font(.system(size: 9, weight: .semibold, design: isCLITheme ? .monospaced : .default))
                    .foregroundStyle(theme.textTertiary)
                    .tracking(isCLITheme ? 0.2 : 0)

                if snapshot.isStale {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isCLITheme ? theme.statusWarning : .orange)
                }
            }
        }
        .padding(isCLITheme ? 14 : 16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                    .fill(theme.cardGradient)

                RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                    .stroke(theme.glassBorder.opacity(isCLITheme ? 0.92 : 0.55), lineWidth: 1)

                if isCLITheme {
                    RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                        .stroke(
                            LinearGradient(
                                colors: [theme.accentSecondary.opacity(0.14), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            }
        )
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
        ]
    }

    private var providerDisplayName: String {
        ProviderVisualIdentityLookup.name(for: snapshot.providerId)
    }
    
    private var statusColor: Color {
        theme.statusColor(for: snapshot.overallStatus)
    }
}
