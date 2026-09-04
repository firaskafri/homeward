import Foundation
import HomewardCore
@preconcurrency import UserNotifications

@MainActor
protocol HomewardNotificationHandling: AnyObject {
    func handleNotificationAction(
        _ identifier: String,
        context: WarningActionContext?
    )
}

@MainActor
final class HomewardNotificationService {
    enum AuthorizationStatus: Equatable {
        case notDetermined
        case authorized
        case denied
        case unavailable
    }

    static let startClosingAction = "HOMEWARD_START_CLOSING"
    static let extendAction = "HOMEWARD_EXTEND_TEN"
    static let warningCategory = "HOMEWARD_WARNING"
    nonisolated private static let warningIdentifierPrefix =
        "homeward-warning-"
    nonisolated private static let statusIdentifierPrefix =
        "homeward-status-"
    nonisolated private static let warningCutoffKey =
        "homeward-warning-cutoff"
    nonisolated private static let policyGenerationKey =
        "homeward-policy-generation"

    enum StatusEvent: Equatable {
        case blockedLaunch(nextAvailability: Date?)
        case closingComplete(nextAvailability: Date?)

        var title: String {
            switch self {
            case .blockedLaunch:
                "A work app was closed"
            case .closingComplete:
                "Work is closed"
            }
        }

        var body: String {
            switch self {
            case let .blockedLaunch(nextAvailability):
                nextAvailability.map {
                    "Available \($0.formatted(date: .abbreviated, time: .shortened))."
                } ?? "No work window is scheduled."
            case let .closingComplete(nextAvailability):
                nextAvailability.map {
                    "Selected apps are unavailable until \($0.formatted(date: .abbreviated, time: .shortened))."
                } ?? "No work window is scheduled."
            }
        }
    }

    struct Client {
        let authorizationStatus: () async -> AuthorizationStatus
        let requestAuthorization: () async throws -> Bool
        let add: (UNNotificationRequest) async throws -> Void
        let pendingWarningIdentifiers: () async -> [String]
        let deliveredWarningIdentifiers: () async -> [String]
        let removePending: ([String]) -> Void
        let removeDelivered: ([String]) -> Void
        let setCategories: (Set<UNNotificationCategory>) -> Void
        let setDelegate: (UNUserNotificationCenterDelegate?) -> Void
    }

    private let client: Client
    private let nowProvider: () -> Date
    private let responseRouter = NotificationResponseRouter()
    private var started = false
    private var lifecycleGeneration = 0
    private var warningOperation = 0
    private var statusOperation = 0

    init(
        center: UNUserNotificationCenter = .current(),
        nowProvider: @escaping () -> Date = Date.init
    ) {
        client = Client(
            authorizationStatus: {
                let settings = await center.notificationSettings()
                switch settings.authorizationStatus {
                case .notDetermined:
                    return .notDetermined
                case .authorized, .provisional, .ephemeral:
                    return .authorized
                case .denied:
                    return .denied
                @unknown default:
                    return .unavailable
                }
            },
            requestAuthorization: {
                try await center.requestAuthorization(options: [.alert])
            },
            add: { request in
                try await center.add(request)
            },
            pendingWarningIdentifiers: {
                await center.pendingNotificationRequests()
                    .map(\.identifier)
            },
            deliveredWarningIdentifiers: {
                await center.deliveredNotifications()
                    .map(\.request.identifier)
            },
            removePending: {
                center.removePendingNotificationRequests(withIdentifiers: $0)
            },
            removeDelivered: {
                center.removeDeliveredNotifications(withIdentifiers: $0)
            },
            setCategories: {
                center.setNotificationCategories($0)
            },
            setDelegate: {
                center.delegate = $0
            }
        )
        self.nowProvider = nowProvider
    }

    init(
        client: Client,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.client = client
        self.nowProvider = nowProvider
    }

