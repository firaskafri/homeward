import AppKit
import HomewardCore
import SwiftUI

@MainActor
final class NotesReadyPanelController: NSWindowController {
    init(model: AppModel, count: Int) {
        let panel = HomewardPanelFactory.make(
            title: "Saved Thoughts",
            size: NSSize(width: 480, height: 250),
            minimumSize: NSSize(width: 420, height: 230),
            resizable: true
        )
        panel.contentViewController = NSHostingController(
            rootView: NotesReadyView(
                model: model,
                count: count,
                onClose: { [weak panel] in panel?.close() }
            )
        )
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

private struct NotesReadyView: View {
    @ObservedObject var model: AppModel
    let count: Int
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HomewardSpacing.large) {
            HomewardPanelHeader(
                title: "Saved thoughts are ready",
                message: count == 1
                    ? "You have 1 saved thought. Open Saved Thoughts to review it."
                    : "You have \(count) saved thoughts. Open Saved Thoughts to review them.",
                systemImage: "note.text",
                tone: .rest
            )
            Spacer(minLength: 0)
            ViewThatFits(in: .horizontal) {
                HStack {
                    reviewButton
                    Spacer()
                    laterButton
                }
                VStack(alignment: .leading, spacing: HomewardSpacing.small) {
                    reviewButton
                    laterButton
                }
            }
        }
        .padding(HomewardSpacing.xLarge)
        .accessibilityIdentifier("notes.ready")
    }

    private var reviewButton: some View {
        Button("Review Saved Thoughts…") {
            onClose()
            model.showNotesReview()
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("notes.ready.review")
    }

    private var laterButton: some View {
        Button("Later", action: onClose)
            .keyboardShortcut(.cancelAction)
    }
}

@MainActor
final class NotesPanelController: HomewardInvokedPanelController {
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
        panel.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        showInvoked()
    }
}

@MainActor
final class NoteCapturePanelController: HomewardInvokedPanelController {
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
        panel.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        showInvoked()
    }

}

struct NoteCaptureView: View {
    @ObservedObject var model: AppModel
    @State private var text = ""
    @State private var isSaving = false
    @State private var didSave = false
    @FocusState private var editorFocused: Bool
    @FocusState private var doneFocused: Bool
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
                    if text.isEmpty, !didSave {
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
                        .disabled(didSave)
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
                if !didSave,
                   text.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty {
                    Text("Enter a thought to save.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("notes.saveDisabledReason")
                }
            }

            if let error = model.lastError {
                InlineErrorView(message: error) {
                    model.clearError()
                }
                .accessibilityIdentifier("notes.error")
            }

            if didSave {
                Label(
                    "Thought saved. It will stay private until you review it.",
                    systemImage: "checkmark.circle"
                )
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("notes.saved")
            }

            HStack {
                if !didSave {
                    Text("\(remainingCharacters) characters remaining")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(
                            remainingCharacters < 0 ? .red : .secondary
                        )
                        .accessibilityLabel(
                            remainingCharacters >= 0
                                ? "\(remainingCharacters) characters remaining"
                                : "\(-remainingCharacters) characters over the limit"
                        )
                }

                Spacer()

                Button(didSave ? "Done" : "Cancel") {
                    onClose()
                }
                .keyboardShortcut(
                    didSave ? .defaultAction : .cancelAction
                )
                .focused($doneFocused)

                if !didSave {
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
                    .accessibilityHint(
                        canSave
                            ? "Saves this thought for your next available work period"
                            : "Enter a thought to save."
                    )
                    .accessibilityIdentifier("notes.save")
                }
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
                text = ""
                didSave = true
                isSaving = false
                doneFocused = true
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
    @State private var recentlyCompleted: [TomorrowNote] = []
    @State private var recentlyKept: [TomorrowNote] = []
    @State private var confirmReset = false
    @FocusState private var focusedNoteID: UUID?
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

            if model.notesHealth == .loading {
                ProgressView("Loading saved thoughts…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.notesHealth == .unavailable {
                ContentUnavailableView {
                    Label(
                        "Saved thoughts are unavailable",
                        systemImage: "exclamationmark.triangle"
                    )
                } description: {
                    Text("App closing still works.")
                } actions: {
                    Button("Retry") {
                        Task { await model.retryNotesLoad() }
                    }
                    if model.notesRecoveryCandidateAvailable {
                        Button("Restore Previous Thoughts…") {
                            Task { await model.restorePreviousNotes() }
                        }
                    }
                    Button("Reset Saved Thoughts…", role: .destructive) {
                        confirmReset = true
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !model.canRevealNoteContent {
                ContentUnavailableView(
                    "Saved thoughts are hidden",
                    systemImage: "lock",
                    description: Text(
                        "Thought text is available only during a normal work window while your session is active."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.visibleNotes.isEmpty {
                ContentUnavailableView(
                    model.notes.notes.isEmpty
                        ? "No saved thoughts"
                        : "No thoughts to review in this work window",
                    systemImage: "note.text",
                    description: Text(
                        model.notes.notes.isEmpty
                            ? "New thoughts saved while work is closed will appear here."
                            : "Kept thoughts will return in a later work window."
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

            if !recentlyCompleted.isEmpty || !recentlyKept.isEmpty {
                HomewardCard(padding: HomewardSpacing.small) {
                    VStack(alignment: .leading, spacing: HomewardSpacing.small) {
                        ForEach(recentlyCompleted) { note in
                            HStack(spacing: HomewardSpacing.small) {
                                Text("Thought marked done")
                                    .font(.callout)
                                Button("Restore") {
                                    Task {
                                        if await model.restoreNote(note) {
                                            recentlyCompleted.removeAll {
                                                $0.id == note.id
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        ForEach(recentlyKept) { note in
                            HStack(spacing: HomewardSpacing.small) {
                                Text("This thought will return in a later work window.")
                                    .font(.callout)
                                Button("Undo Keep") {
                                    Task {
                                        if await model.undoKeepNote(note) {
                                            recentlyKept.removeAll {
                                                $0.id == note.id
                                            }
                                        }
                                    }
                                }
                            }
                        }
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
            recentlyCompleted.removeAll()
            recentlyKept.removeAll()
        }
        .onAppear {
            focusedNoteID = model.visibleNotes.first?.id
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
        } message: {
            Text("This permanently deletes the selected thought. This cannot be undone.")
        }
        .confirmationDialog(
            "Delete all saved thoughts?",
            isPresented: $confirmReset
        ) {
            Button("Delete Saved Thoughts", role: .destructive) {
                Task { await model.resetSavedThoughts() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes every saved thought. This cannot be undone.")
        }
        .accessibilityIdentifier("notes.review")
    }

    private var reviewSummary: String {
        guard model.canRevealNoteContent else {
            return "Thought text is concealed until a normal work window is available and your session is active."
        }
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
                        if await model.keepNote(
                            id: note.id,
                            intervalID: model.currentNoteIntervalID
                        ) {
                            recentlyKept.append(note)
                        }
                    }
                }
                .focused($focusedNoteID, equals: note.id)
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
        .accessibilityIdentifier("notes.row.\(note.id.uuidString)")
    }

    private func complete(_ note: TomorrowNote) {
        Task { @MainActor in
            guard let completed = await model.completeNote(id: note.id) else {
                return
            }
            recentlyCompleted.append(completed)
        }
    }
}
