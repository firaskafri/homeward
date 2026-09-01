import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var model: AppModel
    @AppStorage("showRemainingTime") private var showRemainingTime = false
    @State private var confirmResetSetup = false
    @State private var confirmResetNotes = false
    @State private var confirmTurnOff = false

    var body: some View {
        Form {
            Section("Start at Login") {
                LabeledContent("Status") {
                    Text(loginStatusText)
                        .foregroundStyle(loginStatusHealthy ? Color.secondary : Color.orange)
                }
                HStack {
                    loginItemActions
                }
                Text("Homeward works only while it is running. Start at Login restores enforcement after your next login.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Notifications") {
                LabeledContent("Status") {
                    Text(notificationStatusText)
                        .foregroundStyle(notificationStatusHealthy ? Color.secondary : Color.orange)
                }
                notificationActions
                Text("Notifications provide wind-down and status messages. App closing still works when notifications are off.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Menu Bar") {
                Toggle("Show next transition time", isOn: $showRemainingTime)
            }

            Section("Privacy") {
                Text("Schedules, app selections, and saved thoughts remain on this Mac. Homeward does not read documents, window titles, browser history, terminal commands, or AI conversations.")
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Version") {
                    Text(version)
                }
                Text("Bundle identifier: com.firaskafri.homeward")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Reset Setup…", role: .destructive) {
                    confirmResetSetup = true
                }
                Button("Reset Saved Thoughts…", role: .destructive) {
                    confirmResetNotes = true
                }
                Button("Turn Off Homeward…", role: .destructive) {
                    confirmTurnOff = true
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
            Button("Open Notification Settings") {
                model.openNotificationSettings()
            }
            Button("Check Again") {
                Task { await model.refreshSystemStatuses() }
            }
        }
    }

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "0.1"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
            as? String ?? "1"
        return "\(short) (\(build))"
    }

}
