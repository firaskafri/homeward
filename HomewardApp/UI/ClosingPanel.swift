import AppKit
import SwiftUI

@MainActor
final class ClosingPanelController: NSWindowController, NSWindowDelegate {
    private unowned let model: AppModel
    private weak var previousApplication: NSRunningApplication?

    init(model: AppModel) {
        self.model = model
        let content = ClosingPanelView(model: model)
        let hostingController = NSHostingController(rootView: content)
        let panel = HomewardPanelFactory.make(
            title: "Closing Work Apps",
            size: NSSize(width: 560, height: 440),
            minimumSize: NSSize(width: 480, height: 320),
            resizable: true,
            floatsAcrossSpaces: true
        )
        panel.level = NSWindow.Level(
            rawValue: NSWindow.Level.floating.rawValue + 1
        )
        panel.contentViewController = hostingController
        super.init(window: panel)
        panel.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    var isVisibleAndUnoccluded: Bool {
        window?.isVisibleAndUnoccluded == true
    }

    func show(activating: Bool = false) {
        guard let window else {
            return
        }
        window.center()
        if activating {
            if !window.isVisible {
                previousApplication =
                    NSWorkspace.shared.frontmostApplication
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            window.orderFrontRegardless()
        }
    }

    func windowWillClose(_ notification: Notification) {
        restorePreviousApplication()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model.closingRows.contains(where: {
            $0.status == .countingDown
        }) else {
            return true
        }
        Task {
            await model.stopForceQuit()
            sender.orderOut(nil)
            restorePreviousApplication()
        }
        return false
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard window?.isVisibleAndUnoccluded == false else {
            return
        }
        pauseIfArmed()
    }

    func windowDidMiniaturize(_ notification: Notification) {
        pauseIfArmed()
    }

    private func pauseIfArmed() {
        guard model.closingRows.contains(where: {
            $0.status == .countingDown
        }) else {
            return
        }
        Task {
            await model.stopForceQuit()
        }
    }

    private func restorePreviousApplication() {
        previousApplication?.activate(options: [.activateAllWindows])
        previousApplication = nil
    }
}

private struct ClosingPanelView: View {
    private enum FocusTarget: Hashable {
        case stop
    }

    @ObservedObject var model: AppModel
    @FocusState private var focusedAction: FocusTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HomewardPanelHeader(
                title: "Closing work apps",
                message: summary,
                systemImage: "moon.stars.fill",
                tone: .rest
            )

            if let error = model.lastError {
                InlineErrorView(message: error) {
                    model.clearError()
                }
            }

            Group {
                if model.closingRows.isEmpty {
                    ContentUnavailableView(
                        "No apps are closing",
                        systemImage: "checkmark.circle",
                        description: Text("The closing flow is complete.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(model.closingRows) { row in
                                closingRow(row)
                            }
                        }
                    }
                    .scrollIndicators(.visible)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 10) {
                Divider()

                if hasActiveCountdown {
                    Label(
                        "Hiding this window also stops force quit for this blocked period.",
                        systemImage: "hand.raised"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
                }

                HStack {
                    if model.configuration.closeMode == .firm {
                        Button(stopButtonTitle) {
                            Task { await model.stopForceQuit() }
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityHint(
                            "Pauses force quitting for the current blocked period"
                        )
                        .accessibilityIdentifier("closing.stopForce")
                        .focused($focusedAction, equals: .stop)

                        Button("Change Today Only…") {
                            Task {
                                await model.stopForceQuit()
                                model.hideClosingPanel()
                                model.showTodayChangePanel()
                            }
                        }
                        .accessibilityHint(
                            "Stops force quitting before opening today-only options"
                        )
                    }

                    Spacer()

                    Button(hasActiveCountdown ? "Stop Force Quit and Hide" : "Hide") {
                        if hasActiveCountdown {
                            Task {
                                await model.stopForceQuit()
                                model.hideClosingPanel()
                            }
                        } else {
                            model.hideClosingPanel()
                        }
                    }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityHint(hideButtonHint)
                }
            }
        }
        .padding(HomewardSpacing.xLarge)
        .frame(minWidth: 460, minHeight: 300)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("closing.panel")
        .onAppear {
            if hasActiveCountdown {
                focusedAction = .stop
            }
        }
        .onChange(of: hasActiveCountdown) { wasActive, isActive in
            if !wasActive, isActive {
                focusedAction = .stop
            }
        }
    }

    private var summary: String {
        let count = model.closingRows.count
        let apps = count == 1 ? "1 work app" : "\(count) work apps"
        if model.configuration.closeMode == .firm, hasActiveCountdown {
            return "\(apps) remain open. Homeward will force quit them when their countdowns end; unsaved changes may be lost."
        }
        if model.configuration.closeMode == .firm {
            return "\(apps) remain in the firm closing flow. Review each app’s status below."
        }
        return "\(apps) remain open. Homeward is waiting for them to quit normally."
    }

    private var stopButtonTitle: String {
        model.closingRows.count == 1 ? "Stop Force Quit" : "Stop All Force Quits"
    }

    private var hasActiveCountdown: Bool {
        model.closingRows.contains(where: { $0.status == .countingDown })
    }

    private var hideButtonHint: String {
        hasActiveCountdown
            ? "Stops force quitting before hiding this window"
            : "Hides this window"
    }

    @ViewBuilder
    private func closingRow(_ row: AppModel.ClosingRow) -> some View {
        let rowTone = tone(for: row.status)
        let rowStatusText = statusText(for: row)
        HomewardCard(padding: HomewardSpacing.medium) {
            VStack(alignment: .leading, spacing: HomewardSpacing.medium) {
                HStack(alignment: .top, spacing: HomewardSpacing.medium) {
                    Image(systemName: symbol(for: row.status))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(rowTone.color)
                        .frame(width: 32, height: 32)
                        .background(
                            rowTone.color.opacity(0.12),
                            in: RoundedRectangle(
                                cornerRadius: HomewardMetrics.compactCornerRadius,
                                style: .continuous
                            )
                        )
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: HomewardSpacing.xSmall) {
                        Text(row.applicationName)
                            .font(.headline)
                        Text(rowStatusText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: HomewardSpacing.medium)

                    if row.status == .countingDown, let seconds = row.secondsRemaining {
                        HomewardStatusLabel(
                            title: "\(seconds)s",
                            symbol: "timer",
                            tone: .attention
                        )
                        .accessibilityLabel("\(seconds) seconds remaining")
                    }
                }

                if row.status == .needsAttention || row.status == .forceFailed {
                    HStack {
                        Spacer()
                        Button("Show \(row.applicationName)") {
                            model.bringForward(sessionID: row.id)
                        }
                        .accessibilityHint("Brings the application to the front")
                        .accessibilityIdentifier("closing.show.\(row.id)")

                        if model.configuration.closeMode == .gentle,
                           row.status == .needsAttention {
                            Button("Leave Open This Time") {
                                model.leaveOpen(sessionID: row.id)
                            }
                            .accessibilityHint(
                                "Exempts this application until it closes"
                            )
                            .accessibilityIdentifier("closing.leaveOpen.\(row.id)")
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(row.applicationName)
        .accessibilityValue(rowStatusText)
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
        }
    }

    private func tone(for status: AppModel.ClosingRow.Status) -> HomewardTone {
        switch status {
        case .requestingNormalQuit:
            .neutral
        case .countingDown, .needsAttention:
            .attention
        case .forcePaused:
            .rest
        case .forceFailed:
            .critical
        }
    }

    private func statusText(for row: AppModel.ClosingRow) -> String {
        switch row.status {
        case .requestingNormalQuit:
            "Waiting for the app to quit normally"
        case .countingDown:
            "Force quit is scheduled; unsaved changes may be lost"
        case .needsAttention:
            "The app needs your attention before it can quit"
        case .forcePaused:
            "Force quitting is paused for this blocked period"
        case .forceFailed:
            "Force quit did not close the app; open it to review"
        }
    }
}
