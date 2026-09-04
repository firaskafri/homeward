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
            size: NSSize(width: 560, height: 360),
            minimumSize: NSSize(width: 480, height: 300),
            resizable: true,
            floatsAcrossSpaces: true
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
    @State private var isApplyingExtension = false
    let applicationName: String
    let availabilityText: String
    let close: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HomewardPanelHeader(
                    title: "\(applicationName) stayed closed",
                    message: "Homeward noticed this app open outside your work schedule and closed it.",
                    systemImage: "lock.shield.fill",
                    tone: .rest
                )

                HomewardCard(padding: HomewardSpacing.medium) {
                    VStack(alignment: .leading, spacing: HomewardSpacing.medium) {
                        Label(availabilityText, systemImage: "calendar.badge.clock")
                            .font(.headline)
                            .accessibilityElement(children: .combine)

                        Divider()

                        Text(
                            "Opening the app again while work is blocked will close it again. "
                                + "Your weekly schedule has not changed."
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let error = model.lastError {
                    InlineErrorView(message: error) {
                        model.clearError()
                    }
                }

                if model.canUseGentleShortcutExtension {
                    Button {
                        applyGentleExtension()
                    } label: {
                        if isApplyingExtension {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Updating Availability…")
                            }
                        } else {
                            Text(
                                "Allow All Work Apps for "
                                    + "\(HomewardPolicy.gentleShortcutExtensionMinutes) Minutes"
                            )
                        }
                    }
                    .disabled(isApplyingExtension)
                    .accessibilityHint(
                        "Temporarily changes availability for all selected work apps"
                    )
                }

                Divider()

                HStack {
                    Button("Save a Thought…") {
                        close()
                        model.showNoteCapture()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint(
                        "Closes this message and opens a note editor"
                    )

                    Spacer()

                    Button("Close") {
                        close()
                    }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityHint("Leaves the current schedule unchanged")
                }
            }
            .padding(HomewardSpacing.xLarge)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.visible)
        .frame(minWidth: 460, minHeight: 280)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("blockedLaunch.panel")
    }

    private func applyGentleExtension() {
        model.clearError()
        isApplyingExtension = true
        Task { @MainActor in
            await model.useGentleShortcutExtension()
            isApplyingExtension = false
            if model.lastError == nil {
                close()
            }
        }
    }
}
