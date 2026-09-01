import AppKit
import HomewardCore
import SwiftUI

struct OverviewView: View {
    @ObservedObject var model: AppModel
    @State private var showEndWorkConfirmation = false
    @State private var showNoteCapture = false
    @State private var showNotesReview = false
    @State private var showCustomCutoff = false
    @State private var showTakeDayOffConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                stateHeader
                healthSection
                actionSection
                detailsSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Overview")
        .confirmationDialog(
            "End work now?",
            isPresented: $showEndWorkConfirmation
        ) {
            Button("End Work Now", role: .destructive) {
                Task { await model.endWorkNow() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Homeward will begin the configured closing flow for selected work apps.")
        }
        .sheet(isPresented: $showNoteCapture) {
            NoteCaptureView(model: model)
        }
        .sheet(isPresented: $showNotesReview) {
            NotesReviewView(model: model)
        }
        .sheet(isPresented: $showCustomCutoff) {
            CustomCutoffView(model: model)
        }
        .confirmationDialog(
            "Take today off?",
            isPresented: $showTakeDayOffConfirmation
        ) {
            Button("Take Today Off", role: .destructive) {
                Task { await model.takeTodayOff() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Homeward will apply the configured closing behavior now and keep work apps unavailable through today.")
        }
        .accessibilityIdentifier("overview.view")
    }

    private var stateHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(stateTitle, systemImage: stateSymbol)
                .font(.largeTitle.bold())
            Text(transitionText)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("overview.state")
    }

    @ViewBuilder
    private var healthSection: some View {
        switch model.health {
        case .starting:
            ProgressView("Starting Homeward…")
        case .ready:
            EmptyView()
        case let .configurationUnavailable(message):
            warning(message)
        case let .monitoringUnavailable(message):
            warning(message)
        }

        if model.loginItemStatus != .enabled {
            warning("Start at Login is not enabled. Homeward works only while it is open.")
        }
        if model.notificationStatus != .authorized {
            warning("Wind-down notifications are off. App closing still works.")
        }
        if let lastError = model.lastError {
            HStack {
                warning(lastError)
                Spacer()
                Button("Dismiss") {
                    model.clearError()
                }
            }
        }
    }

    private var actionSection: some View {
        HStack {
            if model.resolvedSchedule.isAvailable {
                Button("End Work Now…") {
                    showEndWorkConfirmation = true
                }
                .accessibilityIdentifier("overview.endWork")
            } else {
                Button("Save a Thought…") {
                    showNoteCapture = true
                }
                .accessibilityIdentifier("overview.saveThought")
            }

            Menu("Change Today Only…") {
                Button("Extend by 10 Minutes") {
                    Task { await model.createExtension(minutes: 10) }
                }
                Button("Extend by 15 Minutes") {
                    Task { await model.createExtension(minutes: 15) }
                }
                Button("Extend by 30 Minutes") {
                    Task { await model.createExtension(minutes: 30) }
                }
                Button("Choose Another Cutoff…") {
                    showCustomCutoff = true
                }
                if !model.resolvedSchedule.isAvailable {
                    Button("Make Work Available Now") {
                        Task { await model.makeWorkAvailableNow() }
                    }
                }
                Button("Take Today Off…") {
                    showTakeDayOffConfirmation = true
                }
                Divider()
                Button("Return to Weekly Schedule") {
                    Task { await model.returnToWeeklySchedule() }
                }
            }
            .accessibilityIdentifier("overview.changeToday")

            if model.forceEscalationPaused {
                Button("Resume Firm Closing…") {
                    Task { await model.resumeFirmClosing() }
                }
            }

            if model.resolvedSchedule.isAvailable,
               model.resolvedSchedule.phase != .temporarilyExtended,
               !model.notes.notes.isEmpty {
                Button("Review Saved Thoughts (\(model.notes.notes.count))…") {
                    showNotesReview = true
                }
            }
        }
    }

    private var detailsSection: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
            GridRow {
                Text("Work apps")
                    .foregroundStyle(.secondary)
                Text("\(model.configuration.selectedApplications.count)")
            }
            GridRow {
                Text("Closing mode")
                    .foregroundStyle(.secondary)
                Text(model.configuration.closeMode == .gentle ? "Gentle Close" : "Firm Close")
            }
            GridRow {
                Text("Warnings")
                    .foregroundStyle(.secondary)
                Text(warningSummary)
            }
            if let activeOverride = model.resolvedSchedule.activeOverride {
                GridRow {
                    Text("Today only")
                        .foregroundStyle(.secondary)
                    Text(
                        "\(overrideName(activeOverride.kind)) until "
                            + activeOverride.expiresAt.formatted(
                                date: .abbreviated,
                                time: .shortened
                            )
                    )
                }
            }
            if !model.closingRows.isEmpty {
                GridRow {
                    Text("Needs attention")
                        .foregroundStyle(.secondary)
                    Text("\(model.closingRows.count)")
                }
            }
        }
    }

