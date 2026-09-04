import AppKit
import SwiftUI

@MainActor
final class TodayChangePanelController: HomewardInvokedPanelController {
    init(model: AppModel) {
        let panel = HomewardPanelFactory.make(
            title: "Change Today Only",
            size: NSSize(width: 420, height: 320)
        )
        panel.contentViewController = NSHostingController(
            rootView: TodayChangePanelView(
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

struct TodayChangePanelView: View {
    @ObservedObject var model: AppModel
    let onClose: () -> Void
    @State private var confirmTakeDayOff = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Change today only")
                .font(.title2.bold())
            Text(TodayActionPresentation.contextDescription)
                .foregroundStyle(.secondary)
            if let error = model.lastError {
                InlineErrorView(message: error) {
                    model.clearError()
                }
            }

            ForEach(model.todayActions, id: \.self) { action in
                Button(action.title) {
                    perform(action)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(HomewardSpacing.panelInset)
        .frame(minWidth: 400, minHeight: 300)
        .confirmationDialog(
            TodayActionPresentation.takeDayOffConfirmationTitle,
            isPresented: $confirmTakeDayOff
        ) {
            Button(
                TodayActionPresentation.takeDayOffConfirmationActionTitle,
                role: .destructive
            ) {
                apply { await model.takeTodayOff() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(TodayActionPresentation.takeDayOffConfirmationMessage)
        }
        .accessibilityIdentifier("today.changePanel")
    }

    private func perform(_ action: TodayActionPresentation.Action) {
        switch action {
        case let .extend(minutes):
            apply { await model.createExtension(minutes: minutes) }
        case .chooseCutoff:
            onClose()
            model.showCustomCutoff()
        case .makeAvailable:
            apply { await model.makeWorkAvailableNow() }
        case .takeDayOff:
            confirmTakeDayOff = true
        case .returnToWeeklySchedule:
            apply { await model.returnToWeeklySchedule() }
        }
    }

    private func apply(_ action: @escaping @MainActor () async -> Bool) {
        model.clearError()
        Task {
            if await action() {
                onClose()
            }
        }
    }
}
