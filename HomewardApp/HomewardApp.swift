import AppKit
import HomewardCore
import SwiftUI

enum HomewardRoute: String, CaseIterable, Identifiable {
    case today = "Today"
    case schedule = "Schedule"
    case workApps = "Work Apps"
    case closing = "Closing & Warnings"
    case savedThoughts = "Saved Thoughts"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .today:
            "house"
        case .schedule:
            "calendar"
        case .workApps:
            "square.grid.2x2"
        case .closing:
            "power"
        case .savedThoughts:
            "note.text"
        }
    }
}

@MainActor
final class HomewardNavigationState: ObservableObject {
    @Published var selection: HomewardRoute? = .today
    private var mainWindowPresenter: (() -> Void)?
    private var hasPendingMainWindowRequest = false

    func select(_ route: HomewardRoute) {
        selection = route
    }

    func requestMainWindow(_ route: HomewardRoute = .today) {
        select(route)
        guard let mainWindowPresenter else {
            hasPendingMainWindowRequest = true
            return
        }
        mainWindowPresenter()
    }

    func installMainWindowPresenter(
        _ presenter: @escaping () -> Void
    ) {
        mainWindowPresenter = presenter
        guard hasPendingMainWindowRequest else {
            return
        }
        hasPendingMainWindowRequest = false
        presenter()
    }
}

@main
struct HomewardApp: App {
    @NSApplicationDelegateAdaptor(HomewardApplicationDelegate.self)
    private var applicationDelegate
    @StateObject private var model: AppModel
    @StateObject private var navigation: HomewardNavigationState
    private let presentsMainWindowOnLaunch: Bool

