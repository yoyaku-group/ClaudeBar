import SwiftUI
import Domain

/// All-providers overview dashboard ("ce qu'il me reste").
///
/// Comprehension-first layout (Ben, 2026-08-18): rows sorted by worst
/// remaining percentage (or soonest reset), one-click window selector
/// Session 5h / Semaine / Tout driving both the headline number and the
/// ordering, relative reset times only, one stylized row per LLM identity.
struct OverviewDashboardView: View {
    let providers: [any AIProvider]
    @Bindable var settings: AppSettings

    @Environment(\.appTheme) private var theme

    private var rows: [ProviderSnapshot] {
        OverviewBuilder.sort(
            OverviewBuilder.build(providers: providers),
            by: settings.overviewSort,
            filter: settings.overviewWindowFilter
        )
    }

    /// Count of filtered windows under 10% remaining — the "act now" footer.
    private var criticalCount: Int {
        OverviewBuilder.build(providers: providers)
            .flatMap { $0.windows }
            .filter { settings.overviewWindowFilter.matches($0.scope) && $0.percentRemaining < 10 && !$0.isDollarBased }
            .count
    }

    var body: some View {
        VStack(spacing: 10) {
            controls
            ForEach(rows) { row in
                ProviderSnapshotRow(snapshot: row, filter: settings.overviewWindowFilter)
            }
            if criticalCount > 0 {
                footer
            }
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 8) {
            // One-click window selector (R11) — drives display AND sort key.
            Picker("Fenêtre", selection: Binding(
                get: { settings.overviewWindowFilter },
                set: { settings.overviewWindowFilter = $0 }
            )) {
                ForEach(OverviewWindowFilter.allCases) { filter in
                    Text(filter.displayName).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            // Sort mode: % restant (default) / Reset le plus proche.
            Menu {
                ForEach(OverviewSort.allCases) { sort in
                    Button {
                        settings.overviewSort = sort
                    } label: {
                        if settings.overviewSort == sort {
                            Label(sort.displayName, systemImage: "checkmark")
                        } else {
                            Text(sort.displayName)
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(theme.font(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(theme.glassBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(theme.glassBorder, lineWidth: 1)
                    )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.fill")
                .font(theme.font(size: 10))
                .foregroundStyle(theme.statusColor(for: .critical))
            Text("\(criticalCount) fenêtre\(criticalCount > 1 ? "s" : "") sous 10%")
                .font(theme.font(size: 11, weight: .medium))
                .foregroundStyle(theme.textSecondary)
            Spacer()
        }
        .padding(.vertical, 2)
    }
}
