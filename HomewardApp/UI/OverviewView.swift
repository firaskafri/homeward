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
    @State private var detailsAreExpanded = false
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HomewardSpacing.xLarge) {
                stateHero
                if let lastError = model.lastError {
                    InlineErrorView(message: lastError) {
                        model.clearError()
                    }
                }
                readinessSection
                actionSection
                detailsSection
            }
            .padding(HomewardSpacing.xLarge)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxWidth: HomewardMetrics.contentMaxWidth)
            .frame(maxWidth: .infinity)
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

    private var stateHero: some View {
        HomewardCard(padding: HomewardSpacing.xLarge) {
            VStack(alignment: .leading, spacing: HomewardSpacing.large) {
                HStack(alignment: .top, spacing: HomewardSpacing.large) {
                    ZStack {
                        Circle()
                            .fill(stateTone.color.opacity(0.14))
                        Image(systemName: stateSymbol)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(stateTone.color)
                    }
                    .frame(width: 52, height: 52)
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: HomewardSpacing.xSmall) {
                        Text("TODAY")
                            .font(.caption.weight(.semibold))
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                        Text(stateTitle)
                            .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(stateDescription)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("overview.state")

                    Spacer(minLength: HomewardSpacing.medium)

                    HomewardStatusLabel(
                        title: stateBadgeTitle,
                        symbol: stateSymbol,
                        tone: stateTone
                    )
                }

                Divider()

                HStack(alignment: .center, spacing: HomewardSpacing.xLarge) {
                    HomewardApplicationSummary(
                        applications: model.configuration.selectedApplications
                    )

                    Spacer(minLength: HomewardSpacing.large)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("NEXT TRANSITION")
                            .font(.caption2.weight(.semibold))
                            .tracking(0.6)
                            .foregroundStyle(.secondary)
                        Text(transitionText)
                            .font(.callout.weight(.medium))
                            .multilineTextAlignment(.trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .overlay {
            RoundedRectangle(
                cornerRadius: HomewardMetrics.cardCornerRadius,
                style: .continuous
            )
            .strokeBorder(
                stateTone.color.opacity(colorSchemeContrast == .increased ? 0.7 : 0.3),
                lineWidth: colorSchemeContrast == .increased ? 2 : 1
            )
        }
    }

    private var readinessSection: some View {
        VStack(alignment: .leading, spacing: HomewardSpacing.medium) {
            Text("Readiness")
                .font(.title3.weight(.semibold))

            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: 190, maximum: 280),
                        spacing: HomewardSpacing.medium
                    ),
                ],
                alignment: .leading,
                spacing: HomewardSpacing.medium
            ) {
                readinessCard(
                    title: "Start at Login",
                    leadingSymbol: "power",
                    presentation: loginReadiness
                )
                readinessCard(
                    title: "Notifications",
                    leadingSymbol: "bell",
                    presentation: notificationReadiness
                )
                readinessCard(
                    title: "Work Apps",
                    leadingSymbol: "square.grid.2x2",
                    presentation: applicationReadiness
                )
            }
        }
    }

    private func readinessCard(
        title: String,
        leadingSymbol: String,
        presentation: ReadinessPresentation
    ) -> some View {
        HomewardCard(padding: HomewardSpacing.medium) {
            VStack(alignment: .leading, spacing: HomewardSpacing.small) {
                HStack {
                    Image(systemName: leadingSymbol)
                        .foregroundStyle(presentation.tone.color)
                        .accessibilityHidden(true)
                    Spacer()
                    HomewardStatusLabel(
                        title: presentation.status,
                        symbol: presentation.symbol,
                        tone: presentation.tone
                    )
                }
                Text(title)
                    .font(.headline)
                Text(presentation.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: HomewardSpacing.medium) {
            Text("Actions")
                .font(.title3.weight(.semibold))

            ViewThatFits(in: .horizontal) {
                HStack(spacing: HomewardSpacing.small) {
                    actionControls
                }
                VStack(alignment: .leading, spacing: HomewardSpacing.small) {
                    actionControls
                }
            }
        }
    }

    @ViewBuilder
    private var actionControls: some View {
        primaryAction

        changeTodayMenu

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

    @ViewBuilder
    private var primaryAction: some View {
        if model.resolvedSchedule.isAvailable {
            Button("End Work Now…") {
                showEndWorkConfirmation = true
            }
            .buttonStyle(.borderedProminent)
            .tint(stateTone.color)
            .controlSize(.large)
            .accessibilityIdentifier("overview.endWork")
        } else {
            Button("Save a Thought…") {
                activeSheet = .noteCapture
            }
            .buttonStyle(.borderedProminent)
            .tint(stateTone.color)
            .controlSize(.large)
            .accessibilityIdentifier("overview.saveThought")
        }
    }

    private var changeTodayMenu: some View {
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
        .controlSize(.large)
        .accessibilityIdentifier("overview.changeToday")
    }

    private var detailsSection: some View {
        HomewardCard {
            DisclosureGroup(isExpanded: $detailsAreExpanded) {
                Grid(
                    alignment: .leading,
                    horizontalSpacing: HomewardSpacing.xLarge,
                    verticalSpacing: HomewardSpacing.medium
                ) {
                    detailRow(
                        title: "Work apps",
                        value: "\(model.configuration.selectedApplications.count)"
                    )
                    detailRow(
                        title: "Closing mode",
                        value: SchedulePresentation.closeModeName(
                            model.configuration.closeMode
                        )
                    )
                    detailRow(title: "Warnings", value: warningSummary)
                    if let activeOverride = model.resolvedSchedule.activeOverride {
                        detailRow(
                            title: "Today only",
                            value: "\(SchedulePresentation.overrideName(activeOverride.kind)) until "
                                + activeOverride.expiresAt.formatted(
                                    date: .abbreviated,
                                    time: .shortened
                                )
                        )
                    }
                    if !model.closingRows.isEmpty {
                        detailRow(
                            title: "Closing apps",
                            value: "\(model.closingRows.count)"
                        )
                    }
                }
                .padding(.top, HomewardSpacing.medium)
            } label: {
                Label("Schedule details", systemImage: "list.bullet.rectangle")
                    .font(.headline)
            }
        }
        .accessibilityIdentifier("overview.details")
    }

    private func detailRow(title: String, value: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .multilineTextAlignment(.trailing)
        }
    }

    private var stateDescription: String {
        if !model.closingRows.isEmpty {
            let count = model.closingRows.count
            return count == 1
                ? "One selected app is completing its closing flow."
                : "\(count) selected apps are completing their closing flow."
        }
        return switch model.resolvedSchedule.phase {
        case .workAvailable:
            "Selected apps are available during this work window."
        case .windingDown:
            "Your work window is ending soon."
        case .workClosed:
            "Selected apps are unavailable so you can step away."
        case .temporarilyExtended:
            "A today-only extension is currently active."
        }
    }

    private var stateBadgeTitle: String {
        scheduleStatus.badgeTitle
    }

    private var stateTone: HomewardTone {
        scheduleStatus.tone
    }

    private var loginReadiness: ReadinessPresentation {
        .login(model.loginItemStatus, readyTitle: "Ready")
    }

    private var notificationReadiness: ReadinessPresentation {
        .notifications(model.notificationStatus, readyTitle: "Ready")
    }

    private var applicationReadiness: ReadinessPresentation {
        let applications = model.configuration.selectedApplications
        let unresolvedCount = applications.count(where: { !$0.isResolvable })
        if applications.isEmpty {
            return ReadinessPresentation(
                status: "Needs setup",
                detail: "Choose at least one work app.",
                symbol: "exclamationmark.circle.fill",
                tone: .attention
            )
        }
        if unresolvedCount > 0 {
            let detail = unresolvedCount == 1
                ? "One app needs to be selected again."
                : "\(unresolvedCount) apps need to be selected again."
            return ReadinessPresentation(
                status: "Needs attention",
                detail: detail,
                symbol: "exclamationmark.circle.fill",
                tone: .attention
            )
        }
        return ReadinessPresentation(
            status: "Ready",
            detail: applications.count == 1
                ? "One work app is selected."
                : "\(applications.count) work apps are selected.",
            symbol: "checkmark.circle.fill",
            tone: .ready
        )
    }

    private var stateTitle: String {
        scheduleStatus.title
    }

    private var scheduleStatus: ScheduleStatusPresentation {
        SchedulePresentation.status(
            schedule: model.resolvedSchedule,
            closingCount: model.closingRows.count
        )
    }

    private var stateSymbol: String {
        scheduleStatus.symbol
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
    @State private var cutoff: Date
    private let earliestCutoff: Date
    private let latestCutoff: Date
    let onClose: () -> Void

    init(model: AppModel, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
        let now = Date()
        let calendar = Calendar.autoupdatingCurrent
        let midnight = ScheduleResolver().nextLocalDayBoundary(
            after: now,
            calendar: calendar
        )
        earliestCutoff = now
        latestCutoff = midnight
        _cutoff = State(
            initialValue: min(
                now.addingTimeInterval(
                    HomewardPolicy.customCutoffDefaultLeadTime
                ),
                midnight
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HomewardSpacing.large) {
            Text("Choose another cutoff")
                .font(.title2.bold())
            DatePicker(
                "Work apps available until",
                selection: $cutoff,
                in: earliestCutoff...latestCutoff
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
