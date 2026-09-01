import SwiftUI

struct ManagementView: View {
    enum Destination: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case schedule = "Schedule"
        case workApps = "Work Apps"
        case closing = "Closing"
        case general = "General"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .overview:
                "house"
            case .schedule:
                "calendar"
            case .workApps:
                "square.grid.2x2"
            case .closing:
                "power"
            case .general:
                "gearshape"
            }
        }
    }

    @ObservedObject var model: AppModel
    @State private var selection: Destination? = .overview

    var body: some View {
        NavigationSplitView {
            List(Destination.allCases, selection: $selection) { destination in
                Label(destination.rawValue, systemImage: destination.symbol)
                    .tag(destination)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            destinationView(selection ?? .overview)
        }
        .frame(minWidth: 680, minHeight: 520)
        .accessibilityIdentifier("management.window")
    }

    @ViewBuilder
    private func destinationView(_ destination: Destination) -> some View {
        switch destination {
        case .overview:
            OverviewView(model: model)
        case .schedule:
            ScheduleEditorView(model: model)
        case .workApps:
            AppPickerView(model: model)
        case .closing:
            ClosingSettingsView(model: model)
        case .general:
            GeneralSettingsView(model: model)
        }
    }
}
