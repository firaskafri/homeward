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

    var body: some View {
        VStack(alignment: .leading, spacing: HomewardSpacing.panelInset) {
            VStack(alignment: .leading, spacing: HomewardSpacing.small) {
                Label("Preview the handoff", systemImage: "play.circle")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
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
                        endPreviewAndDismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    if case .needsAttention = model.previewState {
                        Button("Show App") {
                            model.showPreviewApplication()
                        }
                    }
                    Spacer()
                    runPreviewButton
                }
                VStack(alignment: .leading, spacing: 10) {
                    runPreviewButton
                    if case .needsAttention = model.previewState {
                        Button("Show App") {
                            model.showPreviewApplication()
                        }
                    }
                    Button("End Preview") {
                        endPreviewAndDismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(HomewardSpacing.xLarge)
        .frame(minWidth: 460, minHeight: 320)
        .onDisappear {
            model.endPreview()
        }
        .accessibilityIdentifier("preview.view")
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
        case let .needsAttention(name):
            Presentation(
                title: "App needs attention",
                text: "\(name) needs your attention before the preview can continue.",
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
}
