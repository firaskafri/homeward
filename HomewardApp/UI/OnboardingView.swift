import HomewardCore
import SwiftUI

struct OnboardingView: View {
    private enum AdvancementRequirement {
        case none
        case confirmedSchedule
        case selectedApplications
        case completedEssentials

        func isSatisfied(by model: AppModel) -> Bool {
            let hasResolvableApplication =
                model.configuration.selectedApplications.contains {
                    $0.isResolvable && !$0.isProtected
                }
            return switch self {
            case .none:
                true
            case .confirmedSchedule:
                model.configuration.onboardingScheduleConfirmed
            case .selectedApplications:
                hasResolvableApplication
            case .completedEssentials:
                model.configuration.onboardingScheduleConfirmed
                    && hasResolvableApplication
            }
        }

        var prompt: String? {
            return switch self {
            case .confirmedSchedule:
                "Save and confirm the schedule to continue"
            case .selectedApplications:
                "Choose at least one available work app to continue"
            case .none, .completedEssentials:
                nil
            }
        }
    }

    private struct StepMetadata {
        let title: String
        let subtitle: String
        let symbol: String
        let advancementRequirement: AdvancementRequirement
    }

    private enum Step: Int, CaseIterable {
        case schedule
        case applications
        case closing
        case readiness
        case review

        var metadata: StepMetadata {
            switch self {
            case .schedule:
                StepMetadata(
                    title: "Set your work window",
                    subtitle: "Define the weekly threshold between work time and personal time.",
                    symbol: "calendar.badge.clock",
                    advancementRequirement: .confirmedSchedule
                )
            case .applications:
                StepMetadata(
                    title: "Choose your work apps",
                    subtitle: "Only the apps you select will be managed by Homeward.",
                    symbol: "square.grid.2x2",
                    advancementRequirement: .selectedApplications
                )
            case .closing:
                StepMetadata(
                    title: "Choose a closing style",
                    subtitle: "Start gently, or opt into stronger enforcement with clear safeguards.",
                    symbol: "power",
                    advancementRequirement: .none
                )
            case .readiness:
                StepMetadata(
                    title: "Keep Homeward ready",
                    subtitle: "Choose which background conveniences you want to enable.",
                    symbol: "checklist",
                    advancementRequirement: .none
                )
            case .review:
                StepMetadata(
                    title: "Review and begin",
                    subtitle: "Confirm the essentials, then preview or start Homeward.",
                    symbol: "checkmark.seal",
                    advancementRequirement: .completedEssentials
                )
            }
        }
    }

