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
                VStack(alignment: .leading, spacing: HomewardSpacing.small) {
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
                .padding(.vertical, HomewardSpacing.xSmall)
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
                    detail: loginReadiness.detail,
                    requirement: "Recommended",
                    status: loginReadiness.status,
                    symbol: loginReadiness.symbol,
                    tone: loginReadiness.tone
                )

                ViewThatFits(in: .horizontal) {
                    HStack {
                        StartAtLoginActions(
                            model: model,
                            context: .settings
                        )
                        Spacer()
                    }
                    VStack(alignment: .leading, spacing: HomewardSpacing.small) {
                        StartAtLoginActions(
                            model: model,
                            context: .settings
                        )
                    }
                }
                if case .outsideApplications = model.installationLocationStatus {
                    Text(
                        "Move Homeward to the Applications folder yourself, then choose Check Again. Homeward will not move or delete itself."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings.installationReason")
                } else if case .requiresRelaunch =
                    model.installationLocationStatus {
                    Text(
                        "Your settings are saved. Quit Homeward, then reopen the copy in Applications."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings.relaunchReason")
                }
            } header: {
                Text("Recommended readiness")
            }

            Section {
                readinessRow(
                    title: "Notifications",
                    detail: "Shows wind-down and status messages.",
                    requirement: "Optional",
                    status: notificationReadiness.status,
                    symbol: notificationReadiness.symbol,
                    tone: notificationReadiness.tone
                )

                ViewThatFits(in: .horizontal) {
                    HStack {
                        notificationActions
                        Spacer()
                    }
                    VStack(alignment: .leading, spacing: HomewardSpacing.small) {
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
                    .padding(.top, HomewardSpacing.small)
                }
            }

            Section {
                DisclosureGroup(
                    "About Homeward",
                    isExpanded: $showsAboutDetails
                ) {
                    VStack(alignment: .leading, spacing: HomewardSpacing.small) {
                        LabeledContent("Version") {
                            Text(shortVersion)
                        }
                        LabeledContent("Build") {
                            Text(buildVersion)
                        }
                        LabeledContent("Bundle identifier") {
                            Text(bundleIdentifier)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.top, HomewardSpacing.small)
                }
            }

            Section("Help & updates") {
                Link("Download Homeward…", destination: SupportLinks.download)
                Link("Release Notes…", destination: SupportLinks.releaseNotes)
                Link("Support…", destination: SupportLinks.support)
                Link("Privacy…", destination: SupportLinks.privacy)
                Text(
                    "Updates are manual in version 0.1.0. Download the latest release, quit Homeward, and replace the copy in Applications."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Section("Removal & data") {
                Text(
                    "To remove Homeward, turn it off, quit it, then move Homeward from Applications to the Trash."
                )
                Text(
                    "To delete local data, use Reset Setup and Reset Saved Thoughts before removing the app."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Section("Reset & turn off") {
                VStack(alignment: .leading, spacing: HomewardSpacing.xSmall) {
                    Button("Reset Setup…", role: .destructive) {
                        confirmResetSetup = true
                    }
                    Text("Clear your schedule, work apps, and closing preferences.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: HomewardSpacing.xSmall) {
                    Button("Reset Saved Thoughts…", role: .destructive) {
                        confirmResetNotes = true
                    }
                    Text("Delete every thought saved for a future work window.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: HomewardSpacing.xSmall) {
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
            Text("This permanently deletes every saved thought. This cannot be undone.")
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
            HStack(spacing: HomewardSpacing.large) {
                readinessIdentity(
                    title: title,
                    detail: detail,
                    requirement: requirement
                )
                Spacer(minLength: HomewardSpacing.large)
                HomewardStatusLabel(
                    title: status,
                    symbol: symbol,
                    tone: tone
                )
            }
            VStack(alignment: .leading, spacing: HomewardSpacing.small) {
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

    private var loginReadiness: ReadinessPresentation {
        return .login(
            model.loginItemStatus,
            installation: model.installationLocationStatus,
            readyTitle: "On",
            unhealthySymbol: "exclamationmark.circle"
        )
    }

    private var notificationReadiness: ReadinessPresentation {
        .notifications(
            model.notificationStatus,
            readyTitle: "Enabled",
            unhealthySymbol: "bell.slash",
            unhealthyTone: .neutral
        )
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

    private var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "Unknown"
    }

    private var buildVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
            as? String ?? "Unknown"
    }

    private var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "Unavailable"
    }

}

private enum SupportLinks {
    static let download = URL(
        string: "https://github.com/firaskafri/homeward/releases/latest"
    )!
    static let releaseNotes = URL(
        string: "https://github.com/firaskafri/homeward/releases"
    )!
    static let support = URL(
        string: "https://github.com/firaskafri/homeward/issues"
    )!
    static let privacy = URL(
        string: "https://github.com/firaskafri/homeward/blob/main/docs/PRIVACY.md"
    )!
}
