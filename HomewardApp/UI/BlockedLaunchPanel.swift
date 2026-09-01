import AppKit
import SwiftUI

@MainActor
final class BlockedLaunchPanelController: NSWindowController {
    init(
        model: AppModel,
        applicationName: String,
        availabilityText: String
    ) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        let view = BlockedLaunchView(
            model: model,
            applicationName: applicationName,
            availabilityText: availabilityText,
            close: { [weak panel] in panel?.close() }
        )
        panel.title = "Work App Closed"
        panel.contentViewController = NSHostingController(rootView: view)
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
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
                   model.configuration.warningPreferences.gentleExtensionEnabled {
                    Button("Make All Work Apps Available for 10 Minutes…") {
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
