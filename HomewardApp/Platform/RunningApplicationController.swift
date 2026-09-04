import AppKit
import HomewardCore

@MainActor
final class RunningApplicationController {
    private var applicationsBySessionID: [ProcessSessionID: NSRunningApplication] = [:]
    private let controlPolicy: RunningApplicationControlPolicy

    init(
        controlPolicy: RunningApplicationControlPolicy = .forRuntime()
    ) {
        self.controlPolicy = controlPolicy
    }

    func snapshot(_ application: NSRunningApplication) -> RunningApplicationSnapshot {
        let snapshot = RunningApplicationSnapshot(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            bundlePath: application.bundleURL?.standardizedFileURL.path,
            displayName: application.localizedName ?? "Application",
            launchedAt: application.launchDate
        )
        if let sessionID = snapshot.processSessionID {
            applicationsBySessionID[sessionID] = application
        }
        return snapshot
    }

    func snapshots(_ applications: [NSRunningApplication]) -> [RunningApplicationSnapshot] {
        applications.map(snapshot)
    }

    @discardableResult
    func requestNormalTermination(for sessionID: ProcessSessionID) -> Bool {
        guard let application = validatedApplication(for: sessionID) else {
            return false
        }
        return application.terminate()
    }

    @discardableResult
    func requestForceTermination(for sessionID: ProcessSessionID) -> Bool {
        guard let application = validatedApplication(for: sessionID) else {
            return false
        }
        return application.forceTerminate()
    }

    @discardableResult
    func activate(sessionID: ProcessSessionID) -> Bool {
        guard let application = validatedApplication(for: sessionID) else {
            return false
        }
        return application.activate(options: [.activateAllWindows])
    }

    func isTerminated(sessionID: ProcessSessionID) -> Bool {
        guard let application = applicationsBySessionID[sessionID] else {
            return true
        }
        return application.isTerminated
    }

    func remove(sessionID: ProcessSessionID) {
        applicationsBySessionID.removeValue(forKey: sessionID)
    }

    func remove(processIdentifier: pid_t) {
        applicationsBySessionID = applicationsBySessionID.filter {
            $0.value.processIdentifier != processIdentifier
        }
    }

    func liveSessionID(
        processIdentifier: pid_t
    ) -> ProcessSessionID? {
        applicationsBySessionID.first { _, application in
            application.processIdentifier == processIdentifier
                && !application.isTerminated
        }?.key
    }

    private func validatedApplication(
        for sessionID: ProcessSessionID
    ) -> NSRunningApplication? {
        guard let application = applicationsBySessionID[sessionID],
              !application.isTerminated,
              let launchDate = application.launchDate,
              controlPolicy.permits(
                  bundleIdentifier: application.bundleIdentifier,
                  bundleURL: application.bundleURL
              )
        else {
            return nil
        }
        let currentSessionID = ProcessSessionID(
            processIdentifier: application.processIdentifier,
            launchedAt: launchDate
        )
        guard currentSessionID == sessionID else {
            return nil
        }
        return application
    }
}
