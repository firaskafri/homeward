import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var navigation: HomewardNavigationState
    @State private var confirmReset = false

    var body: some View {
        switch model.presentationSnapshot.state {
        case .starting:
            ProgressView(model.presentationSnapshot.title)
                .frame(minWidth: 420, minHeight: 260)
        case .startupDelayed:
            delayedStartupView
        case .configurationRecovery:
            recoveryView
        case .applicationResolutionRecovery:
            applicationResolutionRecoveryView
        case .onboarding:
            OnboardingView(model: model)
        case .operational:
            ManagementView(model: model, navigation: navigation)
        }
    }

    private var delayedStartupView: some View {
        VStack(spacing: HomewardSpacing.large) {
            ProgressView(model.presentationSnapshot.title)
            Text(model.presentationSnapshot.transitionText ?? "")
                .foregroundStyle(.secondary)
            Button("Retry") {
                model.retryStartup()
            }
        }
        .padding(HomewardSpacing.xLarge)
        .frame(minWidth: 520, minHeight: 320)
        .accessibilityIdentifier("startup.delayed")
    }

    private var applicationResolutionRecoveryView: some View {
        VStack(alignment: .leading, spacing: HomewardSpacing.large) {
            Label(
                model.presentationSnapshot.title,
                systemImage: "exclamationmark.triangle"
            )
            .font(.title2.bold())
            Text(model.presentationSnapshot.transitionText ?? "")
            .foregroundStyle(.secondary)
            if let error = model.lastError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button("Retry") {
                model.retryStartup()
            }
        }
        .padding(HomewardSpacing.xLarge)
        .frame(minWidth: 520, minHeight: 320)
        .accessibilityIdentifier("application-resolution.recovery")
    }

    private var recoveryView: some View {
        VStack(alignment: .leading, spacing: HomewardSpacing.large) {
            Label(
                model.presentationSnapshot.title,
                systemImage: "exclamationmark.triangle"
            )
            .font(.title2.bold())
            Text(model.presentationSnapshot.transitionText ?? "")
                .foregroundStyle(.secondary)
            if let error = model.lastError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if model.isRecoveryInProgress {
                ProgressView("Recovering settings…")
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
            .disabled(model.isRecoveryInProgress)
        }
        .padding(HomewardSpacing.xLarge)
        .frame(minWidth: 520, minHeight: 320)
        .confirmationDialog(
            "Reset Homeward setup?",
            isPresented: $confirmReset
        ) {
            Button("Reset Setup", role: .destructive) {
                Task { await model.replaceWithFreshSetup() }
            }
            .disabled(model.isRecoveryInProgress)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This replaces unverified settings with a fresh setup. Saved thoughts remain.")
        }
        .accessibilityIdentifier("recovery.view")
    }
}