    @ObservedObject var model: AppModel
    @AppStorage(HomewardPreferenceKeys.onboardingStep) private var step = 0
    @State private var showPreview = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: currentStep.metadata.symbol)
                        .font(.title2)
                        .foregroundStyle(HomewardTone.rest.color)
                        .frame(width: 38, height: 38)
                        .background(
                            HomewardTone.rest.color.opacity(0.12),
                            in: RoundedRectangle(
                                cornerRadius: HomewardMetrics.compactCornerRadius
                            )
                        )
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(
                            "STEP \(currentStep.rawValue + 1) OF \(Step.allCases.count)"
                        )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(currentStep.metadata.title)
                            .font(.largeTitle.bold())
                            .accessibilityAddTraits(.isHeader)
                    }
                }

                Text(currentStep.metadata.subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ProgressView(
                    value: Double(currentStep.rawValue + 1),
                    total: Double(Step.allCases.count)
                )
                .accessibilityLabel("Setup progress")
                .accessibilityValue(
                    "Step \(currentStep.rawValue + 1) of \(Step.allCases.count)"
                )
            }
            .frame(maxWidth: 860, alignment: .leading)
            .padding(HomewardSpacing.xLarge)

            Divider()

            if currentStep == .readiness || currentStep == .review,
               let error = model.lastError {
                InlineErrorView(message: error) {
                    model.clearError()
                }
                .frame(maxWidth: 860)
                .padding(.horizontal, HomewardSpacing.xLarge)
                .padding(.top, HomewardSpacing.medium)
            }

            Group {
                switch currentStep {
                case .schedule:
                    ScheduleEditorView(
                        model: model,
                        requiresOnboardingConfirmation: true
                    )
                case .applications:
                    AppPickerView(model: model)
                case .closing:
                    ClosingSettingsView(model: model)
                case .readiness:
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
                VStack(
                    alignment: .leading,
                    spacing: HomewardSpacing.medium
                ) {
                    footerStatus
                    onboardingActions
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .frame(maxWidth: 860)
            .padding(HomewardSpacing.large)
        }
        .frame(minWidth: 680, minHeight: 560)
        .sheet(isPresented: $showPreview) {
            PreviewView(model: model)
        }
        .onAppear {
            if step != currentStep.rawValue {
                step = currentStep.rawValue
            }
        }
        .accessibilityIdentifier("onboarding.step.\(currentStep.rawValue + 1)")
    }

    @ViewBuilder
    private var footerStatus: some View {
        if let prompt = currentStep.metadata.advancementRequirement.prompt,
           !currentStep.metadata.advancementRequirement.isSatisfied(by: model) {
            Label(prompt, systemImage: "circle.dashed")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if currentStep == .review {
            Label("Setup stays editable after you start", systemImage: "checkmark.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            EmptyView()
        }
    }

    private var onboardingActions: some View {
        HStack {
            Button("Back") {
                step = max(0, currentStep.rawValue - 1)
            }
            .disabled(currentStep == .schedule)

            if currentStep == .review {
                Button("Test Setup…") {
                    showPreview = true
                }
                Button(startButtonTitle) {
                    Task { await model.completeOnboarding() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    !currentStep.metadata.advancementRequirement
                        .isSatisfied(by: model)
                )
                .accessibilityIdentifier("onboarding.start")
            } else {
                Button("Continue") {
                    step = min(
                        Step.allCases.count - 1,
                        currentStep.rawValue + 1
                    )
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    !currentStep.metadata.advancementRequirement
                        .isSatisfied(by: model)
                )
            }
        }
    }

    private var currentStep: Step {
        let index = min(max(step, 0), Step.allCases.count - 1)
        return Step(rawValue: index) ?? .schedule
    }

    private var permissionStep: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: HomewardSpacing.small) {
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
                    presentation: loginReadiness
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
                    case .unavailable:
                        Button("Check Again") {
                            Task { await model.refreshSystemStatuses() }
                        }
                    }
                }
            }

            Section("Optional") {
                readinessRow(
                    title: "Notifications",
                    presentation: notificationReadiness
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
        presentation: ReadinessPresentation,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: HomewardSpacing.large) {
                    readinessIdentity(
                        title: title,
                        detail: presentation.detail
                    )
                    Spacer(minLength: HomewardSpacing.large)
                    HomewardStatusLabel(
                        title: presentation.status,
                        symbol: presentation.symbol,
                        tone: presentation.tone
                    )
                }
                VStack(alignment: .leading, spacing: HomewardSpacing.small) {
                    readinessIdentity(
                        title: title,
                        detail: presentation.detail
                    )
                    HomewardStatusLabel(
                        title: presentation.status,
                        symbol: presentation.symbol,
                        tone: presentation.tone
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
                VStack(alignment: .leading, spacing: HomewardSpacing.small) {
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
                    isReady: model.configuration.selectedApplications.contains {
                        $0.isResolvable && !$0.isProtected
                    },
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
            HStack(spacing: HomewardSpacing.large) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(value)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: HomewardSpacing.large)
                readinessMark(
                    isReady: isReady,
                    notReadyLabel: notReadyLabel
                )
            }
            VStack(alignment: .leading, spacing: HomewardSpacing.small) {
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
        if applications.count
            <= ApplicationListFormatter.maximumVisibleItemCount {
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
        case .unavailable:
            "Unavailable"
        }
    }

    private var loginReadiness: ReadinessPresentation {
        let presentation = ReadinessPresentation.login(
            model.loginItemStatus,
            readyTitle: loginSummary,
            unhealthySymbol: "exclamationmark.circle"
        )
        return ReadinessPresentation(
            status: loginSummary,
            detail: "Keeps your schedule active after you sign in.",
            symbol: presentation.symbol,
            tone: presentation.tone
        )
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

    private var notificationReadiness: ReadinessPresentation {
        let presentation = ReadinessPresentation.notifications(
            model.notificationStatus,
            readyTitle: notificationSummary,
            unhealthySymbol: "bell.slash",
            unhealthyTone: .neutral
        )
        return ReadinessPresentation(
            status: notificationSummary,
            detail: "Shows wind-down and status messages. Closing works without them.",
            symbol: presentation.symbol,
            tone: presentation.tone
        )
    }
}
