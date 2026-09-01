import ServiceManagement

@MainActor
final class LoginItemService {
    enum Status: Equatable {
        case notRegistered
        case enabled
        case requiresApproval
        case notFound
    }

    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
    }

    var status: Status {
        switch service.status {
        case .notRegistered:
            .notRegistered
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .notFound
        @unknown default:
            .notFound
        }
    }

    func enable() throws {
        try service.register()
    }

    func disable() throws {
        try service.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
