import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var model: AppModel
    @AppStorage(HomewardPreferenceKeys.showNextTransitionTime)
    private var showNextTransitionTime = false
    @State private var confirmResetSetup = false
    @State private var confirmResetNotes = false
    @State private var confirmTurnOff = false
    @State private var showsPrivacyDetails = false
    @State private var showsAboutDetails = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Keep Homeward ready", systemImage: "checklist")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(
                        "Homeward needs to be running to enforce your schedule. "
                            + "Notifications are helpful, but optional."
                    )
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }

            if let error = model.lastError {
                Section {
                    InlineErrorView(message: error) {
                        model.clearError()
                    }
                }
            }

            Section {
                readinessRow(
                    title: "Start at Login",
                    detail: "Restores your schedule after you sign in.",
                    requirement: "Recommended",
                    status: loginStatusText,
                    symbol: loginStatusHealthy
                        ? "checkmark.circle.fill"
                        : "exclamationmark.circle",
                    tone: loginStatusHealthy ? .ready : .attention
                )

                ViewThatFits(in: .horizontal) {
                    HStack {
                        loginItemActions
                        Spacer()
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        loginItemActions
                    }
                }
                Text("Homeward works only while it is running.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Recommended readiness")
            }

            Section {
                readinessRow(
                    title: "Notifications",
                    detail: "Shows wind-down and status messages.",
                    requirement: "Optional",
                    status: notificationStatusText,
                    symbol: notificationStatusHealthy
                        ? "checkmark.circle.fill"
                        : "bell.slash",
                    tone: notificationStatusHealthy ? .ready : .neutral
                )

                ViewThatFits(in: .horizontal) {
                    HStack {
                        notificationActions
                        Spacer()
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        notificationActions
                    }
                }
                Text("App closing still works when notifications are off.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if model.notificationStatus == .denied {
                    Label(
                        "In System Settings, choose Notifications, then Homeward.",
                        systemImage: "gear"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            } header: {
                Text("Optional readiness")
            }

            Section("Menu Bar") {
                Toggle(
                    "Show next transition time",
                    isOn: $showNextTransitionTime
                )
            }

            Section {
                DisclosureGroup(
                    "Privacy & permissions",
                    isExpanded: $showsPrivacyDetails
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(
                            "Schedules, app selections, and saved thoughts remain on this Mac.",
                            systemImage: "internaldrive"
                        )
                        Label(
                            "No Accessibility, Screen Recording, administrator access, or account is required.",
                            systemImage: "lock.shield"
                        )
                        Text(
                            "Homeward does not read documents, window titles, browser history, "
                                + "terminal commands, or AI conversations."
                        )
                        .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    .padding(.top, 8)
                }
            }

            Section {
                DisclosureGroup(
                    "About Homeward",
                    isExpanded: $showsAboutDetails
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Version") {
                            Text(version)
                        }
                        LabeledContent("Bundle identifier") {
                            Text(bundleIdentifier)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.top, 8)
                }
            }

            Section("Reset & turn off") {
                VStack(alignment: .leading, spacing: 4) {
                    Button("Reset Setup…", role: .destructive) {
                        confirmResetSetup = true
                    }
                    Text("Clear your schedule, work apps, and closing preferences.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Button("Reset Saved Thoughts…", role: .destructive) {
                        confirmResetNotes = true
                    }
                    Text("Delete every thought saved for a future work window.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Button("Turn Off Homeward…", role: .destructive) {
                        confirmTurnOff = true
                    }
                    Text("Disable Start at Login and quit Homeward.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
        .confirmationDialog(
            "Reset Homeward setup?",
            isPresented: $confirmResetSetup
        ) {
            Button("Reset Setup", role: .destructive) {
                Task { await model.resetSetup() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears the schedule, selected apps, closing preferences, and today-only changes. Saved thoughts and Start at Login remain.")
        }
        .confirmationDialog(
            "Delete all saved thoughts?",
            isPresented: $confirmResetNotes
        ) {
            Button("Delete Saved Thoughts", role: .destructive) {
                Task { await model.resetSavedThoughts() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .confirmationDialog(
            "Turn off Homeward?",
            isPresented: $confirmTurnOff
        ) {
            Button("Turn Off Homeward", role: .destructive) {
                Task { await model.turnOff() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Homeward will cancel pending force quits, disable Start at Login, and quit. Apps already asked to quit may still close. Settings and saved thoughts remain.")
        }
        .accessibilityIdentifier("general.settings")
    }

    private func readinessRow(
        title: String,
        detail: String,
        requirement: String,
        status: String,
        symbol: String,
        tone: HomewardTone
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                readinessIdentity(
                    title: title,
                    detail: detail,
                    requirement: requirement
                )
                Spacer(minLength: 16)
                HomewardStatusLabel(
                    title: status,
                    symbol: symbol,
                    tone: tone
                )
            }
            VStack(alignment: .leading, spacing: 8) {
                readinessIdentity(
                    title: title,
                    detail: detail,
                    requirement: requirement
                )
                HomewardStatusLabel(
                    title: status,
                    symbol: symbol,
                    tone: tone
                )
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func readinessIdentity(
        title: String,
        detail: String,
        requirement: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(requirement)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var loginStatusText: String {
        switch model.loginItemStatus {
        case .enabled:
            "Enabled"
        case .notRegistered:
            "Off"
        case .requiresApproval:
            "Approval required"
        case .notFound:
            "Unavailable"
        }
    }

    private var loginStatusHealthy: Bool {
        model.loginItemStatus == .enabled
    }

    @ViewBuilder
    private var loginItemActions: some View {
        switch model.loginItemStatus {
        case .enabled:
            Button("Disable") {
                model.disableStartAtLogin()
            }
        case .notRegistered:
            Button("Enable") {
                model.enableStartAtLogin()
            }
        case .requiresApproval, .notFound:
            Button("Open Login Items") {
                model.openLoginItemSettings()
            }
            Button("Check Again") {
                Task { await model.refreshSystemStatuses() }
            }
        }
    }

    private var notificationStatusText: String {
        switch model.notificationStatus {
        case .authorized:
            "Enabled"
        case .notDetermined:
            "Not requested"
        case .denied:
            "Off"
        case .unavailable:
            "Unavailable"
        }
    }

    private var notificationStatusHealthy: Bool {
        model.notificationStatus == .authorized
    }

    @ViewBuilder
    private var notificationActions: some View {
        switch model.notificationStatus {
        case .authorized:
            Button("Check Again") {
                Task { await model.refreshSystemStatuses() }
            }
        case .notDetermined:
            Button("Enable Notifications") {
                Task { await model.requestNotificationPermission() }
            }
        case .denied, .unavailable:
            Button("Open System Settings") {
                model.openSystemSettings()
            }
            Button("Check Again") {
                Task { await model.refreshSystemStatuses() }
            }
        }
    }

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
            as? String ?? "Unknown"
        return "\(short) (\(build))"
    }

    private var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "Unavailable"
    }

}
