import AppKit
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
    func workspaceMonitor(
        _ monitor: WorkspaceMonitor,
        sessionActiveDidChange isActive: Bool
    )
}

@MainActor
final class WorkspaceMonitor: NSObject {
    weak var delegate: WorkspaceMonitorDelegate?

    private let workspace: NSWorkspace
    private var started = false

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
        center.addObserver(
            self,
            selector: #selector(applicationDidLaunch(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: workspace
        )
        center.addObserver(
            self,
            selector: #selector(applicationDidTerminate(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: workspace
        )
        center.addObserver(
            self,
            selector: #selector(workspaceDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: workspace
        )
        center.addObserver(
            self,
            selector: #selector(sessionDidBecomeActive(_:)),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: workspace
        )
        center.addObserver(
            self,
            selector: #selector(sessionDidResignActive(_:)),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: workspace
        )

        let defaultCenter = NotificationCenter.default
        defaultCenter.addObserver(
            self,
            selector: #selector(systemTimeDidChange(_:)),
            name: .NSSystemClockDidChange,
            object: nil
        )
        defaultCenter.addObserver(
            self,
            selector: #selector(systemTimeDidChange(_:)),
            name: .NSSystemTimeZoneDidChange,
            object: nil
        )
        defaultCenter.addObserver(
            self,
            selector: #selector(systemTimeDidChange(_:)),
            name: .NSCalendarDayChanged,
            object: nil
        )
    }

    func stop() {
        guard started else {
            return
        }
        started = false
        workspace.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    @objc
    private func applicationDidLaunch(_ notification: Notification) {
        guard let application = notification.userInfo?[
            NSWorkspace.applicationUserInfoKey
        ] as? NSRunningApplication else {
            delegate?.workspaceMonitorRequiresReconciliation(self)
            return
        }
        delegate?.workspaceMonitor(self, didLaunch: application)
    }

    @objc
    private func applicationDidTerminate(_ notification: Notification) {
        guard let application = notification.userInfo?[
            NSWorkspace.applicationUserInfoKey
        ] as? NSRunningApplication else {
            delegate?.workspaceMonitorRequiresReconciliation(self)
            return
        }
        delegate?.workspaceMonitor(self, didTerminate: application)
    }

    @objc
    private func workspaceDidWake(_ notification: Notification) {
        delegate?.workspaceMonitorRequiresReconciliation(self)
    }

    @objc
    private func sessionDidBecomeActive(_ notification: Notification) {
        delegate?.workspaceMonitor(self, sessionActiveDidChange: true)
        delegate?.workspaceMonitorRequiresReconciliation(self)
    }

    @objc
    private func sessionDidResignActive(_ notification: Notification) {
        delegate?.workspaceMonitor(self, sessionActiveDidChange: false)
    }

    @objc
    private func systemTimeDidChange(_ notification: Notification) {
        delegate?.workspaceMonitorRequiresReconciliation(self)
    }
}
