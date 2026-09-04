import HomewardCore
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: AppModel
    @AppStorage(HomewardPreferenceKeys.onboardingStep) private var step = 0
    @State private var showPreview = false

    private let stepTitles = [
        "Set your work window",
        "Choose your work apps",
        "Choose a closing style",
        "Keep Homeward ready",
        "Review and begin",
    ]

    private let stepSubtitles = [
        "Define the weekly threshold between work time and personal time.",
        "Only the apps you select will be managed by Homeward.",
        "Start gently, or opt into stronger enforcement with clear safeguards.",
        "Choose which background conveniences you want to enable.",
        "Confirm the essentials, then preview or start Homeward.",
    ]

    private let stepSymbols = [
        "calendar.badge.clock",
        "square.grid.2x2",
        "power",
        "checklist",
        "checkmark.seal",
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: stepSymbols[currentStep])
                        .font(.title2)
                        .foregroundStyle(HomewardTone.rest.color)
                        .frame(width: 38, height: 38)
                        .background(
                            HomewardTone.rest.color.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("STEP \(currentStep + 1) OF \(stepTitles.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(stepTitles[currentStep])
                            .font(.largeTitle.bold())
                            .accessibilityAddTraits(.isHeader)
                    }
                }

                Text(stepSubtitles[currentStep])
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ProgressView(
                    value: Double(currentStep + 1),
                    total: Double(stepTitles.count)
                )
                .accessibilityLabel("Setup progress")
                .accessibilityValue(
                    "Step \(currentStep + 1) of \(stepTitles.count)"
                )
            }
            .frame(maxWidth: 860, alignment: .leading)
            .padding(24)

            Divider()

            if let error = model.lastError {
                InlineErrorView(message: error) {
                    model.clearError()
                }
                .frame(maxWidth: 860)
                .padding(.horizontal, 24)
                .padding(.top, 12)
            }

            Group {
                switch currentStep {
                case 0:
                    ScheduleEditorView(
                        model: model,
                        requiresOnboardingConfirmation: true
                    )
                case 1:
                    AppPickerView(model: model)
                case 2:
                    ClosingSettingsView(model: model)
                case 3:
                    permissionStep
                default:
                    readyStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            ViewThatFits(in: .horizontal) {
                HStack {
                    footerStatus
                    Spacer()
                    onboardingActions
                }
                VStack(alignment: .leading, spacing: 12) {
                    footerStatus
                    onboardingActions
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .frame(maxWidth: 860)
            .padding(16)
        }
        .frame(minWidth: 680, minHeight: 560)
        .sheet(isPresented: $showPreview) {
            PreviewView(model: model)
        }
        .onAppear {
            if step != currentStep {
                step = currentStep
            }
        }
        .accessibilityIdentifier("onboarding.step.\(currentStep + 1)")
    }

    @ViewBuilder
    private var footerStatus: some View {
        switch currentStep {
        case 0 where !model.configuration.onboardingScheduleConfirmed:
            Label("Save and confirm the schedule to continue", systemImage: "circle.dashed")
                .font(.callout)
                .foregroundStyle(.secondary)
        case 1 where model.configuration.selectedApplications.isEmpty:
            Label("Choose at least one work app to continue", systemImage: "circle.dashed")
                .font(.callout)
                .foregroundStyle(.secondary)
        case _ where currentStep == stepTitles.count - 1:
            Label("Setup stays editable after you start", systemImage: "checkmark.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }

    private var onboardingActions: some View {
        HStack {
            Button("Back") {
                step = max(0, currentStep - 1)
            }
            .disabled(currentStep == 0)

            if currentStep == stepTitles.count - 1 {
                Button("Test Setup…") {
                    showPreview = true
                }
                Button(startButtonTitle) {
                    Task { await model.completeOnboarding() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    !model.configuration.onboardingScheduleConfirmed
                        || model.configuration.selectedApplications.isEmpty
                )
                .accessibilityIdentifier("onboarding.start")
            } else {
                Button("Continue") {
                    step = min(stepTitles.count - 1, currentStep + 1)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    (currentStep == 0
                        && !model.configuration.onboardingScheduleConfirmed)
                        || (currentStep == 1
                            && model.configuration.selectedApplications.isEmpty)
                )
            }
        }
    }

    private var currentStep: Int {
        min(max(step, 0), stepTitles.count - 1)
    }

    private var permissionStep: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("The essentials are already in place", systemImage: "checkmark.shield")
                        .font(.title2.bold())
                    Text(
                        "These conveniences improve reliability and awareness. "
                            + "Neither one grants Homeward access to your content."
                    )
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }

            Section("Recommended") {
                readinessRow(
                    title: "Start at Login",
                    detail: "Keeps your schedule active after you sign in.",
                    status: loginSummary,
                    symbol: model.loginItemStatus == .enabled
                        ? "checkmark.circle.fill"
                        : "exclamationmark.circle",
                    tone: model.loginItemStatus == .enabled ? .ready : .attention
                ) {
                    switch model.loginItemStatus {
                    case .enabled:
                        EmptyView()
                    case .notRegistered:
                        Button("Enable Start at Login") {
                            model.enableStartAtLogin()
                        }
                    case .requiresApproval, .notFound:
                        Button("Open Login Items") {
                            model.openLoginItemSettings()
                        }
                    }
                }
            }

            Section("Optional") {
                readinessRow(
                    title: "Notifications",
                    detail: "Shows wind-down and status messages. Closing works without them.",
                    status: notificationSummary,
                    symbol: model.notificationStatus == .authorized
                        ? "checkmark.circle.fill"
                        : "bell.slash",
                    tone: model.notificationStatus == .authorized ? .ready : .neutral
                ) {
                    if model.notificationStatus == .notDetermined {
                        Button("Enable Notifications") {
                            Task { await model.requestNotificationPermission() }
                        }
                    } else if model.notificationStatus != .authorized {
                        Button("Open System Settings") {
                            model.openSystemSettings()
                        }
                        Button("Check Again") {
                            Task { await model.refreshSystemStatuses() }
                        }
                    } else {
                        EmptyView()
                    }
                }
                if model.notificationStatus == .denied {
                    Text("In System Settings, choose Notifications, then Homeward.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Label(
                    "No Accessibility, Screen Recording, administrator access, or account required.",
                    systemImage: "lock.shield"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    private func readinessRow<Actions: View>(
        title: String,
        detail: String,
        status: String,
        symbol: String,
        tone: HomewardTone,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    readinessIdentity(title: title, detail: detail)
                    Spacer(minLength: 16)
                    HomewardStatusLabel(
                        title: status,
                        symbol: symbol,
                        tone: tone
                    )
                }
                VStack(alignment: .leading, spacing: 8) {
                    readinessIdentity(title: title, detail: detail)
                    HomewardStatusLabel(
                        title: status,
                        symbol: symbol,
                        tone: tone
                    )
                }
            }
            HStack {
                actions()
            }
        }
    }

    private func readinessIdentity(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var readyStep: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Ready to cross the threshold", systemImage: "house")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(
                        "Homeward will begin following this setup only after you choose "
                            + "the start button below."
                    )
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }

            Section("Required") {
                reviewRow(
                    title: "Weekly schedule",
                    value: "\(scheduledDayCount) days with scheduled hours",
                    isReady: model.configuration.onboardingScheduleConfirmed,
                    notReadyLabel: "Required"
                )
                reviewRow(
                    title: "Work apps",
                    value: selectedApplicationSummary,
                    isReady: !model.configuration.selectedApplications.isEmpty,
                    notReadyLabel: "Required"
                )
                reviewRow(
                    title: "Closing style",
                    value: SchedulePresentation.closeModeName(
                        model.configuration.closeMode
                    ),
                    isReady: true
                )
            }

            Section("Readiness") {
                reviewRow(
                    title: "Start at Login · Recommended",
                    value: loginSummary,
                    isReady: model.loginItemStatus == .enabled,
                    notReadyLabel: "Recommended"
                )
                reviewRow(
                    title: "Notifications · Optional",
                    value: notificationSummary,
                    isReady: model.notificationStatus == .authorized,
                    notReadyLabel: "Optional"
                )
            }

            if !model.resolvedSchedule.isAvailable {
                Section("Starts immediately") {
                    Label(
                        "Work is currently closed. Starting Homeward will begin the "
                            + "selected \(SchedulePresentation.closeModeName(model.configuration.closeMode).lowercased()) flow.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func reviewRow(
        title: String,
        value: String,
        isReady: Bool,
        notReadyLabel: String = "Not enabled"
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(value)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 16)
                readinessMark(
                    isReady: isReady,
                    notReadyLabel: notReadyLabel
                )
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                Text(value)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                readinessMark(
                    isReady: isReady,
                    notReadyLabel: notReadyLabel
                )
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func readinessMark(
        isReady: Bool,
        notReadyLabel: String
    ) -> some View {
        HomewardStatusLabel(
            title: isReady ? "Ready" : notReadyLabel,
            symbol: isReady ? "checkmark.circle.fill" : "circle",
            tone: isReady ? .ready : .attention
        )
    }

    private var selectedApplicationSummary: String {
        let applications = model.configuration.selectedApplications
        guard !applications.isEmpty else {
            return "No apps selected"
        }
        if applications.count <= 3 {
            return applications.map(\.displayName).joined(separator: ", ")
        }
        return "\(applications.count) apps selected"
    }

    private var startButtonTitle: String {
        model.resolvedSchedule.isAvailable ? "Start Homeward" : "Start & Close Work Apps…"
    }

    private var scheduledDayCount: Int {
        model.configuration.schedule.rules.values.reduce(into: 0) { count, rule in
            if case .scheduled = rule {
                count += 1
            }
        }
    }

    private var loginSummary: String {
        switch model.loginItemStatus {
        case .enabled:
            "Starts automatically"
        case .notRegistered:
            "Off"
        case .requiresApproval:
            "Approval required"
        case .notFound:
            "Move Homeward to Applications"
        }
    }

    private var notificationSummary: String {
        switch model.notificationStatus {
        case .authorized:
            "Wind-down alerts enabled"
        case .notDetermined:
            "Not requested"
        case .denied:
            "Alerts are off"
        case .unavailable:
            "Unavailable"
        }
    }
}

private struct PreviewView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectionID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
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
                    ForEach(model.configuration.selectedApplications) { application in
                        Text(application.displayName).tag(Optional(application.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HomewardCard {
                HStack(alignment: .top, spacing: HomewardSpacing.medium) {
                    Image(systemName: statusSymbol)
                        .font(.title3)
                        .foregroundStyle(statusColor)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(statusTitle)
                            .font(.headline)
                        Text(statusText)
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
                        model.endPreview()
                        dismiss()
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
                        model.endPreview()
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(24)
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

    private var statusTitle: String {
        switch model.previewState {
        case .idle:
            "Ready to test"
        case .waitingForFirstExit:
            "Closing normally"
        case .waitingForRelaunch:
            "First close complete"
        case .waitingForSecondExit:
            "Relaunch detected"
        case .needsAttention:
            "App needs attention"
        case .complete:
            "Preview complete"
        }
    }

    private var statusColor: Color {
        switch model.previewState {
        case .complete:
            .green
        case .needsAttention:
            .orange
        case .idle:
            .secondary
        case .waitingForFirstExit, .waitingForRelaunch, .waitingForSecondExit:
            .accentColor
        }
    }

    private var statusText: String {
        switch model.previewState {
        case .idle:
            "Choose a harmless selected app, open it, then run the preview."
        case let .waitingForFirstExit(name):
            "Waiting for \(name) to close normally."
        case let .waitingForRelaunch(name):
            "Reopen \(name). Homeward will detect and close it automatically."
        case let .waitingForSecondExit(name):
            "Homeward detected the relaunch and is waiting for \(name) to close."
        case let .needsAttention(name):
            "\(name) needs your attention before the preview can continue."
        case let .complete(name):
            "Preview complete. Homeward closed both \(name) launches normally."
        }
    }

    private var statusSymbol: String {
        switch model.previewState {
        case .complete:
            "checkmark.circle"
        case .needsAttention:
            "exclamationmark.triangle"
        case .idle:
            "info.circle"
        case .waitingForFirstExit, .waitingForRelaunch, .waitingForSecondExit:
            "testtube.2"
        }
    }
}
