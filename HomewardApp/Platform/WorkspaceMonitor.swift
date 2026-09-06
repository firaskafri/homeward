@preconcurrency import AppKit
import Foundation

@MainActor
protocol WorkspaceMonitorDelegate: AnyObject {
    func workspaceMonitor(
        _ monitor: WorkspaceMonitor,
        didLaunch application: NSRunningApplication
    )
    func workspaceMonitor(
        _ monitor: WorkspaceMonitor,
        didTerminate application: NSRunningApplication
    )
    func workspaceMonitorRequiresReconciliation(_ monitor: WorkspaceMonitor)
    func workspaceMonitorWillSuspend(_ monitor: WorkspaceMonitor)
    func workspaceMonitor(
        _ monitor: WorkspaceMonitor,
        sessionActiveDidChange isActive: Bool
    )
}

// NotificationCenter guarantees delivery on the requested main queue. This
// wrapper carries the framework-owned value into MainActor.assumeIsolated.
private struct SendableWorkspaceNotification: @unchecked Sendable {
    nonisolated(unsafe) let value: Notification

    nonisolated init(value: Notification) {
        self.value = value
    }
}

private struct WorkspaceObservation {
    let center: NotificationCenter
    let token: NSObjectProtocol
}

@MainActor
final class WorkspaceMonitor: NSObject {
    weak var delegate: WorkspaceMonitorDelegate?

    private let workspace: NSWorkspace
    private var started = false
    private var observations: [WorkspaceObservation] = []

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
        super.init()
    }

    var runningApplications: [NSRunningApplication] {
        workspace.runningApplications
    }

    var sessionIsLikelyActive: Bool {
        guard let frontmostBundleIdentifier = workspace
            .frontmostApplication?
            .bundleIdentifier else {
            return false
        }
        return frontmostBundleIdentifier != "com.apple.loginwindow"
    }

    func start() {
        guard !started else {
            return
        }
        started = true

        let center = workspace.notificationCenter
        observe(
            center,
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: workspace
        ) { monitor, notification in
            monitor.applicationDidLaunch(notification)
        }
        observe(
            center,
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: workspace
        ) { monitor, notification in
            monitor.applicationDidTerminate(notification)
        }
        observe(
            center,
            forName: NSWorkspace.willSleepNotification,
            object: workspace
        ) { monitor, notification in
            monitor.workspaceWillSleep(notification)
        }
        observe(
            center,
            forName: NSWorkspace.didWakeNotification,
            object: workspace
        ) { monitor, notification in
            monitor.workspaceDidWake(notification)
        }
        observe(
            center,
            forName: NSWorkspace.screensDidSleepNotification,
            object: workspace
        ) { monitor, notification in
            monitor.workspaceWillSleep(notification)
        }
        observe(
            center,
            forName: NSWorkspace.screensDidWakeNotification,
            object: workspace
        ) { monitor, notification in
            monitor.workspaceDidWake(notification)
        }
        observe(
            center,
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: workspace
        ) { monitor, notification in
            monitor.sessionDidBecomeActive(notification)
        }
        observe(
            center,
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: workspace
        ) { monitor, notification in
            monitor.sessionDidResignActive(notification)
        }

        let defaultCenter = NotificationCenter.default
        for name in [
            Notification.Name.NSSystemClockDidChange,
            .NSSystemTimeZoneDidChange,
            .NSCalendarDayChanged,
        ] {
            observe(
                defaultCenter,
                forName: name,
                object: nil
            ) { monitor, notification in
                monitor.systemTimeDidChange(notification)
            }
        }
    }

    func stop() {
        guard started else {
            return
        }
        started = false
        for observation in observations {
            observation.center.removeObserver(observation.token)
        }
        observations.removeAll()
    }

    private func observe(
        _ center: NotificationCenter,
        forName name: Notification.Name,
        object: Any?,
        handler: @escaping @MainActor @Sendable (
            WorkspaceMonitor,
            Notification
        ) -> Void
    ) {
        let token = center.addObserver(
            forName: name,
            object: object,
            queue: .main
        ) { [weak self] notification in
            let value = SendableWorkspaceNotification(value: notification)
            MainActor.assumeIsolated {
                guard let self, self.started else {
                    return
                }
                handler(self, value.value)
            }
        }
        observations.append(
            WorkspaceObservation(center: center, token: token)
        )
    }

    private func applicationDidLaunch(_ notification: Notification) {
        guard let application = notification.userInfo?[
            NSWorkspace.applicationUserInfoKey
        ] as? NSRunningApplication else {
            delegate?.workspaceMonitorRequiresReconciliation(self)
            return
        }
        delegate?.workspaceMonitor(self, didLaunch: application)
    }

    private func applicationDidTerminate(_ notification: Notification) {
        guard let application = notification.userInfo?[
            NSWorkspace.applicationUserInfoKey
        ] as? NSRunningApplication else {
            delegate?.workspaceMonitorRequiresReconciliation(self)
            return
        }
        delegate?.workspaceMonitor(self, didTerminate: application)
    }

    private func workspaceWillSleep(_ notification: Notification) {
        delegate?.workspaceMonitorWillSuspend(self)
    }

    private func workspaceDidWake(_ notification: Notification) {
        delegate?.workspaceMonitor(
            self,
            sessionActiveDidChange: sessionIsLikelyActive
        )
    }

    private func sessionDidBecomeActive(_ notification: Notification) {
        delegate?.workspaceMonitor(self, sessionActiveDidChange: true)
    }

    private func sessionDidResignActive(_ notification: Notification) {
        delegate?.workspaceMonitor(self, sessionActiveDidChange: false)
    }

    private func systemTimeDidChange(_ notification: Notification) {
        delegate?.workspaceMonitorRequiresReconciliation(self)
    }
}
