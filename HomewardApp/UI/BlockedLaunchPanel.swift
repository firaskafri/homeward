import AppKit
import HomewardCore
import SwiftUI

@MainActor
final class BlockedLaunchPanelController: NSWindowController {
    init(
        model: AppModel,
        applicationName: String,
        availabilityText: String
    ) {
        let panel = HomewardPanelFactory.make(
            title: "Work App Closed",
            size: NSSize(width: 420, height: 220),
            floatsAutomatically: true
        )
        let view = BlockedLaunchView(
            model: model,
            applicationName: applicationName,
            availabilityText: availabilityText,
            close: { [weak panel] in panel?.close() }
        )
        panel.contentViewController = NSHostingController(rootView: view)
        super.init(window: panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        window?.center()
        window?.orderFrontRegardless()
    }
}

private struct BlockedLaunchView: View {
    @ObservedObject var model: AppModel
    let applicationName: String
    let availabilityText: String
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(applicationName) is off for now")
                .font(.title2.bold())
            Text(availabilityText)
                .foregroundStyle(.secondary)
            Text("Homeward closes selected apps immediately after they open during blocked hours.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Button("Save a Thought…") {
                    close()
                    model.showNoteCapture()
                }
                if model.configuration.closeMode == .gentle,
                   model.configuration.gentleShortcutExtensionEnabled {
                    Button(
                        "Make All Work Apps Available for "
                            + "\(HomewardPolicy.gentleShortcutExtensionMinutes) Minutes…"
                    ) {
                        close()
                        Task { await model.useGentleShortcutExtension() }
                    }
                }
                Spacer()
                Button("Close") {
                    close()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 400, minHeight: 200)
        .accessibilityIdentifier("blockedLaunch.panel")
    }
}
