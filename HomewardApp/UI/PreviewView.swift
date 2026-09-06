import SwiftUI

struct PreviewView: View {
    private struct Presentation {
        let title: String
        let text: String
        let symbol: String
        let color: Color
    }

    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectionID: UUID?
    @State private var showEndConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: HomewardSpacing.panelInset) {
            VStack(alignment: .leading, spacing: HomewardSpacing.small) {
                Label("Preview the handoff", systemImage: "play.circle")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("preview.view")
                Text(
                    "Choose a harmless app and open it first. "
                        + "The preview requests a normal quit and never force-quits."
                )
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            GroupBox("Application") {
                Picker("Application", selection: $selectionID) {
                    Text("Choose an app").tag(UUID?.none)
                    ForEach(model.configuration.selectedApplications.filter {
                        $0.isResolvable && !$0.isProtected
                    }) { application in
                        Text(application.displayName).tag(Optional(application.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HomewardCard {
                HStack(alignment: .top, spacing: HomewardSpacing.medium) {
                    Image(systemName: previewPresentation.symbol)
                        .font(.title3)
                        .foregroundStyle(previewPresentation.color)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(previewPresentation.title)
                            .font(.headline)
                        Text(previewPresentation.text)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("preview.status")

            ViewThatFits(in: .horizontal) {
                HStack {
                    Button("End Preview") {
                        requestEndPreview()
                    }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("preview.end")
                    if model.previewState.canShowApplication {
                        Button("Show App") {
                            model.showPreviewApplication()
                        }
                    }
                    Spacer()
                    runPreviewButton
                }
                VStack(alignment: .leading, spacing: 10) {
                    runPreviewButton
                    if model.previewState.canShowApplication {
                        Button("Show App") {
                            model.showPreviewApplication()
                        }
                    }
                    Button("End Preview") {
                        requestEndPreview()
                    }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("preview.end")
                }
            }
        }
        .padding(HomewardSpacing.xLarge)
        .frame(minWidth: 460, minHeight: 320)
        .onDisappear {
            model.endPreview()
        }
        .confirmationDialog(
            "End preview?",
            isPresented: $showEndConfirmation
        ) {
            Button("End Preview", role: .destructive) {
                endPreviewAndDismiss()
            }
            Button("Continue Preview", role: .cancel) {}
        } message: {
            Text(
                "Ending preview prevents later preview steps. "
                    + "A normal quit the app already accepted cannot be undone."
            )
        }
    }

    private var runPreviewButton: some View {
        Button("Run Preview") {
            guard let selectionID else {
                return
            }
            model.startPreview(selectionID: selectionID)
        }
        .disabled(selectionID == nil || previewIsRunning)
        .keyboardShortcut(.defaultAction)
    }

    private var previewIsRunning: Bool {
        switch model.previewState {
        case .idle, .complete, .needsAttention:
            false
        case .waitingForFirstExit, .waitingForRelaunch, .waitingForSecondExit:
            true
        }
    }

    private var previewPresentation: Presentation {
        switch model.previewState {
        case .idle:
            Presentation(
                title: "Ready to test",
                text: "Choose a harmless selected app, open it, then run the preview.",
                symbol: "info.circle",
                color: .secondary
            )
        case let .waitingForFirstExit(name):
            Presentation(
                title: "Closing normally",
                text: "Waiting for \(name) to close normally.",
                symbol: "testtube.2",
                color: .accentColor
            )
        case let .waitingForRelaunch(name):
            Presentation(
                title: "First close complete",
                text: "Reopen \(name). Homeward will detect and close it automatically.",
                symbol: "testtube.2",
                color: .accentColor
            )
        case let .waitingForSecondExit(name):
            Presentation(
                title: "Relaunch detected",
                text: "Homeward detected the relaunch and is waiting for \(name) to close.",
                symbol: "testtube.2",
                color: .accentColor
            )
        case let .needsAttention(name, _, reason):
            Presentation(
                title: "App needs attention",
                text: attentionMessage(name: name, reason: reason),
                symbol: "exclamationmark.triangle",
                color: .orange
            )
        case let .complete(name):
            Presentation(
                title: "Preview complete",
                text: "Preview complete. Homeward closed both \(name) launches normally.",
                symbol: "checkmark.circle",
                color: .green
            )
        }
    }

    private func endPreviewAndDismiss() {
        model.endPreview()
        dismiss()
    }

    private func requestEndPreview() {
        guard previewHasLifecycleConsequences else {
            endPreviewAndDismiss()
            return
        }
        showEndConfirmation = true
    }

    private var previewHasLifecycleConsequences: Bool {
        switch model.previewState {
        case .idle, .needsAttention(_, _, .applicationNotRunning):
            return false
        case .waitingForFirstExit, .waitingForRelaunch,
             .waitingForSecondExit, .needsAttention, .complete:
            return true
        }
    }

    private func attentionMessage(
        name: String,
        reason: AppModel.PreviewAttentionReason
    ) -> String {
        switch reason {
        case .applicationNotRunning:
            "Open \(name), then run the preview again."
        case .normalQuitRejected:
            "\(name) declined the normal quit request. Check the app, then try again or skip preview."
        case .timedOut:
            "Preview timed out. Check \(name), try again, or skip preview."
        case .applicationExited:
            "\(name) is no longer running. Open it, then try again or skip preview."
        }
    }
}