    static func isolatedForUITesting() -> HomewardNotificationService {
        HomewardNotificationService(
            client: Client(
                authorizationStatus: { .unavailable },
                requestAuthorization: { false },
                add: { _ in },
                pendingWarningIdentifiers: { [] },
                deliveredWarningIdentifiers: { [] },
                removePending: { _ in },
                removeDelivered: { _ in },
                setCategories: { _ in },
                setDelegate: { _ in }
            )
        )
    }

    func start(handler: HomewardNotificationHandling) {
        guard !started else {
            responseRouter.handler = handler
            return
        }
        started = true
        lifecycleGeneration &+= 1
        responseRouter.handler = handler
        client.setDelegate(responseRouter)
        registerCategories(includeExtension: false)
    }

    func stop() {
        lifecycleGeneration &+= 1
        warningOperation &+= 1
        statusOperation &+= 1
        started = false
        responseRouter.handler = nil
        client.setDelegate(nil)
    }

    func authorizationStatus() async -> AuthorizationStatus {
        await client.authorizationStatus()
    }

    func requestAuthorization() async throws -> Bool {
        try await client.requestAuthorization()
    }

    func replaceWarnings(
        cutoff: Date,
        policyGeneration: UInt64,
        preferences: HomewardCore.WarningPreferences,
        includeExtension: Bool
    ) async throws {
        guard started else {
            return
        }
        let generation = lifecycleGeneration
        warningOperation &+= 1
        let operation = warningOperation
        guard await removeWarnings(ifCurrent: operation) else {
            return
        }
        guard generation == lifecycleGeneration, started else {
            return
        }
        registerCategories(includeExtension: includeExtension)
        let now = nowProvider()
        var addedIdentifiers: [String] = []
        for leadTime in preferences.enabledLeadTimes {
            guard operation == warningOperation,
                  generation == lifecycleGeneration,
                  started else {
                client.removePending(addedIdentifiers)
                return
            }
            let offset = leadTime.offset
            let minutes = leadTime.rawValue
            let warningDate = cutoff.addingTimeInterval(-offset)
            guard warningDate > now else {
                continue
            }
            let content = UNMutableNotificationContent()
            content.title = switch leadTime {
            case .fifteenMinute:
                "Workday ends in 15 minutes"
            case .fiveMinute:
                "5 minutes remaining"
            }
            content.body = warningBody(
                leadTime: leadTime,
                cutoff: cutoff
            )
            content.categoryIdentifier = Self.warningCategory
            content.interruptionLevel = .active
            content.userInfo = Self.warningUserInfo(
                cutoff: cutoff,
                policyGeneration: policyGeneration
            )

            let components = Calendar.autoupdatingCurrent.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: warningDate
            )
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: components,
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: Self.warningIdentifierPrefix
                    + "\(operation)-\(minutes)-\(cutoff.timeIntervalSince1970)",
                content: content,
                trigger: trigger
            )
            do {
                try await client.add(request)
                addedIdentifiers.append(request.identifier)
            } catch {
                client.removePending(addedIdentifiers)
                throw error
            }
        }
        guard operation == warningOperation,
              generation == lifecycleGeneration,
              started else {
            client.removePending(addedIdentifiers)
            return
        }
    }

    nonisolated static func warningUserInfo(
        cutoff: Date,
        policyGeneration: UInt64
    ) -> [AnyHashable: Any] {
        [
            warningCutoffKey: cutoff.timeIntervalSince1970,
            policyGenerationKey: String(policyGeneration),
        ]
    }

    nonisolated static func warningActionContext(
        from userInfo: [AnyHashable: Any]
    ) -> WarningActionContext? {
        guard let timestamp = userInfo[warningCutoffKey] as? TimeInterval,
              timestamp.isFinite,
              let generationText = userInfo[policyGenerationKey] as? String,
              let policyGeneration = UInt64(generationText) else {
            return nil
        }
        return WarningActionContext(
            cutoff: Date(timeIntervalSince1970: timestamp),
            policyGeneration: policyGeneration
        )
    }

    func post(_ event: StatusEvent) async throws {
        guard started else {
            return
        }
        let generation = lifecycleGeneration
        let operation = statusOperation
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.body
        content.interruptionLevel = .passive
        let request = UNNotificationRequest(
            identifier: Self.statusIdentifierPrefix + UUID().uuidString,
            content: content,
            trigger: nil
        )
        try await client.add(request)
        guard started,
              generation == lifecycleGeneration,
              operation == statusOperation else {
            client.removePending([request.identifier])
            client.removeDelivered([request.identifier])
            return
        }
    }

    func removeWarnings() async {
        warningOperation &+= 1
        _ = await removeWarnings(ifCurrent: warningOperation)
    }

    func removeAllOwned() async {
        warningOperation &+= 1
        statusOperation &+= 1
        let warningOperation = warningOperation
        let statusOperation = statusOperation
        let pending = await client.pendingWarningIdentifiers()
        guard warningOperation == self.warningOperation,
              statusOperation == self.statusOperation else {
            return
        }
        let delivered = await client.deliveredWarningIdentifiers()
        guard warningOperation == self.warningOperation,
              statusOperation == self.statusOperation else {
            return
        }
        let identifiers = Set(pending + delivered).filter(Self.isOwned)
        client.removePending(Array(identifiers))
        client.removeDelivered(Array(identifiers))
    }

    private func removeWarnings(ifCurrent operation: Int) async -> Bool {
        let pending = await client.pendingWarningIdentifiers()
        guard operation == warningOperation else {
            return false
        }
        let delivered = await client.deliveredWarningIdentifiers()
        guard operation == warningOperation else {
            return false
        }
        let identifiers = Set(
            pending + delivered
        )
            .filter { $0.hasPrefix(Self.warningIdentifierPrefix) }
        client.removePending(Array(identifiers))
        client.removeDelivered(Array(identifiers))
        return true
    }

    nonisolated private static func isOwned(_ identifier: String) -> Bool {
        identifier.hasPrefix(warningIdentifierPrefix)
            || identifier.hasPrefix(statusIdentifierPrefix)
    }

    private func registerCategories(includeExtension: Bool) {
        let startClosing = UNNotificationAction(
            identifier: Self.startClosingAction,
            title: "End Work Now…",
            options: [.foreground]
        )
        let extend = UNNotificationAction(
            identifier: Self.extendAction,
            title:
                "Make All Work Apps Available for "
                + "\(HomewardPolicy.gentleShortcutExtensionMinutes) Minutes…",
            options: [.foreground]
        )
        let actions = includeExtension ? [startClosing, extend] : [startClosing]
        let category = UNNotificationCategory(
            identifier: Self.warningCategory,
            actions: actions,
            intentIdentifiers: [],
            options: []
        )
        client.setCategories([category])
    }

    private func warningBody(
        leadTime: WarningLeadTime,
        cutoff: Date
    ) -> String {
        let time = cutoff.formatted(date: .omitted, time: .shortened)
        let closingStatement = "Work apps will close at \(time)."
        return switch leadTime {
        case .fifteenMinute:
            "Finish your current thought. \(closingStatement)"
        case .fiveMinute:
            closingStatement
        }
    }
}

// UNUserNotificationCenterDelegate is called from framework-managed threads.
// The router carries only a weak main-actor handler and copies Sendable action
// data before crossing to MainActor.
private final class NotificationResponseRouter: NSObject,
    UNUserNotificationCenterDelegate,
    @unchecked Sendable
{
    @MainActor weak var handler: HomewardNotificationHandling?

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.actionIdentifier
        let context = HomewardNotificationService.warningActionContext(
            from: response.notification.request.content.userInfo
        )
        await MainActor.run { [weak self] in
            self?.handler?.handleNotificationAction(
                identifier,
                context: context
            )
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner]
    }
}