    init() {
        HomewardPreferenceKeys.migrate()
        presentsMainWindowOnLaunch =
            HomewardRepository.shouldPresentMainWindow()
        let instance: AppModel
        do {
            instance = try AppModel.makeDefault()
        } catch {
            fatalError("Homeward built-in defaults are invalid: \(error)")
        }
        let navigationState = HomewardNavigationState()
        _model = StateObject(wrappedValue: instance)
        _navigation = StateObject(wrappedValue: navigationState)
        instance.installRouteHandler { route in
            navigationState.requestMainWindow(route)
        }
        instance.installSensitivePresentationDismissalHandler {
            if navigationState.selection == .savedThoughts {
                navigationState.select(.today)
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(
                model: model,
                navigation: navigation
            )
        } label: {
            MenuBarLabel(
                model: model,
                navigation: navigation,
                applicationDelegate: applicationDelegate
            )
        }
        .menuBarExtraStyle(.menu)

        Window("Homeward", id: "homeward") {
            RootView(
                model: model,
                navigation: navigation
            )
        }
        .defaultSize(width: 760, height: 600)
        .defaultLaunchBehavior(
            presentsMainWindowOnLaunch ? .presented : .suppressed
        )
        .commands {
            HomewardCommands(model: model)
        }

        Settings {
            GeneralSettingsView(model: model)
                .disabled(!model.isPolicyMutationEnabled)
        }
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var navigation: HomewardNavigationState
    let applicationDelegate: HomewardApplicationDelegate
    @Environment(\.openWindow) private var openWindow
    @AppStorage(HomewardPreferenceKeys.showNextTransitionTime)
    private var showNextTransitionTime = false

    var body: some View {
        Group {
            if model.health == .ready,
               showNextTransitionTime,
               let transition = model.resolvedSchedule.nextTransition {
                Label(
                    transition.date.formatted(date: .omitted, time: .shortened),
                    systemImage: "house"
                )
            } else {
                Image(systemName: "house")
            }
        }
        .accessibilityLabel("Homeward")
        .accessibilityValue(accessibilityState)
        .task {
            navigation.installMainWindowPresenter {
                NSApp.unhide(nil)
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "homeward")
            }
            applicationDelegate.register(
                navigation: navigation,
                model: model
            )
        }
    }

    private var accessibilityState: String {
        model.presentationSnapshot.accessibilityValue
    }
}

private struct MenuContent: View {
    @ObservedObject var model: AppModel
    @ObservedObject var navigation: HomewardNavigationState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if model.health == .starting {
            Text("Starting Homeward…")
            Divider()
            Button("Quit Homeward…") {
                confirmQuit(model: model)
            }
        } else if model.health == .startupDelayed {
            Text("Starting Homeward…")
            Text("This is taking longer than expected. App closing has not started.")
            Button("Retry") {
                model.retryStartup()
            }
            Divider()
            Button("Quit Homeward…") {
                confirmQuit(model: model)
            }
        } else if requiresRecovery {
            Button("Open Recovery…") {
                navigation.requestMainWindow()
            }
            Divider()
            Button("Quit Homeward…") {
                confirmQuit(model: model)
            }
        } else if !model.isOnboardingComplete {
            Button("Finish Setup…") {
                navigation.requestMainWindow()
            }
            Divider()
            Button("Quit Homeward…") {
                confirmQuit(model: model)
            }
        } else {
            Section {
                Text(model.presentationSnapshot.title)
                if let transitionText = model.presentationSnapshot.transitionText {
                    Text(transitionText)
                    .foregroundStyle(.secondary)
                }
            }

            Section {
                Text("\(model.configuration.selectedApplications.count) work apps")
                Text(
                    SchedulePresentation.closeModeName(
                        model.configuration.closeMode
                    )
                )
                if let activeOverride = model.resolvedSchedule.activeOverride {
                    Text(
                        "Today-only change until "
                            + activeOverride.expiresAt.formatted(
                                date: .abbreviated,
                                time: .shortened
                            )
                    )
                }
            }

            if !model.closingRows.isEmpty {
                Button("Show Closing Progress…") {
                    model.showClosingDetails()
                }
            }

            if model.presentationSnapshot.savedThoughtCount > 0 {
                Button(
                    "Review Saved Thoughts (\(model.presentationSnapshot.savedThoughtCount))…"
                ) {
                    navigation.requestMainWindow(.savedThoughts)
                }
            }

            if model.resolvedSchedule.isAvailable {
                Button("End Work Now…") {
                    model.requestPolicyConfirmation(
                        .endWorkNow,
                        routeToToday: true
                    )
                }
            } else {
                switch model.notesHealth {
                case .available:
                    Button("Save a Thought…") {
                        model.showNoteCapture()
                    }
                case .loading:
                    Button("Loading Saved Thoughts…") {}
                        .disabled(true)
                case .unavailable:
                    Button("Saved Thoughts Need Attention…") {
                        navigation.requestMainWindow(.savedThoughts)
                    }
                }
            }

            Menu("Change Today Only…") {
                if model.canExtendToday {
                    ForEach(
                        HomewardPolicy.extensionDurationsMinutes,
                        id: \.self
                    ) { minutes in
                        Button("Extend by \(minutes) Minutes") {
                            Task { await model.createExtension(minutes: minutes) }
                        }
                    }
                }
                Button("Choose Another Cutoff…") {
                    model.showCustomCutoff()
                }
                if !model.resolvedSchedule.isAvailable {
                    Button("Make Work Available Now") {
                        Task { await model.makeWorkAvailableNow() }
                    }
                }
                Button("Take Today Off…") {
                    confirmTakeTodayOff()
                }
                if model.hasAvailabilityOverride {
                    Divider()
                    Button("Return to Weekly Schedule") {
                        Task { await model.returnToWeeklySchedule() }
                    }
                }
            }

            if model.forceEscalationPaused {
                Button("Resume Firm Closing…") {
                    model.requestPolicyConfirmation(
                        .resumeFirmClosing,
                        routeToToday: true
                    )
                }
            }

            if model.presentationSnapshot.attentionCount > 0 {
                Divider()
                Button(
                    "Homeward Needs Attention (\(model.presentationSnapshot.attentionCount))…"
                ) {
                    openPrimaryAttention()
                }
            }

            Divider()
            Button("Open Homeward") {
                navigation.requestMainWindow()
            }
            Button("Settings…") {
                openSettingsWindow()
            }
            .keyboardShortcut(",", modifiers: .command)
            Divider()
            Button("About Homeward") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.orderFrontStandardAboutPanel()
            }
            Button("Hide Homeward") {
                if model.closingRows.contains(where: {
                    $0.status == .countingDown
                }) {
                    Task {
                        await model.stopForceQuit()
                        NSApp.hide(nil)
                    }
                } else {
                    NSApp.hide(nil)
                }
            }
            Divider()
            Button("Quit Homeward…") {
                confirmQuit(model: model)
            }
        }
    }

    private func openSettingsWindow() {
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
    }

    private var requiresRecovery: Bool {
        if case .configurationUnavailable = model.health {
            return true
        }
        if case .applicationResolutionUnavailable = model.health {
            return true
        }
        return false
    }

    private func openPrimaryAttention() {
        switch model.primaryAttentionDestination {
        case .workApps:
            navigation.requestMainWindow(.workApps)
        case .savedThoughts:
            navigation.requestMainWindow(.savedThoughts)
        case .settings, .none:
            openSettingsWindow()
        }
    }

    private func confirmTakeTodayOff() {
        let alert = NSAlert()
        alert.messageText = "Take today off?"
        alert.informativeText = "Homeward will apply the configured closing flow now and keep work apps unavailable through today."
        alert.addButton(withTitle: "Take Today Off")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        Task { await model.takeTodayOff() }
    }

}

