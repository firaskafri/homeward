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
    private var mainWindowPresenter: ((HomewardRoute) -> Void)?
    private var pendingMainWindowRoute: HomewardRoute?

    func select(_ route: HomewardRoute) {
        selection = route
    }

    func requestMainWindow(_ route: HomewardRoute = .today) {
        select(route)
        guard let mainWindowPresenter else {
            pendingMainWindowRoute = route
            return
        }
        mainWindowPresenter(route)
    }

    func installMainWindowPresenter(
        _ presenter: @escaping (HomewardRoute) -> Void
    ) {
        mainWindowPresenter = presenter
        guard let pendingMainWindowRoute else {
            return
        }
        self.pendingMainWindowRoute = nil
        presenter(pendingMainWindowRoute)
    }
}

@main
struct HomewardApp: App {
    @NSApplicationDelegateAdaptor(HomewardApplicationDelegate.self)
    private var applicationDelegate
    @StateObject private var model: AppModel
    @StateObject private var navigation = HomewardNavigationState()
    private let presentsMainWindowOnLaunch: Bool

    init() {
        HomewardPreferenceKeys.migrate()
        presentsMainWindowOnLaunch =
            HomewardRepository.shouldPresentMainWindow()
        let instance: AppModel
        do {
            instance = try AppModel.makeDefault()
        } catch {
            fatalError("Homeward could not initialize local storage: \(error)")
        }
        _model = StateObject(wrappedValue: instance)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model, navigation: navigation)
        } label: {
            MenuBarLabel(
                model: model,
                navigation: navigation,
                applicationDelegate: applicationDelegate
            )
        }
        .menuBarExtraStyle(.menu)

        Window("Homeward", id: "homeward") {
            RootView(model: model, navigation: navigation)
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
            if showNextTransitionTime,
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
            navigation.installMainWindowPresenter { route in
                navigation.select(route)
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "homeward")
            }
            applicationDelegate.register(navigation: navigation)
            await model.start()
            if !model.isOnboardingComplete
                || model.health == .configurationUnavailable {
                navigation.requestMainWindow()
            }
        }
    }

    private var accessibilityState: String {
        let state = SchedulePresentation.stateTitle(
            schedule: model.resolvedSchedule,
            closingCount: model.closingRows.count
        )
        if let transition = model.resolvedSchedule.nextTransition {
            return "\(state). Next transition \(transition.date.formatted(date: .abbreviated, time: .shortened))."
        }
        return state
    }
}

private struct MenuContent: View {
    @ObservedObject var model: AppModel
    @ObservedObject var navigation: HomewardNavigationState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if requiresRecovery {
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
                Text(stateTitle)
                Text(transitionText)
                    .foregroundStyle(.secondary)
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

            if model.resolvedSchedule.isAvailable {
                Button("End Work Now…") {
                    confirmEndWork()
                }
            } else {
                Button("Save a Thought…") {
                    model.showNoteCapture()
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
                    confirmResumeFirmClosing()
                }
            }

            if model.loginItemStatus != .enabled || model.notificationStatus != .authorized {
                Divider()
                Button("Homeward Needs Attention…") {
                    openSettingsWindow()
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
        return false
    }

    private var stateTitle: String {
        SchedulePresentation.stateTitle(
            schedule: model.resolvedSchedule,
            closingCount: model.closingRows.count
        )
    }

    private var transitionText: String {
        SchedulePresentation.transitionText(for: model.resolvedSchedule)
    }

    private func confirmEndWork() {
        let alert = NSAlert()
        alert.messageText = "End work now?"
        alert.informativeText = "Homeward will begin the configured closing flow for selected work apps."
        alert.addButton(withTitle: "End Work Now")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        Task { await model.endWorkNow() }
    }

    private func confirmResumeFirmClosing() {
        let alert = NSAlert()
        alert.messageText = "Resume Firm Closing?"
        alert.informativeText =
            "Homeward will ask selected apps to quit normally and begin a new "
            + "\(Int(HomewardPolicy.firmGracePeriod))-second grace period."
        alert.addButton(withTitle: "Resume Firm Closing")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        Task { await model.resumeFirmClosing() }
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
private final class HomewardApplicationDelegate: NSObject, NSApplicationDelegate {
    private weak var navigation: HomewardNavigationState?
    private var pendingReopenRoute: HomewardRoute?

    func register(navigation: HomewardNavigationState) {
        self.navigation = navigation
        guard let pendingReopenRoute else {
            return
        }
        self.pendingReopenRoute = nil
        navigation.requestMainWindow(pendingReopenRoute)
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
        return false
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
