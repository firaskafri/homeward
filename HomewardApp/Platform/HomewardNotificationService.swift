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
    private static let warningIdentifierPrefix = "homeward-warning-"
    nonisolated private static let warningCutoffKey =
        "homeward-warning-cutoff"

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
    private var warningOperation = 0

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

    func start(handler: HomewardNotificationHandling) {
        guard !started else {
            responseRouter.handler = handler
            return
        }
        started = true
        responseRouter.handler = handler
        client.setDelegate(responseRouter)
        registerCategories(includeExtension: false)
    }

    func stop() {
        warningOperation &+= 1
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
        applicationNames: [String],
        preferences: HomewardCore.WarningPreferences,
        includeExtension: Bool
    ) async throws {
        warningOperation &+= 1
        let operation = warningOperation
        guard await removeWarnings(ifCurrent: operation) else {
            return
        }
        registerCategories(includeExtension: includeExtension)
        let now = nowProvider()
        var addedIdentifiers: [String] = []
        for offset in preferences.enabledOffsets {
            guard operation == warningOperation else {
                client.removePending(addedIdentifiers)
                return
            }
            let minutes = Int(offset / 60)
            let warningDate = cutoff.addingTimeInterval(-offset)
            guard warningDate > now else {
                continue
            }
            let content = UNMutableNotificationContent()
            content.title = minutes == 15
                ? "Workday ends in 15 minutes"
                : "5 minutes remaining"
            content.body = warningBody(
                minutes: minutes,
                applicationNames: applicationNames,
                cutoff: cutoff
            )
            content.categoryIdentifier = Self.warningCategory
            content.interruptionLevel = .active
            content.userInfo = Self.warningUserInfo(cutoff: cutoff)

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
        guard operation == warningOperation else {
            client.removePending(addedIdentifiers)
            return
        }
    }

    nonisolated static func warningUserInfo(
        cutoff: Date
    ) -> [AnyHashable: Any] {
        [warningCutoffKey: cutoff.timeIntervalSince1970]
    }

    nonisolated static func warningActionContext(
        from userInfo: [AnyHashable: Any]
    ) -> WarningActionContext? {
        guard let timestamp = userInfo[warningCutoffKey] as? TimeInterval,
              timestamp.isFinite else {
            return nil
        }
        return WarningActionContext(
            cutoff: Date(timeIntervalSince1970: timestamp)
        )
    }

    func postStatus(title: String, body: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.interruptionLevel = .passive
        let request = UNNotificationRequest(
            identifier: "homeward-status-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try await client.add(request)
    }

    func removeWarnings() async {
        warningOperation &+= 1
        _ = await removeWarnings(ifCurrent: warningOperation)
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

    private func registerCategories(includeExtension: Bool) {
        let startClosing = UNNotificationAction(
            identifier: Self.startClosingAction,
            title: "Start Closing Now…",
            options: [.foreground]
        )
        let extend = UNNotificationAction(
            identifier: Self.extendAction,
            title: "Extend \(HomewardPolicy.gentleShortcutExtensionMinutes) Minutes",
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
        minutes: Int,
        applicationNames: [String],
        cutoff: Date
    ) -> String {
        let sorted = applicationNames.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        let appSummary = ApplicationListFormatter.summary(
            names: sorted,
            emptyFallback: "Selected work apps become unavailable"
        )
        let time = cutoff.formatted(date: .omitted, time: .shortened)
        let closingStatement = sorted.isEmpty
            ? "\(appSummary) at \(time)."
            : "\(appSummary) will close at \(time)."
        return minutes == 15
            ? "Finish your current thought. \(closingStatement)"
            : closingStatement
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
