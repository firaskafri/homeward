import AppKit
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
