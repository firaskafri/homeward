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

    private let center: UNUserNotificationCenter
    private let responseRouter = NotificationResponseRouter()
    private var started = false

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func start(handler: HomewardNotificationHandling) {
        guard !started else {
            responseRouter.handler = handler
            return
        }
        started = true
        responseRouter.handler = handler
        center.delegate = responseRouter
        registerCategories(includeExtension: false)
    }

    func authorizationStatus() async -> AuthorizationStatus {
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
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert])
    }

    func replaceWarnings(
        cutoff: Date,
        applicationNames: [String],
        preferences: HomewardCore.WarningPreferences,
        includeExtension: Bool
    ) async throws {
        await removeWarnings()
        registerCategories(includeExtension: includeExtension)
        let now = Date()
        for offset in preferences.enabledOffsets {
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
                    + "\(minutes)-\(cutoff.timeIntervalSince1970)",
                content: content,
                trigger: trigger
            )
            try await center.add(request)
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
        guard let timestamp = userInfo[warningCutoffKey] as? TimeInterval else {
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
        try await center.add(request)
    }

    func removeWarnings() async {
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        let identifiers = Set(
            pending.map(\.identifier) + delivered.map(\.request.identifier)
        )
            .filter { $0.hasPrefix(Self.warningIdentifierPrefix) }
        center.removePendingNotificationRequests(
            withIdentifiers: Array(identifiers)
        )
        center.removeDeliveredNotifications(
            withIdentifiers: Array(identifiers)
        )
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
        center.setNotificationCategories([category])
    }

    private func warningBody(
        minutes: Int,
        applicationNames: [String],
        cutoff: Date
    ) -> String {
        let sorted = applicationNames.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        let appSummary: String
        if sorted.isEmpty {
            appSummary = "Selected work apps become unavailable"
        } else if sorted.count <= 3 {
            appSummary = sorted.joined(separator: ", ")
        } else {
            appSummary = sorted.prefix(3).joined(separator: ", ")
                + ", and \(sorted.count - 3) others"
        }
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
