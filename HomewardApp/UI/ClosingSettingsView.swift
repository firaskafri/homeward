import HomewardCore
import SwiftUI

struct ClosingSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var pendingFirmConfirmation = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: HomewardSpacing.small) {
                    Label("Choose how work apps close", systemImage: "power")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(
                        "Both modes ask apps to quit normally first. "
                            + "Only Firm Close can force-quit after a visible safety countdown."
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

            Section("Closing behavior") {
                Picker("Mode", selection: modeBinding) {
                    Text("Gentle Close").tag(CloseMode.gentle)
                    Text("Firm Close").tag(CloseMode.firm)
                }
                .pickerStyle(.radioGroup)
                .accessibilityIdentifier("closing.mode")

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        gentleComparison
                        firmComparison
                    }
                    VStack(spacing: 12) {
                        gentleComparison
                        firmComparison
                    }
                }

                if model.configuration.closeMode == .firm {
                    Label(
                        "Unsaved changes can be lost if an app reaches force quit.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                Text("Give yourself notice before the work window ends.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Toggle(
                    "15-minute warning",
                    isOn: warningBinding(.fifteenMinute)
                )
                Toggle(
                    "5-minute warning",
                    isOn: warningBinding(.fiveMinute)
                )
                Toggle(
                    "Allow one \(HomewardPolicy.gentleShortcutExtensionMinutes)-minute Gentle extension",
                    isOn: Binding(
                        get: {
                            model.configuration.gentleShortcutExtensionEnabled
                        },
                        set: { enabled in
                            Task {
                                await model.setGentleShortcutExtensionEnabled(
                                    enabled
                                )
                            }
                        }
                    )
                )
                .disabled(model.configuration.closeMode == .firm)
                if model.configuration.closeMode == .firm {
                    Text("Gentle extensions are unavailable while Firm Close is selected.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Wind-down")
            } footer: {
                Text("Warnings require notification permission. Closing still works without it.")
            }

            Section("Firm safety controls") {
                Label(
                    "A full \(Int(HomewardPolicy.firmGracePeriod))-second countdown always appears before force quit.",
                    systemImage: "timer"
                )
                Label(
                    "Stop Force Quit pauses escalation for the current blocked interval. "
                        + "It does not make work apps available.",
                    systemImage: "hand.raised"
                )
                .fixedSize(horizontal: false, vertical: true)
                Text("These safeguards cannot be shortened or bypassed.")
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
            Text(
                "Firm Close can discard unsaved changes or interrupt active "
                    + "processes. Homeward always requests a normal quit and shows "
                    + "a full \(Int(HomewardPolicy.firmGracePeriod))-second countdown first."
            )
        }
        .accessibilityIdentifier("closing.settings")
    }

    private var gentleComparison: some View {
        closingModeCard(
            title: "Gentle Close",
            symbol: "leaf",
            badge: "Recommended",
            details: [
                "Requests a normal quit",
                "Never force-quits",
                "Leaves blocked apps open if they need attention",
            ],
            isSelected: model.configuration.closeMode == .gentle,
            isCaution: false
        )
    }

    private var firmComparison: some View {
        closingModeCard(
            title: "Firm Close",
            symbol: "shield.lefthalf.filled",
            badge: "Higher enforcement",
            details: [
                "Requests a normal quit first",
                "Shows a \(Int(HomewardPolicy.firmGracePeriod))-second countdown",
                "May force-quit apps still running",
            ],
            isSelected: model.configuration.closeMode == .firm,
            isCaution: true
        )
    }

    private func closingModeCard(
        title: String,
        symbol: String,
        badge: String,
        details: [String],
        isSelected: Bool,
        isCaution: Bool
    ) -> some View {
        HomewardCard(padding: HomewardSpacing.medium) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(title, systemImage: symbol)
                        .font(.headline)
                    Spacer(minLength: HomewardSpacing.small)
                    HomewardStatusLabel(
                        title: isSelected ? "Selected" : badge,
                        symbol: isSelected ? "checkmark.circle.fill" : "info.circle",
                        tone: isSelected ? .ready : (isCaution ? .attention : .neutral)
                    )
                }
                ForEach(details, id: \.self) { detail in
                    Label(detail, systemImage: "checkmark")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            RoundedRectangle(
                cornerRadius: HomewardMetrics.cardCornerRadius,
                style: .continuous
            )
                .stroke(
                    isSelected
                        ? Color.accentColor
                        : Color.clear,
                    lineWidth: isSelected ? 1.5 : 0
                )
        }
        .accessibilityElement(children: .combine)
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
        _ option: AppModel.WarningOption
    ) -> Binding<Bool> {
        Binding(
            get: {
                switch option {
                case .fifteenMinute:
                    model.configuration.warningPreferences
                        .fifteenMinuteWarningEnabled
                case .fiveMinute:
                    model.configuration.warningPreferences
                        .fiveMinuteWarningEnabled
                }
            },
            set: { value in
                Task { await model.setWarning(option, enabled: value) }
            }
        )
    }
}
