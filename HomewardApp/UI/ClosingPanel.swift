import AppKit
import SwiftUI

@MainActor
final class ClosingPanelController: NSWindowController, NSWindowDelegate {
    private unowned let model: AppModel

    init(model: AppModel) {
        self.model = model
        let content = ClosingPanelView(model: model)
        let hostingController = NSHostingController(rootView: content)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 320),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Closing Work Apps"
        panel.contentViewController = hostingController
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
        panel.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    var isVisible: Bool {
        window?.isVisible == true
            && window?.occlusionState.contains(.visible) == true
    }

    func show(activating: Bool = false) {
        guard let window else {
            return
        }
        window.center()
        if activating {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            window.orderFrontRegardless()
        }
    }

    func refresh() {
        window?.contentView?.needsLayout = true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model.closingRows.contains(where: { $0.status == .countingDown }) else {
            return true
        }
        Task {
            await model.stopForceQuit()
            sender.orderOut(nil)
        }
        return false
    }
}

private struct ClosingPanelView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Closing work apps")
                    .font(.title2.bold())
                Text(summary)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(model.closingRows) { row in
                        closingRow(row)
                    }
                }
            }

            HStack {
                if model.configuration.closeMode == .firm {
                    Button(stopButtonTitle) {
                        Task { await model.stopForceQuit() }
                    }
                    .accessibilityIdentifier("closing.stopForce")
                    Button("Change Today Only…") {
                        Task {
                            await model.stopForceQuit()
                            model.openManagementSettings()
                        }
                    }
                }
                Spacer()
                Button(hideButtonTitle) {
                    model.hideClosingPanel()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 240)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("closing.panel")
    }

    private var summary: String {
        let unresolved = model.closingRows.count
        return unresolved == 1
            ? "1 work app still needs attention."
            : "\(unresolved) work apps still need attention."
    }

    private var stopButtonTitle: String {
        model.closingRows.count == 1 ? "Stop Force Quit" : "Stop All Force Quits"
    }

    private var hideButtonTitle: String {
        model.closingRows.contains(where: { $0.status == .countingDown })
            ? "Stop Force Quit and Hide"
            : "Hide"
    }

    @ViewBuilder
    private func closingRow(_ row: AppModel.ClosingRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol(for: row.status))
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.applicationName)
                    .font(.headline)
                Text(statusText(for: row))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if row.status == .needsAttention || row.status == .forceFailed {
                Button("Show \(row.applicationName)") {
                    model.bringForward(sessionID: row.id)
                }
                .accessibilityIdentifier("closing.show.\(row.id)")
            }
            if model.configuration.closeMode == .gentle,
               row.status == .needsAttention {
                Button("Leave Open This Time") {
                    model.leaveOpen(sessionID: row.id)
                }
                .accessibilityIdentifier("closing.leaveOpen.\(row.id)")
            }
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("closing.row.\(row.id)")
    }

    private func symbol(for status: AppModel.ClosingRow.Status) -> String {
        switch status {
        case .requestingNormalQuit:
            "hourglass"
        case .countingDown:
            "timer"
        case .needsAttention:
            "exclamationmark.bubble"
        case .forcePaused:
            "pause.circle"
        case .forceFailed:
            "exclamationmark.triangle"
        case .leftOpen:
            "checkmark.circle"
        }
    }

    private func statusText(for row: AppModel.ClosingRow) -> String {
        switch row.status {
        case .requestingNormalQuit:
            "Waiting for the app to quit normally"
        case .countingDown:
            "Force quit in \(row.secondsRemaining ?? 0) seconds"
        case .needsAttention:
            "The app needs your attention before it can quit"
        case .forcePaused:
            "Force quit is paused"
        case .forceFailed:
            "Force quit did not close the app"
        case .leftOpen:
            "Left open this time"
        }
    }
}
