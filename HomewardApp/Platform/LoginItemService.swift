import Foundation
import ServiceManagement

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