    private var stateTitle: String {
        switch model.resolvedSchedule.phase {
        case .workAvailable:
            "Work available"
        case .windingDown:
            "Winding down"
        case .workClosed:
            model.closingRows.isEmpty ? "Work is closed" : "Closing work apps"
        case .temporarilyExtended:
            "Work extended"
        }
    }

    private var stateSymbol: String {
        switch model.resolvedSchedule.phase {
        case .workAvailable:
            "checkmark.circle"
        case .windingDown:
            "clock"
        case .workClosed:
            model.closingRows.isEmpty ? "house" : "power"
        case .temporarilyExtended:
            "clock.badge.plus"
        }
    }

    private var transitionText: String {
        guard let transition = model.resolvedSchedule.nextTransition else {
            return model.resolvedSchedule.isAvailable
                ? "Work apps are always available"
                : "No work window scheduled"
        }
        let formatted = transition.date.formatted(date: .abbreviated, time: .shortened)
        switch transition.cause {
        case .workWindowStarts:
            return "Available \(formatted)"
        case .workWindowEnds:
            return "Until \(formatted)"
        case .overrideExpires:
            return "Weekly schedule resumes \(formatted)"
        }
    }

    private var warningSummary: String {
        var values: [String] = []
        if model.configuration.warningPreferences.fifteenMinuteWarningEnabled {
            values.append("15 min")
        }
        if model.configuration.warningPreferences.fiveMinuteWarningEnabled {
            values.append("5 min")
        }
        return values.isEmpty ? "Off" : values.joined(separator: ", ")
    }

    private func overrideName(_ kind: OverrideKind) -> String {
        switch kind {
        case .endWorkNow:
            "Work ended early"
        case .fixedExtension:
            "Extended"
        case .customCutoff:
            "Custom cutoff"
        case .makeAvailable:
            "Work available"
        case .takeDayOff:
            "Day off"
        case .forceEscalationPaused:
            "Force quit paused"
        }
    }

    private func warning(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.orange)
            .accessibilityElement(children: .combine)
    }
}

@MainActor
final class CustomCutoffPanelController: NSWindowController {
    init(model: AppModel) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 220),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Choose Another Cutoff"
        panel.contentViewController = NSHostingController(
            rootView: CustomCutoffView(
                model: model,
                onClose: { [weak panel] in panel?.close() }
            )
        )
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

struct CustomCutoffView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var cutoff = Date().addingTimeInterval(60 * 60)
    var onClose: (() -> Void)?

    init(model: AppModel, onClose: (() -> Void)? = nil) {
        self.model = model
        self.onClose = onClose
        let now = Date()
        let calendar = Calendar.autoupdatingCurrent
        let midnight = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: now)
        ) ?? now.addingTimeInterval(24 * 60 * 60)
        _cutoff = State(
            initialValue: min(now.addingTimeInterval(60 * 60), midnight)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose another cutoff")
                .font(.title2.bold())
            DatePicker(
                "Work apps available until",
                selection: $cutoff,
                in: Date()...maximumCutoff
            )
            Text(cutoff.formatted(date: .abbreviated, time: .shortened))
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") {
                    onClose?()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Apply Cutoff") {
                    Task {
                        await model.chooseCutoff(cutoff)
                        onClose?()
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
        .accessibilityIdentifier("today.customCutoff")
    }

    private var maximumCutoff: Date {
        let calendar = Calendar.autoupdatingCurrent
        return calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: Date())
        ) ?? Date().addingTimeInterval(24 * 60 * 60)
    }
}

@MainActor
final class TodayChangePanelController: NSWindowController {
    init(model: AppModel) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Change Today Only"
        panel.contentViewController = NSHostingController(
            rootView: TodayChangePanelView(
                model: model,
                onClose: { [weak panel] in panel?.close() }
            )
        )
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

private struct TodayChangePanelView: View {
    @ObservedObject var model: AppModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Change today only")
                .font(.title2.bold())
            Text("Your weekly schedule will not change.")
                .foregroundStyle(.secondary)

            Button("Extend by 10 Minutes") {
                apply { await model.createExtension(minutes: 10) }
            }
            Button("Extend by 15 Minutes") {
                apply { await model.createExtension(minutes: 15) }
            }
            Button("Extend by 30 Minutes") {
                apply { await model.createExtension(minutes: 30) }
            }
            Button("Choose Another Cutoff…") {
                onClose()
                model.showCustomCutoff()
            }
            if !model.resolvedSchedule.isAvailable {
                Button("Make Work Available Now") {
                    apply { await model.makeWorkAvailableNow() }
                }
            }
            Button("Take Today Off…") {
                apply { await model.takeTodayOff() }
            }
            Button("Return to Weekly Schedule") {
                apply { await model.returnToWeeklySchedule() }
            }

            HStack {
                Spacer()
                Button("Cancel", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 400, minHeight: 300)
        .accessibilityIdentifier("today.changePanel")
    }

    private func apply(_ action: @escaping @MainActor () async -> Void) {
        onClose()
        Task { await action() }
    }
}
