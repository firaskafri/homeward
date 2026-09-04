import SwiftUI

struct ManagementView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var navigation: HomewardNavigationState

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                sidebarHeader

                List(HomewardRoute.allCases, selection: $navigation.selection) { destination in
                    Label(destination.rawValue, systemImage: destination.symbol)
                        .font(.body.weight(.medium))
                        .padding(.vertical, HomewardSpacing.xSmall)
                        .tag(destination)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)

                Divider()

                sidebarStatus
            }
            .background(.thinMaterial)
            .navigationSplitViewColumnWidth(min: 184, ideal: 208, max: 240)
        } detail: {
            destinationView(navigation.selection ?? .today)
        }
        .frame(minWidth: 720, minHeight: 540)
        .accessibilityIdentifier("management.window")
    }

    private var sidebarHeader: some View {
        HStack(spacing: HomewardSpacing.medium) {
            ZStack {
                RoundedRectangle(
                    cornerRadius: HomewardMetrics.compactCornerRadius,
                    style: .continuous
                )
                .fill(HomewardTone.rest.color.opacity(0.14))
                Image(systemName: "house.and.flag.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(HomewardTone.rest.color)
            }
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("Homeward")
                    .font(.headline)
                Text("Your workday boundary")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, HomewardSpacing.medium)
        .padding(.top, HomewardSpacing.large)
        .padding(.bottom, HomewardSpacing.medium)
        .accessibilityElement(children: .combine)
    }

    private var sidebarStatus: some View {
        VStack(alignment: .leading, spacing: HomewardSpacing.small) {
            HomewardStatusLabel(
                title: scheduleStatus.title,
                symbol: scheduleStatus.symbol,
                tone: scheduleStatus.tone
            )
            Text(SchedulePresentation.transitionText(for: model.resolvedSchedule))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(HomewardSpacing.medium)
        .accessibilityElement(children: .combine)
    }

    private var scheduleStatus: ScheduleStatusPresentation {
        SchedulePresentation.status(
            schedule: model.resolvedSchedule,
            closingCount: model.closingRows.count
        )
    }

    @ViewBuilder
    private func destinationView(_ destination: HomewardRoute) -> some View {
        switch destination {
        case .today:
            TodayView(model: model)
        case .schedule:
            ScheduleEditorView(model: model)
        case .workApps:
            AppPickerView(model: model)
        case .closing:
            ClosingSettingsView(model: model)
        case .savedThoughts:
            NotesReviewView(
                model: model,
                onClose: { navigation.select(.today) }
            )
            .navigationTitle("Saved Thoughts")
        }
    }
}
