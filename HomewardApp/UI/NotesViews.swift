import AppKit
import HomewardCore
import SwiftUI

@MainActor
final class NotesPanelController: NSWindowController {
    init(model: AppModel) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let view = NotesReviewView(
            model: model,
            onClose: { [weak panel] in panel?.close() }
        )
        panel.title = "Saved Thoughts"
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

@MainActor
final class NoteCapturePanelController: NSWindowController {
    init(model: AppModel) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 280),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        let view = NoteCaptureView(
            model: model,
            onClose: { [weak panel] in panel?.close() }
        )
        panel.title = "Save a Thought"
        panel.contentViewController = NSHostingController(rootView: view)
        panel.isReleasedWhenClosed = false
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
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isSaving = false
    @FocusState private var editorFocused: Bool
    var onClose: (() -> Void)?

    init(model: AppModel, onClose: (() -> Void)? = nil) {
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
                    onClose?()
                    dismiss()
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
                onClose?()
                dismiss()
            } else {
                isSaving = false
                editorFocused = true
            }
        }
    }
}

struct NotesReviewView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var pendingDelete: TomorrowNote?
    @State private var recentlyCompleted: TomorrowNote?
    @State private var undoTask: Task<Void, Never>?
    var onClose: (() -> Void)?

    init(model: AppModel, onClose: (() -> Void)? = nil) {
        self.model = model
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Saved thoughts")
                .font(.title2.bold())

            if visibleNotes.isEmpty {
                ContentUnavailableView(
                    "No saved thoughts",
                    systemImage: "note.text"
                )
            } else {
                List(visibleNotes) { note in
                    noteRow(note)
                }
            }

            if let recentlyCompleted {
                HStack {
                    Text("Thought marked done")
                    Button("Undo") {
                        undoTask?.cancel()
                        Task { await model.restoreNote(recentlyCompleted) }
                        self.recentlyCompleted = nil
                    }
                    .keyboardShortcut("z", modifiers: .command)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("notes.undo")
            }

            HStack {
                Spacer()
                Button("Done") {
                    onClose?()
                    dismiss()
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
                            intervalID: currentIntervalID
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

    private var currentIntervalID: String {
        model.resolvedSchedule.activeBaseInterval?.id ?? "available"
    }

    private var visibleNotes: [TomorrowNote] {
        model.notes.notes.filter {
            $0.lastPresentedIntervalID != currentIntervalID
        }
    }

    private func complete(_ note: TomorrowNote) {
        undoTask?.cancel()
        recentlyCompleted = note
        Task { await model.removeNote(id: note.id) }
        undoTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else {
                return
            }
            recentlyCompleted = nil
        }
    }
}
