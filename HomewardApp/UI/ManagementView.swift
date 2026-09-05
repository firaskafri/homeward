import AppKit
import SwiftUI

struct ManagementView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var navigation: HomewardNavigationState
    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                sidebarHeader

                List(HomewardRoute.allCases) { destination in
                    Button {
                        navigation.select(destination)
                    } label: {
                        HStack {
                            Label(
                                destination.rawValue,
                                systemImage: destination.symbol
                            )
                            if destination == .savedThoughts,
                               model.availableNotesCount > 0 {
                                Spacer()
                                Text("\(model.availableNotesCount)")
                                    .monospacedDigit()
                                    .accessibilityLabel(
                                        "\(model.availableNotesCount) saved thoughts"
                                    )
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .font(.body.weight(.medium))
                    .padding(.vertical, HomewardSpacing.xSmall)
                    .listRowBackground(
                        navigation.selection == destination
                            ? HomewardTone.rest.color.opacity(0.12)
                            : Color.clear
                    )
                    .accessibilityIdentifier(
                        "navigation.\(destination.rawValue)"
                    )
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)

                Divider()

                sidebarStatus
            }
            .background(
                reduceTransparency
                    ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
                    : AnyShapeStyle(.thinMaterial)
            )
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
                title: model.presentationSnapshot.title,
                symbol: scheduleStatus.symbol,
                tone: scheduleStatus.tone
            )
            Text(
                model.presentationSnapshot.transitionText
                    ?? "No transition is available"
            )
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
