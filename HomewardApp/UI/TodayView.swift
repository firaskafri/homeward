import AppKit
import HomewardCore
import SwiftUI

struct TodayView: View {
    private enum ActiveSheet: String, Identifiable {
        case noteCapture
        case notesReview
        case customCutoff

        var id: String { rawValue }
    }

    @ObservedObject var model: AppModel
    @State private var activeSheet: ActiveSheet?
    @State private var showTakeDayOffConfirmation = false
    @State private var detailsAreExpanded = false
    @FocusState private var primaryActionFocused: Bool
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HomewardSpacing.xLarge) {
                stateHero
                if let explanation = model.todayExplanation {
                    HomewardCard {
                        HStack(alignment: .top) {
                            Text(explanation)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button("Dismiss") {
                                model.clearTodayExplanation()
                            }
                        }
                    }
                    .accessibilityIdentifier("today.explanation")
                }
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
        .navigationTitle("Today")
        .confirmationDialog(
            model.pendingPolicyConfirmation?.title ?? "",
            isPresented: Binding(
                get: { model.pendingPolicyConfirmation != nil },
                set: { if !$0 { model.cancelPolicyConfirmation() } }
            )
        ) {
            if let intent = model.pendingPolicyConfirmation {
                Button(
                    intent.actionTitle
                ) {
                    Task { await model.confirmPolicyAction() }
                }
            }
            Button("Cancel", role: .cancel) {
                model.cancelPolicyConfirmation()
            }
        } message: {
            if let intent = model.pendingPolicyConfirmation {
                Text(intent.message(closeMode: model.configuration.closeMode))
            }
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
            TodayActionPresentation.takeDayOffConfirmationTitle,
            isPresented: $showTakeDayOffConfirmation
        ) {
            Button(
                TodayActionPresentation.takeDayOffConfirmationActionTitle,
                role: .destructive
            ) {
                Task { await model.takeTodayOff() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(TodayActionPresentation.takeDayOffConfirmationMessage)
        }
        .accessibilityIdentifier("today.view")
        .onChange(of: model.isSessionActive) { _, isActive in
            if !isActive {
                activeSheet = nil
            }
        }
        .onAppear {
            primaryActionFocused = true
        }
    }

    private var stateHero: some View {
        HomewardCard(padding: HomewardSpacing.xLarge) {
            VStack(alignment: .leading, spacing: HomewardSpacing.large) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: HomewardSpacing.large) {
                        stateIdentity
                        Spacer(minLength: HomewardSpacing.medium)
                        stateBadge
                    }
                    VStack(alignment: .leading, spacing: HomewardSpacing.medium) {
                        stateIdentity
                        stateBadge
                    }
                }

                Divider()

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: HomewardSpacing.xLarge) {
                        applicationSummary
                        Spacer(minLength: HomewardSpacing.large)
                        transitionSummary
                    }
                    VStack(
                        alignment: .leading,
                        spacing: HomewardSpacing.medium
                    ) {
                        applicationSummary
                        transitionSummary
                    }
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

    private var stateIdentity: some View {
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
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today.state")
    }

    private var stateBadge: some View {
        HomewardStatusLabel(
            title: stateBadgeTitle,
            symbol: stateSymbol,
            tone: stateTone
        )
    }

    private var applicationSummary: some View {
        HomewardApplicationSummary(
            applications: model.configuration.selectedApplications,
            iconsBySelectionKey: applicationIcons
        )
    }

    private var transitionSummary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("NEXT TRANSITION")
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Text(transitionText)
                .font(.callout.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
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
            if model.presentationSnapshot.attentionCount > 0 {
                Button(
                    "Homeward Needs Attention (\(model.presentationSnapshot.attentionCount))…"
                ) {
                    openPrimaryAttention()
                }
                .accessibilityHint(
                    "Opens the highest-priority issue that needs action"
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
                model.requestPolicyConfirmation(.resumeFirmClosing)
            }
        }

        if model.resolvedSchedule.isAvailable,
           model.canRevealNoteContent,
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
                model.requestPolicyConfirmation(.endWorkNow)
            }
            .buttonStyle(.borderedProminent)
            .tint(stateTone.color)
            .controlSize(.large)
            .focused($primaryActionFocused)
            .accessibilityIdentifier("today.endWork")
        } else {
            Button("Save a Thought…") {
                activeSheet = .noteCapture
            }
            .buttonStyle(.borderedProminent)
            .tint(stateTone.color)
            .controlSize(.large)
            .focused($primaryActionFocused)
            .accessibilityIdentifier("today.saveThought")
        }
    }

    private var changeTodayMenu: some View {
        Menu(TodayActionPresentation.menuTitle) {
            ForEach(model.todayActions, id: \.self) { action in
                if action == .returnToWeeklySchedule {
                    Divider()
                }
                Button(action.title) {
                    performTodayAction(action)
                }
            }
        }
        .controlSize(.large)
        .accessibilityIdentifier("today.changeToday")
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
        .accessibilityIdentifier("today.details")
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
        if model.forceEscalationPaused {
            return model.presentationSnapshot.transitionText ?? ""
        }
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
        model.presentationSnapshot.title
    }

    private var scheduleStatus: ScheduleStatusPresentation {
        if model.forceEscalationPaused {
            return ScheduleStatusPresentation(
                title: model.presentationSnapshot.title,
                badgeTitle: "Paused",
                symbol: "pause.circle",
                tone: .rest
            )
        }
        return SchedulePresentation.status(
            schedule: model.resolvedSchedule,
            closingCount: model.closingRows.count
        )
    }

    private var stateSymbol: String {
        scheduleStatus.symbol
    }

    private var transitionText: String {
        model.presentationSnapshot.transitionText
            ?? "No transition is available"
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

    private var applicationIcons: [String: NSImage] {
        model.catalog.reduce(into: [:]) { result, application in
            result[application.selection.stableSelectionKey] =
                application.icon
        }
    }

    private func openPrimaryAttention() {
        switch model.primaryAttentionDestination {
        case .workApps:
            model.requestRoute(.workApps)
        case .savedThoughts:
            model.requestRoute(.savedThoughts)
        case .settings, .none:
            openSettings()
        }
    }

    private func performTodayAction(
        _ action: TodayActionPresentation.Action
    ) {
        switch action {
        case let .extend(minutes):
            Task { await model.createExtension(minutes: minutes) }
        case .chooseCutoff:
            activeSheet = .customCutoff
        case .makeAvailable:
            Task { await model.makeWorkAvailableNow() }
        case .takeDayOff:
            showTakeDayOffConfirmation = true
        case .returnToWeeklySchedule:
            Task { await model.returnToWeeklySchedule() }
        }
    }
}