private struct HomewardCommands: Commands {
    @ObservedObject var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
            .disabled(!model.isPolicyMutationEnabled)
        }

        CommandGroup(replacing: .appTermination) {
            Button("Quit Homeward…") {
                confirmQuit(model: model)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}

@MainActor
final class HomewardApplicationDelegate: NSObject, NSApplicationDelegate {
    private static let delayedStartupThreshold: Duration = .seconds(3)

    private weak var navigation: HomewardNavigationState?
    private weak var model: AppModel?
    private var bootstrapTask: Task<Void, Never>?
    private var bootstrapRevision = 0
    private var didFinishLaunching = false
    private var pendingReopenRoute: HomewardRoute?
    private var terminationInProgress = false

    func register(
        navigation: HomewardNavigationState,
        model: AppModel
    ) {
        self.navigation = navigation
        self.model = model
        model.installBootstrapRetryHandler { [weak self] in
            self?.restartBootstrap()
        }
        if let pendingReopenRoute {
            self.pendingReopenRoute = nil
            navigation.requestMainWindow(pendingReopenRoute)
        }
        if didFinishLaunching {
            beginBootstrap()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        didFinishLaunching = true
        beginBootstrap()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if let navigation {
            navigation.requestMainWindow(.today)
        } else {
            pendingReopenRoute = .today
        }
        return true
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        bootstrapTask?.cancel()
        bootstrapTask = nil
        guard let model else {
            return .terminateNow
        }
        guard !terminationInProgress else {
            return .terminateLater
        }
        terminationInProgress = true
        Task {
            await model.prepareForTermination()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func beginBootstrap() {
        guard bootstrapTask == nil, let model else {
            return
        }
        bootstrapRevision &+= 1
        let revision = bootstrapRevision
        bootstrapTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            let delayedTask = Task { @MainActor [weak self] in
                try? await Task.sleep(
                    for: Self.delayedStartupThreshold
                )
                guard !Task.isCancelled,
                      let self,
                      self.bootstrapRevision == revision else {
                    return
                }
                self.model?.markStartupDelayed()
            }
            await model.start()
            delayedTask.cancel()
            guard !Task.isCancelled,
                  bootstrapRevision == revision else {
                return
            }
            bootstrapTask = nil
            if !model.isOnboardingComplete || model.health != .ready {
                navigation?.requestMainWindow()
            }
        }
    }

    private func restartBootstrap() {
        bootstrapTask?.cancel()
        bootstrapTask = nil
        beginBootstrap()
    }
}

@MainActor
private func confirmQuit(model: AppModel) {
    let alert = NSAlert()
    alert.messageText = "Quit Homeward?"
    alert.informativeText = "Pending force quits will be cancelled. Apps already asked to quit may still close. Selected apps will not be monitored until Homeward is reopened."
    alert.addButton(withTitle: "Quit Homeward")
    alert.addButton(withTitle: "Cancel")
    guard alert.runModal() == .alertFirstButtonReturn else {
        return
    }
    Task {
        await model.quit()
    }
}
