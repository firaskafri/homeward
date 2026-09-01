import AppKit
import HomewardCore

@MainActor
final class RunningApplicationController {
    private var applicationsBySessionID: [String: NSRunningApplication] = [:]

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
    func requestNormalTermination(for sessionID: String) -> Bool {
        guard let application = validatedApplication(for: sessionID) else {
            return false
        }
        return application.terminate()
    }

    @discardableResult
    func requestForceTermination(for sessionID: String) -> Bool {
        guard let application = validatedApplication(for: sessionID) else {
            return false
        }
        return application.forceTerminate()
    }

    @discardableResult
    func activate(sessionID: String) -> Bool {
        guard let application = validatedApplication(for: sessionID) else {
            return false
        }
        return application.activate(options: [.activateAllWindows])
    }

    func isTerminated(sessionID: String) -> Bool {
        guard let application = applicationsBySessionID[sessionID] else {
            return true
        }
        return application.isTerminated
    }

    func remove(sessionID: String) {
        applicationsBySessionID.removeValue(forKey: sessionID)
    }

    private func validatedApplication(for sessionID: String) -> NSRunningApplication? {
        guard let application = applicationsBySessionID[sessionID],
              !application.isTerminated,
              let launchDate = application.launchDate
        else {
            return nil
        }
        let currentSessionID =
            "\(application.processIdentifier)-\(launchDate.timeIntervalSinceReferenceDate)"
        guard currentSessionID == sessionID else {
            return nil
        }
        return application
    }
}
