import HomewardCore
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: AppModel
    @AppStorage("onboardingStep") private var step = 0
    @State private var showPreview = false

    private let stepTitles = [
        "When is work available?",
        "Which apps belong to work?",
        "How should apps close?",
        "Keep Homeward ready",
        "Ready",
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Step \(step + 1) of \(stepTitles.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(stepTitles[step])
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                if step == 0 {
                    Text("Bring your Mac home. Leave work at work.")
                        .font(.title3)
                    Text("Homeward closes the work apps you choose when your workday ends and keeps them closed until your next work window.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)

            Divider()

            if let error = model.lastError {
                InlineErrorView(message: error) {
                    model.clearError()
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
            }

            Group {
                switch step {
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

            HStack {
                Button("Back") {
                    step = max(0, step - 1)
                }
                .disabled(step == 0)

                Spacer()

                if step == stepTitles.count - 1 {
                    Button("Test Setup…") {
                        showPreview = true
                    }
                    Button(startButtonTitle) {
                        Task { await model.completeOnboarding() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.configuration.selectedApplications.isEmpty)
                    .accessibilityIdentifier("onboarding.start")
                } else {
                    Button("Continue") {
                        step = min(stepTitles.count - 1, step + 1)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        (step == 0 && !model.configuration.onboardingScheduleConfirmed)
                            || (step == 1 && model.configuration.selectedApplications.isEmpty)
                    )
                }
            }
            .padding(16)
        }
        .frame(minWidth: 680, minHeight: 560)
        .sheet(isPresented: $showPreview) {
            PreviewView(model: model)
        }
        .accessibilityIdentifier("onboarding.step.\(step + 1)")
    }

    private var permissionStep: some View {
        Form {
            Section("Start at Login") {
                Text("Homeward must be running to apply the schedule after login.")
                    .foregroundStyle(.secondary)
                HStack {
                    Text(loginSummary)
                    Spacer()
                    switch model.loginItemStatus {
                    case .enabled:
                        Label("Enabled", systemImage: "checkmark.circle")
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

            Section("Notifications") {
                Text("Notifications provide wind-down and status messages. App closing still works without them.")
                    .foregroundStyle(.secondary)
                HStack {
                    Text(notificationSummary)
                    Spacer()
                    if model.notificationStatus == .notDetermined {
                        Button("Enable Notifications") {
                            Task { await model.requestNotificationPermission() }
                        }
                    } else if model.notificationStatus != .authorized {
                        Button("Open Notification Settings") {
                            model.openNotificationSettings()
                        }
                        Button("Check Again") {
                            Task { await model.refreshSystemStatuses() }
                        }
                    } else {
                        Label("Enabled", systemImage: "checkmark.circle")
                    }
                }
            }

            Section {
                Text("Homeward does not require Accessibility, Screen Recording, administrator access, or an account.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var readyStep: some View {
        Form {
            Section("Schedule") {
                LabeledContent("Scheduled-hour days") {
                    Text("\(scheduledDayCount)")
                }
            }
            Section("Work Apps") {
                LabeledContent("Selected") {
                    Text("\(model.configuration.selectedApplications.count)")
                }
            }
            Section("Closing") {
                LabeledContent("Mode") {
                    Text(model.configuration.closeMode == .gentle ? "Gentle Close" : "Firm Close")
                }
            }
            if !model.resolvedSchedule.isAvailable {
                Section {
                    Label(
                        "The current time is blocked. Starting Homeward will begin closing selected work apps.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
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
        VStack(alignment: .leading, spacing: 16) {
            Text("Test Setup")
                .font(.title2.bold())
            Text("The preview requests a normal quit. It never force-quits.")
                .foregroundStyle(.secondary)

            Picker("Application", selection: $selectionID) {
                Text("Choose an app").tag(UUID?.none)
                ForEach(model.configuration.selectedApplications) { application in
                    Text(application.displayName).tag(Optional(application.id))
                }
            }

            Label(statusText, systemImage: statusSymbol)
                .accessibilityIdentifier("preview.status")

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
                Button("Run Preview") {
                    guard let selectionID else {
                        return
                    }
                    model.startPreview(selectionID: selectionID)
                }
                .disabled(selectionID == nil || previewIsRunning)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 440, minHeight: 280)
        .onDisappear {
            model.endPreview()
        }
        .accessibilityIdentifier("preview.view")
    }

    private var previewIsRunning: Bool {
        switch model.previewState {
        case .idle, .complete, .needsAttention:
            false
        case .waitingForFirstExit, .waitingForRelaunch, .waitingForSecondExit:
            true
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
