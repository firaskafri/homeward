import AppKit
import HomewardCore
import SwiftUI

@MainActor
final class CustomCutoffPanelController: HomewardInvokedPanelController {
    init(model: AppModel) {
        let panel = HomewardPanelFactory.make(
            title: "Choose Another Cutoff",
            size: NSSize(width: 440, height: 220)
        )
        panel.contentViewController = NSHostingController(
            rootView: CustomCutoffView(
                model: model,
                onClose: { [weak panel] in panel?.close() }
            )
        )
        super.init(window: panel)
        panel.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        showInvoked()
    }
}

struct CustomCutoffView: View {
    @ObservedObject var model: AppModel
    @State private var cutoff: Date
    private let earliestCutoff: Date
    private let latestCutoff: Date
    let onClose: () -> Void

    init(model: AppModel, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
        let now = Date()
        let calendar = Calendar.autoupdatingCurrent
        let midnight = ScheduleResolver().nextLocalDayBoundary(
            after: now,
            calendar: calendar
        )
        earliestCutoff = now
        latestCutoff = midnight
        _cutoff = State(
            initialValue: min(
                now.addingTimeInterval(
                    HomewardPolicy.customCutoffDefaultLeadTime
                ),
                midnight
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HomewardSpacing.large) {
            Text("Choose another cutoff")
                .font(.title2.bold())
            DatePicker(
                "Work apps available until",
                selection: $cutoff,
                in: earliestCutoff...latestCutoff
            )
            Text(cutoff.formatted(date: .abbreviated, time: .shortened))
                .foregroundStyle(.secondary)
            if let error = model.lastError {
                InlineErrorView(message: error) {
                    model.clearError()
                }
            }
            HStack {
                Spacer()
                Button("Cancel") {
                    onClose()
                }
                .keyboardShortcut(.cancelAction)
                Button("Apply Cutoff") {
                    Task {
                        model.clearError()
                        if await model.chooseCutoff(cutoff) {
                            onClose()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(HomewardSpacing.panelInset)
        .frame(minWidth: 420)
        .accessibilityIdentifier("today.customCutoff")
    }
}
