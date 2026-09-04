import AppKit
import HomewardCore
import SwiftUI

struct OverviewView: View {
    private enum ActiveSheet: String, Identifiable {
        case noteCapture
        case notesReview
        case customCutoff

        var id: String { rawValue }
    }

    @ObservedObject var model: AppModel
    @State private var showEndWorkConfirmation = false
    @State private var activeSheet: ActiveSheet?
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
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .noteCapture:
                NoteCaptureView(model: model) {
                    activeSheet = nil
                }
            case .notesReview:
                NotesReviewView(model: model) {
                    activeSheet = nil
                }
            case .customCutoff:
                CustomCutoffView(model: model) {
                    activeSheet = nil
                }
            }
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
                    activeSheet = .noteCapture
                }
                .accessibilityIdentifier("overview.saveThought")
            }

            Menu("Change Today Only…") {
                if model.canExtendToday {
                    ForEach(
                        HomewardPolicy.extensionDurationsMinutes,
                        id: \.self
                    ) { minutes in
                        Button("Extend by \(minutes) Minutes") {
                            Task { await model.createExtension(minutes: minutes) }
                        }
                    }
                }
                Button("Choose Another Cutoff…") {
                    activeSheet = .customCutoff
                }
                if !model.resolvedSchedule.isAvailable {
                    Button("Make Work Available Now") {
                        Task { await model.makeWorkAvailableNow() }
                    }
                }
                Button("Take Today Off…") {
                    showTakeDayOffConfirmation = true
                }
                if model.hasAvailabilityOverride {
                    Divider()
                    Button("Return to Weekly Schedule") {
                        Task { await model.returnToWeeklySchedule() }
                    }
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
               !model.visibleNotes.isEmpty {
                Button("Review Saved Thoughts (\(model.visibleNotes.count))…") {
                    activeSheet = .notesReview
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
                Text(
                    SchedulePresentation.closeModeName(
                        model.configuration.closeMode
                    )
                )
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
                        "\(SchedulePresentation.overrideName(activeOverride.kind)) until "
                            + activeOverride.expiresAt.formatted(
                                date: .abbreviated,
                                time: .shortened
                            )
                    )
                }
            }
            if !model.closingRows.isEmpty {
                GridRow {
                    Text("Closing apps")
                        .foregroundStyle(.secondary)
                    Text("\(model.closingRows.count)")
                }
            }
        }
    }

    private var stateTitle: String {
        SchedulePresentation.stateTitle(
            schedule: model.resolvedSchedule,
            closingCount: model.closingRows.count
        )
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
        SchedulePresentation.transitionText(for: model.resolvedSchedule)
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

    private func warning(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.orange)
            .accessibilityElement(children: .combine)
    }
}

@MainActor
final class CustomCutoffPanelController: NSWindowController {
    init(model: AppModel) {
        let panel = HomewardPanelFactory.make(
            title: "Choose Another Cutoff",
            size: NSSize(width: 440, height: 220)
        )
        panel.contentViewController = NSHostingController(
            rootView: CustomCutoffView(
                model: model,
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
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct CustomCutoffView: View {
    @ObservedObject var model: AppModel
    @State private var cutoff = Date().addingTimeInterval(60 * 60)
    let onClose: () -> Void

    init(model: AppModel, onClose: @escaping () -> Void) {
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
                    onClose()
                }
                .keyboardShortcut(.cancelAction)
                Button("Apply Cutoff") {
                    Task {
                        model.clearError()
                        await model.chooseCutoff(cutoff)
                        if model.lastError == nil {
                            onClose()
                        }
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
        let panel = HomewardPanelFactory.make(
            title: "Change Today Only",
            size: NSSize(width: 420, height: 320)
        )
        panel.contentViewController = NSHostingController(
            rootView: TodayChangePanelView(
                model: model,
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
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct TodayChangePanelView: View {
    @ObservedObject var model: AppModel
    let onClose: () -> Void
    @State private var confirmTakeDayOff = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Change today only")
                .font(.title2.bold())
            Text("Your weekly schedule will not change.")
                .foregroundStyle(.secondary)
            if let error = model.lastError {
                InlineErrorView(message: error) {
                    model.clearError()
                }
            }

            if model.canExtendToday {
                ForEach(
                    HomewardPolicy.extensionDurationsMinutes,
                    id: \.self
                ) { minutes in
                    Button("Extend by \(minutes) Minutes") {
                        apply { await model.createExtension(minutes: minutes) }
                    }
                }
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
                confirmTakeDayOff = true
            }
            if model.hasAvailabilityOverride {
                Button("Return to Weekly Schedule") {
                    apply { await model.returnToWeeklySchedule() }
                }
            }

            HStack {
                Spacer()
                Button("Cancel", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 400, minHeight: 300)
        .confirmationDialog(
            "Take today off?",
            isPresented: $confirmTakeDayOff
        ) {
            Button("Take Today Off", role: .destructive) {
                apply { await model.takeTodayOff() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Homeward will apply the configured closing flow and keep "
                    + "work apps unavailable through today."
            )
        }
        .accessibilityIdentifier("today.changePanel")
    }

    private func apply(_ action: @escaping @MainActor () async -> Void) {
        model.clearError()
        Task {
            await action()
            if model.lastError == nil {
                onClose()
            }
        }
    }
}
