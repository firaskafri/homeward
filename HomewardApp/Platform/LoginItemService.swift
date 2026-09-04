import Foundation
import AppKit
import ServiceManagement

enum InstallationLocationStatus: Equatable {
    case applications
    case outsideApplications(URL)
    case unavailable

    var supportsStartAtLogin: Bool {
        self == .applications
    }
}

@MainActor
final class InstallationLocationService {
    private let statusProvider: () -> InstallationLocationStatus
    private let reveal: (URL) -> Void

    init(
        bundleURL: URL = Bundle.main.bundleURL,
        workspace: NSWorkspace = .shared
    ) {
        statusProvider = {
            let standardizedURL = bundleURL.standardizedFileURL
            let applicationsURL = URL(
                fileURLWithPath: "/Applications",
                isDirectory: true
            ).standardizedFileURL
            guard standardizedURL.pathExtension == "app" else {
                return .unavailable
            }
            return standardizedURL.deletingLastPathComponent()
                == applicationsURL
                ? .applications
                : .outsideApplications(standardizedURL)
        }
        reveal = { workspace.activateFileViewerSelecting([$0]) }
    }

    init(
        statusProvider: @escaping () -> InstallationLocationStatus,
        reveal: @escaping (URL) -> Void = { _ in }
    ) {
        self.statusProvider = statusProvider
        self.reveal = reveal
    }

    var status: InstallationLocationStatus {
        statusProvider()
    }

    func showInFinder() {
        guard case let .outsideApplications(url) = status else {
            return
        }
        reveal(url)
    }
}

@MainActor
final class LoginItemService {
    enum Status: Equatable {
        case notRegistered
        case enabled
        case requiresApproval
        case notFound
        case unavailable
    }

    enum ServiceStatus {
        case notRegistered
        case enabled
        case requiresApproval
        case notFound
        case unavailable
    }

    enum ServiceError: Error, Equatable {
        case unavailable
    }

    private let statusProvider: () -> ServiceStatus
    private let register: () throws -> Void
    private let unregister: () throws -> Void
    private let openSettings: () -> Void

    init(service: SMAppService = .mainApp) {
        statusProvider = {
            switch service.status {
            case .notRegistered:
                return .notRegistered
            case .enabled:
                return .enabled
            case .requiresApproval:
                return .requiresApproval
            case .notFound:
                return .notFound
            @unknown default:
                return .unavailable
            }
        }
        register = {
            try service.register()
        }
        unregister = {
            try service.unregister()
        }
        openSettings = {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    init(
        statusProvider: @escaping () -> ServiceStatus,
        register: @escaping () throws -> Void = {},
        unregister: @escaping () throws -> Void = {},
        openSettings: @escaping () -> Void = {}
    ) {
        self.statusProvider = statusProvider
        self.register = register
        self.unregister = unregister
        self.openSettings = openSettings
    }

    static func isolatedForUITesting() -> LoginItemService {
        LoginItemService(statusProvider: { .notRegistered })
    }

    var status: Status {
        switch statusProvider() {
        case .notRegistered:
            .notRegistered
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .notFound
        case .unavailable:
            .unavailable
        }
    }

    func enable() throws {
        guard statusProvider() != .unavailable else {
            throw ServiceError.unavailable
        }
        try register()
    }

    func disable() throws {
        switch statusProvider() {
        case .enabled, .requiresApproval:
            try unregister()
        case .notRegistered, .notFound:
            return
        case .unavailable:
            throw ServiceError.unavailable
        }
    }

    func openSystemSettings() {
        openSettings()
    }
}
