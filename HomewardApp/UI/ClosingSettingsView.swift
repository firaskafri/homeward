import HomewardCore
import SwiftUI

struct ClosingSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var pendingFirmConfirmation = false

    var body: some View {
        Form {
            Section("Closing behavior") {
                Picker("Mode", selection: modeBinding) {
                    Text("Gentle Close").tag(CloseMode.gentle)
                    Text("Firm Close").tag(CloseMode.firm)
                }
                .pickerStyle(.radioGroup)
                .accessibilityIdentifier("closing.mode")

                if model.configuration.closeMode == .gentle {
                    Text("Requests a normal quit and never force-quits.")
                        .foregroundStyle(.secondary)
                } else {
                    Label(
                        "Homeward asks apps to quit normally, shows a full 30-second countdown, then may force-quit apps still running. Unsaved changes can be lost.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                }
            }

            Section("Wind-down") {
                Toggle(
                    "15-minute warning",
                    isOn: warningBinding(\.fifteenMinuteWarningEnabled)
                )
                Toggle(
                    "5-minute warning",
                    isOn: warningBinding(\.fiveMinuteWarningEnabled)
                )
                Toggle(
                    "Allow one 10-minute Gentle extension",
                    isOn: warningBinding(\.gentleExtensionEnabled)
                )
                .disabled(model.configuration.closeMode == .firm)
            }

            Section {
                Text("Firm Close never shortens the 30-second grace. Stop Force Quit pauses force escalation for the current blocked interval without making work apps available.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Closing")
        .confirmationDialog(
            "Enable Firm Close?",
            isPresented: $pendingFirmConfirmation
        ) {
            Button("Enable Firm Close", role: .destructive) {
                Task { await model.setCloseMode(.firm) }
            }
            Button("Keep Gentle Close", role: .cancel) {}
        } message: {
            Text("Firm Close can discard unsaved changes or interrupt active processes. Homeward always requests a normal quit and shows a full 30-second countdown first.")
        }
        .accessibilityIdentifier("closing.settings")
    }

    private var modeBinding: Binding<CloseMode> {
        Binding(
            get: { model.configuration.closeMode },
            set: { mode in
                if mode == .firm {
                    pendingFirmConfirmation = true
                } else {
                    Task { await model.setCloseMode(.gentle) }
                }
            }
        )
    }

    private func warningBinding(
        _ keyPath: WritableKeyPath<WarningPreferences, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: { model.configuration.warningPreferences[keyPath: keyPath] },
            set: { value in
                var preferences = model.configuration.warningPreferences
                preferences[keyPath: keyPath] = value
                Task { await model.setWarningPreferences(preferences) }
            }
        )
    }
}
