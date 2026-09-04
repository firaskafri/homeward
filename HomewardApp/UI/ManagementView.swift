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
                title: sidebarStatusTitle,
                symbol: sidebarStatusSymbol,
                tone: sidebarStatusTone
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

    private var sidebarStatusTitle: String {
        SchedulePresentation.stateTitle(
            schedule: model.resolvedSchedule,
            closingCount: model.closingRows.count
        )
    }

    private var sidebarStatusSymbol: String {
        if !model.closingRows.isEmpty {
            return "power"
        }
        return switch model.resolvedSchedule.phase {
        case .workAvailable:
            "checkmark.circle.fill"
        case .windingDown:
            "clock.fill"
        case .workClosed:
            "moon.stars.fill"
        case .temporarilyExtended:
            "clock.badge.plus"
        }
    }

    private var sidebarStatusTone: HomewardTone {
        if !model.closingRows.isEmpty {
            return .attention
        }
        return switch model.resolvedSchedule.phase {
        case .workAvailable:
            .ready
        case .windingDown, .temporarilyExtended:
            .attention
        case .workClosed:
            .rest
        }
    }

    @ViewBuilder
    private func destinationView(_ destination: HomewardRoute) -> some View {
        switch destination {
        case .today:
            OverviewView(model: model)
        case .schedule:
            ScheduleEditorView(model: model)
        case .workApps:
            AppPickerView(model: model)
        case .closing:
            ClosingSettingsView(model: model)
        case .savedThoughts:
            SavedThoughtsDestinationView(
                model: model,
                onDone: { navigation.select(.today) }
            )
        }
    }
}

private struct SavedThoughtsDestinationView: View {
    @ObservedObject var model: AppModel
    let onDone: () -> Void

    var body: some View {
        NotesReviewView(model: model, onClose: onDone)
            .navigationTitle("Saved Thoughts")
    }
}
