import AppKit
import HomewardCore
import SwiftUI

@MainActor
final class NotesPanelController: NSWindowController {
    init(model: AppModel) {
        let panel = HomewardPanelFactory.make(
            title: "Saved Thoughts",
            size: NSSize(width: 560, height: 420),
            resizable: true,
            floatsAutomatically: true
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
            size: NSSize(width: 440, height: 280)
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

    init(model: AppModel, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Save a thought for later")
                .font(.title2.bold())
            Text("Existing thoughts stay hidden while work is closed.")
                .foregroundStyle(.secondary)

            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 120)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.separator)
                }
                .focused($editorFocused)
                .accessibilityLabel("What do you want to remember?")
                .accessibilityIdentifier("notes.editor")

            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("notes.error")
            }

            HStack {
                Text("\(remainingCharacters) characters remaining")
                    .font(.caption)
                    .foregroundStyle(remainingCharacters < 0 ? .red : .secondary)
                Spacer()
                Button("Cancel") {
                    onClose()
                }
                .keyboardShortcut(.cancelAction)
                Button("Save") {
                    save()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canSave || isSaving)
                .accessibilityIdentifier("notes.save")
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 260)
        .onAppear {
            editorFocused = true
        }
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

    init(model: AppModel, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Saved thoughts")
                .font(.title2.bold())

            if model.visibleNotes.isEmpty {
                ContentUnavailableView(
                    "No saved thoughts",
                    systemImage: "note.text"
                )
            } else {
                List(model.visibleNotes) { note in
                    noteRow(note)
                }
            }

            if let recentlyCompleted {
                HStack {
                    Text("Thought marked done")
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
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("notes.undo")
            }

            HStack {
                Spacer()
                Button("Done") {
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 380)
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

    @ViewBuilder
    private func noteRow(_ note: TomorrowNote) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(note.text)
                .textSelection(.enabled)
            HStack {
                Button("Keep") {
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
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
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
