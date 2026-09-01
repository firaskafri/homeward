import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel
    @State private var confirmReset = false

    var body: some View {
        switch model.health {
        case .starting:
            ProgressView("Starting Homeward…")
                .frame(minWidth: 420, minHeight: 260)
                .task {
                    await model.start()
                }
        case .configurationUnavailable:
            recoveryView
        case .ready, .monitoringUnavailable:
            if model.isOnboardingComplete {
                ManagementView(model: model)
            } else {
                OnboardingView(model: model)
            }
        }
    }

    private var recoveryView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(
                "App closing is paused",
                systemImage: "exclamationmark.triangle"
            )
            .font(.title2.bold())
            Text("Homeward could not verify its saved settings, so it will not close any applications.")
                .foregroundStyle(.secondary)
            if let error = model.lastError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Retry") {
                    Task { await model.retryConfigurationLoad() }
                }
                Button("Restore Previous Settings…") {
                    Task { await model.restorePreviousConfiguration() }
                }
                Button("Reset Setup…", role: .destructive) {
                    confirmReset = true
                }
            }
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 320)
        .confirmationDialog(
            "Reset Homeward setup?",
            isPresented: $confirmReset
        ) {
            Button("Reset Setup", role: .destructive) {
                Task { await model.replaceWithFreshSetup() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This replaces unverified settings with a fresh setup. Saved thoughts remain.")
        }
        .accessibilityIdentifier("recovery.view")
    }
}
