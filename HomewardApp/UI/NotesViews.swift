import AppKit
import HomewardCore
import SwiftUI

@MainActor
final class NotesPanelController: NSWindowController {
    init(model: AppModel) {
        let panel = HomewardPanelFactory.make(
            title: "Saved Thoughts",
            size: NSSize(width: 620, height: 500),
            minimumSize: NSSize(width: 520, height: 360),
            resizable: true,
            floatsAcrossSpaces: true
        )
        let view = NotesReviewView(
            model: model,
            onClose: { [weak panel] in panel?.close() }
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

@MainActor
final class NoteCapturePanelController: NSWindowController {
    init(model: AppModel) {
        let panel = HomewardPanelFactory.make(
            title: "Save a Thought",
            size: NSSize(width: 520, height: 380),
            minimumSize: NSSize(width: 440, height: 320),
            resizable: true
        )
        let view = NoteCaptureView(
            model: model,
            onClose: { [weak panel] in panel?.close() }
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
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

}

struct NoteCaptureView: View {
    @ObservedObject var model: AppModel
    @State private var text = ""
    @State private var isSaving = false
    @FocusState private var editorFocused: Bool
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HomewardPanelHeader(
                title: "Save a thought for later",
                message: "Homeward will keep this thought out of sight until work is available again.",
                systemImage: "note.text.badge.plus",
                tone: .rest
            )

            VStack(alignment: .leading, spacing: HomewardSpacing.small) {
                Text("Thought")
                    .font(.headline)

                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("What do you want to remember?")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 11)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }

                    TextEditor(text: $text)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(5)
                        .focused($editorFocused)
                        .accessibilityLabel("Thought")
                        .accessibilityHint(
                            "Enter up to \(TomorrowNote.maximumCharacterCount) characters"
                        )
                        .accessibilityIdentifier("notes.editor")
                }
                .frame(minHeight: 140)
                .background(
                    Color(nsColor: .textBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            remainingCharacters < 0
                                ? Color.red
                                : Color(nsColor: .separatorColor)
                        )
                }
            }

            if let error = model.lastError {
                InlineErrorView(message: error) {
                    model.clearError()
                }
                .accessibilityIdentifier("notes.error")
            }

            HStack {
                Text("\(remainingCharacters) characters remaining")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(remainingCharacters < 0 ? .red : .secondary)
                    .accessibilityLabel(
                        remainingCharacters >= 0
                            ? "\(remainingCharacters) characters remaining"
                            : "\(-remainingCharacters) characters over the limit"
                    )

                Spacer()

                Button("Cancel") {
                    onClose()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    save()
                } label: {
                    if isSaving {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Saving…")
                        }
                    } else {
                        Text("Save")
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canSave || isSaving)
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Saves this thought for your next available work period")
                .accessibilityIdentifier("notes.save")
            }
        }
        .padding(HomewardSpacing.xLarge)
        .frame(minWidth: 420, minHeight: 300)
        .onAppear {
            Task { @MainActor in
                editorFocused = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("notes.capture")
    }

    private var remainingCharacters: Int {
        TomorrowNote.maximumCharacterCount - text.count
    }

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && remainingCharacters >= 0
    }

    private func save() {
        isSaving = true
        Task { @MainActor in
            if await model.saveNote(text) {
                onClose()
            } else {
                isSaving = false
                editorFocused = true
            }
        }
    }
}

struct NotesReviewView: View {
    @ObservedObject var model: AppModel
    @State private var pendingDelete: TomorrowNote?
    @State private var recentlyCompleted: TomorrowNote?
    @State private var undoTask: Task<Void, Never>?
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HomewardPanelHeader(
                title: "Saved thoughts",
                message: reviewSummary,
                systemImage: "note.text",
                tone: .rest
            )

            if let error = model.lastError {
                InlineErrorView(message: error) {
                    model.clearError()
                }
            }

            if model.visibleNotes.isEmpty {
                ContentUnavailableView(
                    "No saved thoughts",
                    systemImage: "note.text",
                    description: Text(
                        "New thoughts saved while work is closed will appear here."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.visibleNotes) { note in
                    noteRow(note)
                }
                .listStyle(.inset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let recentlyCompleted {
                HomewardCard(padding: HomewardSpacing.small) {
                    HStack(spacing: HomewardSpacing.small) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(HomewardTone.ready.color)
                            .accessibilityHidden(true)
                        Text("Thought marked done.")
                            .font(.callout)
                        Button("Undo") {
                            undoTask?.cancel()
                            Task {
                                if await model.restoreNote(recentlyCompleted) {
                                    self.recentlyCompleted = nil
                                }
                            }
                        }
                        .keyboardShortcut("z", modifiers: .command)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("notes.undo")
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") {
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(HomewardSpacing.xLarge)
        .frame(minWidth: 500, minHeight: 340)
        .onDisappear {
            undoTask?.cancel()
            recentlyCompleted = nil
        }
        .confirmationDialog(
            "Delete this thought?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                guard let pendingDelete else {
                    return
                }
                Task { await model.removeNote(id: pendingDelete.id) }
                self.pendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        }
        .accessibilityIdentifier("notes.review")
    }

    private var reviewSummary: String {
        let count = model.visibleNotes.count
        return count == 1
            ? "1 thought is ready to review. Keep it for later, mark it done, or delete it."
            : "\(count) thoughts are ready to review. Keep them for later, mark them done, or delete them."
    }

    @ViewBuilder
    private func noteRow(_ note: TomorrowNote) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                note.createdAt.formatted(date: .abbreviated, time: .shortened),
                systemImage: "clock"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(note.text)
                .font(.body)
                .textSelection(.enabled)

            HStack {
                Button("Keep for Later") {
                    Task {
                        await model.keepNote(
                            id: note.id,
                            intervalID: model.currentNoteIntervalID
                        )
                    }
                }
                Button("Mark Done") {
                    complete(note)
                }
                Button("Delete…", role: .destructive) {
                    pendingDelete = note
                }
            }
            .controlSize(.small)
        }
        .padding(.vertical, HomewardSpacing.small)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Thought from \(note.createdAt.formatted(date: .abbreviated, time: .shortened))"
        )
        .accessibilityIdentifier("notes.row.\(note.id.uuidString)")
    }

    private func complete(_ note: TomorrowNote) {
        undoTask?.cancel()
        Task { @MainActor in
            guard let completed = await model.completeNote(id: note.id) else {
                return
            }
            recentlyCompleted = completed
            undoTask = Task { @MainActor in
                try? await Task.sleep(
                    for: .seconds(HomewardPolicy.noteUndoDuration)
                )
                guard !Task.isCancelled else {
                    return
                }
                recentlyCompleted = nil
            }
        }
    }
}
