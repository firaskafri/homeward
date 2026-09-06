import AppKit
import Darwin
import Foundation
import HomewardCore
import XCTest

// 1 - Name: Homeward Release E2E shared support.
// 2 - Description: Creates exact-build application fixtures, isolated policy storage, monotonic timing, and identity-checked lifecycle cleanup.
// 3 - Assumptions: Xcode places Homeward, HomewardFixture, and the UI runner in one Release products directory.
// 4 - Expectations: Release tests control only verified build products and leave no Homeward or fixture process running.

@MainActor
final class ReleaseE2EFixture {
    private(set) var homeward: XCUIApplication?
    private(set) var controlledApplication: NSRunningApplication?
    let storageDirectory: URL
    let readyURL: URL
    let homewardURL: URL
    let fixtureURL: URL

    init(testBundle: Bundle = Bundle(for: ReleaseE2EFixture.self)) throws {
        let productsDirectory = try BuiltApplicationLocator.productsDirectory(
            testBundle: testBundle
        )
        homewardURL = try BuiltApplicationLocator.application(
            named: "Homeward.app",
            bundleIdentifier: ReleaseE2EPolicy.homewardBundleIdentifier,
            productsDirectory: productsDirectory
        )
        fixtureURL = try BuiltApplicationLocator.application(
            named: "HomewardFixture.app",
            bundleIdentifier: ReleaseE2EPolicy.fixtureBundleIdentifier,
            productsDirectory: productsDirectory
        )
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "HomewardReleaseE2E-\(UUID().uuidString)",
                isDirectory: true
            )
        readyURL = storageDirectory.appendingPathComponent(
            "runtime-ready"
        )
        try FileManager.default.createDirectory(
            at: storageDirectory,
            withIntermediateDirectories: true
        )
        try rejectUnexpectedApplications()
    }

    func launchHomeward(closeMode: CloseMode) async throws -> XCUIApplication {
        try writeConfiguration(closeMode: closeMode)
        try? FileManager.default.removeItem(at: readyURL)
        let app = XCUIApplication()
        app.launchEnvironment["HOMEWARD_STORAGE_DIRECTORY"] =
            storageDirectory.path
        app.launchEnvironment["HOMEWARD_UI_TESTING"] = "1"
        app.launchEnvironment["HOMEWARD_UI_TEST_SCENARIO"] =
            "releaseLifecycle"
        app.launchEnvironment["HOMEWARD_TEST_READY_FILE"] = readyURL.path
        app.launchArguments += [
            "--homeward-ui-test-storage=\(storageDirectory.path)",
            "--homeward-ui-test-scenario=releaseLifecycle",
            "--homeward-test-ready-file=\(readyURL.path)",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-ApplePersistenceIgnoreState", "YES",
        ]
        app.launch()
        homeward = app
        let statusItem = app.menuBars.statusItems.firstMatch
        guard statusItem.waitForExistence(
            timeout: ReleaseE2EPolicy.launchTimeout
        ) else {
            throw ReleaseE2EError.homewardDidNotBecomeReady
        }
        guard exactRunningApplication(
            bundleIdentifier: ReleaseE2EPolicy.homewardBundleIdentifier,
            bundleURL: homewardURL
        ) != nil else {
            throw ReleaseE2EError.runningIdentityMismatch(homewardURL)
        }
        let readyDeadline = ProcessInfo.processInfo.systemUptime
            + ReleaseE2EPolicy.launchTimeout
        while !FileManager.default.fileExists(atPath: readyURL.path),
              ProcessInfo.processInfo.systemUptime < readyDeadline {
            try await Task.sleep(
                for: .milliseconds(ReleaseE2EPolicy.pollMilliseconds)
            )
        }
        guard FileManager.default.fileExists(atPath: readyURL.path) else {
            throw ReleaseE2EError.homewardDidNotBecomeReady
        }
        return app
    }

    func launchFixture() async throws -> NSRunningApplication {
        guard controlledApplication == nil else {
            throw ReleaseE2EError.fixtureAlreadyRunning
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        let application = try await NSWorkspace.shared.openApplication(
            at: fixtureURL,
            configuration: configuration
        )
        guard identityMatches(
            application,
            bundleIdentifier: ReleaseE2EPolicy.fixtureBundleIdentifier,
            bundleURL: fixtureURL
        ) else {
            throw ReleaseE2EError.runningIdentityMismatch(fixtureURL)
        }
        controlledApplication = application
        let deadline = ProcessInfo.processInfo.systemUptime
            + ReleaseE2EPolicy.launchTimeout
        while !application.isFinishedLaunching,
              ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(
                for: .milliseconds(ReleaseE2EPolicy.pollMilliseconds)
            )
        }
        guard application.isFinishedLaunching,
              isRunning(
                  processIdentifier: application.processIdentifier
              ) else {
            throw ReleaseE2EError.fixtureDidNotBecomeReady
        }
        return application
    }

    func waitUntilTerminated(
        processIdentifier: pid_t,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            if !processIsRunning(processIdentifier) {
                return true
            }
            Thread.sleep(forTimeInterval: ReleaseE2EPolicy.pollInterval)
        }
        return !processIsRunning(processIdentifier)
    }

    func waitUntilUptime(_ uptime: TimeInterval) {
        while ProcessInfo.processInfo.systemUptime < uptime {
            Thread.sleep(forTimeInterval: ReleaseE2EPolicy.pollInterval)
        }
    }

    func isRunning(processIdentifier: pid_t) -> Bool {
        processIsRunning(processIdentifier)
    }

    func terminateControlledFixture() throws {
        guard let application = controlledApplication else {
            return
        }
        guard identityMatches(
            application,
            bundleIdentifier: ReleaseE2EPolicy.fixtureBundleIdentifier,
            bundleURL: fixtureURL
        ) else {
            throw ReleaseE2EError.runningIdentityMismatch(fixtureURL)
        }
        let processIdentifier = application.processIdentifier
        _ = application.forceTerminate()
        guard waitUntilTerminated(
            processIdentifier: processIdentifier,
            timeout: ReleaseE2EPolicy.terminationTimeout
        ) else {
            throw ReleaseE2EError.terminationTimedOut(fixtureURL)
        }
        controlledApplication = nil
    }

    func remove() throws {
        var cleanupError: Error?
        if let homeward,
           homeward.state == .runningBackground
            || homeward.state == .runningForeground {
            if exactRunningApplication(
                bundleIdentifier: ReleaseE2EPolicy.homewardBundleIdentifier,
                bundleURL: homewardURL
            ) == nil {
                cleanupError = ReleaseE2EError.runningIdentityMismatch(
                    homewardURL
                )
            } else {
                homeward.terminate()
                if !waitForProcessExit(
                    applicationURL: homewardURL,
                    bundleIdentifier:
                        ReleaseE2EPolicy.homewardBundleIdentifier,
                    timeout: ReleaseE2EPolicy.terminationTimeout
                ) {
                    cleanupError = ReleaseE2EError.terminationTimedOut(
                        homewardURL
                    )
                }
            }
        }
        if let application = controlledApplication,
           !application.isTerminated {
            if identityMatches(
                application,
                bundleIdentifier: ReleaseE2EPolicy.fixtureBundleIdentifier,
                bundleURL: fixtureURL
            ) {
                let processIdentifier = application.processIdentifier
                _ = application.forceTerminate()
                if !waitUntilTerminated(
                    processIdentifier: processIdentifier,
                    timeout: ReleaseE2EPolicy.terminationTimeout
                ) {
                    cleanupError = ReleaseE2EError.terminationTimedOut(
                        fixtureURL
                    )
                }
            } else {
                cleanupError = ReleaseE2EError.runningIdentityMismatch(
                    fixtureURL
                )
            }
        }
        try? FileManager.default.removeItem(at: storageDirectory)
        if let cleanupError {
            throw cleanupError
        }
    }

    private func writeConfiguration(closeMode: CloseMode) throws {
        let schedule = try WeeklySchedule(
            rules: Dictionary(
                uniqueKeysWithValues: Weekday.allCases.map {
                    ($0, DayRule.blockedAllDay)
                }
            )
        )
        let selectedApplication = SelectedApplication(
            bundleIdentifier: ReleaseE2EPolicy.fixtureBundleIdentifier,
            bundlePath: fixtureURL.path,
            displayName: "Homeward Fixture",
            developerName: "Homeward Tests"
        )
        let configuration = try HomewardConfiguration(
            schedule: schedule,
            selectedApplications: [selectedApplication],
            closeMode: closeMode,
            onboardingScheduleConfirmed: true,
            completedOnboarding: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(configuration).write(
            to: storageDirectory.appendingPathComponent(
                "configuration.json"
            ),
            options: .atomic
        )
    }

    private func rejectUnexpectedApplications() throws {
        let homewardApplications = NSRunningApplication.runningApplications(
            withBundleIdentifier: ReleaseE2EPolicy.homewardBundleIdentifier
        ).filter {
            !$0.isTerminated
                && processIsRunning($0.processIdentifier)
        }
        let fixtureApplications = NSRunningApplication.runningApplications(
            withBundleIdentifier: ReleaseE2EPolicy.fixtureBundleIdentifier
        ).filter {
            !$0.isTerminated
                && processIsRunning($0.processIdentifier)
        }
        guard homewardApplications.isEmpty, fixtureApplications.isEmpty else {
            throw ReleaseE2EError.unexpectedRunningApplication
        }
    }

    private func waitForProcessExit(
        applicationURL: URL,
        bundleIdentifier: String,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            if exactRunningApplication(
                bundleIdentifier: bundleIdentifier,
                bundleURL: applicationURL
            ) == nil {
                return true
            }
            Thread.sleep(forTimeInterval: ReleaseE2EPolicy.pollInterval)
        }
        return exactRunningApplication(
            bundleIdentifier: bundleIdentifier,
            bundleURL: applicationURL
        ) == nil
    }

    private func processIsRunning(_ processIdentifier: pid_t) -> Bool {
        errno = 0
        return Darwin.kill(processIdentifier, 0) == 0 || errno != ESRCH
    }

    private func exactRunningApplication(
        bundleIdentifier: String,
        bundleURL: URL
    ) -> NSRunningApplication? {
        let matches = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ).filter {
            identityMatches(
                $0,
                bundleIdentifier: bundleIdentifier,
                bundleURL: bundleURL
            )
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private func identityMatches(
        _ application: NSRunningApplication,
        bundleIdentifier: String,
        bundleURL: URL
    ) -> Bool {
        application.bundleIdentifier == bundleIdentifier
            && application.bundleURL?
                .resolvingSymlinksInPath()
                .standardizedFileURL
                == bundleURL
    }

}

enum ReleaseE2EError: Error {
    case fixtureAlreadyRunning
    case fixtureDidNotBecomeReady
    case homewardDidNotBecomeReady
    case runningIdentityMismatch(URL)
    case terminationTimedOut(URL)
    case unexpectedRunningApplication
}

enum ReleaseE2EPolicy {
    static let homewardBundleIdentifier = "com.firaskafri.homeward"
    static let fixtureBundleIdentifier = "com.firaskafri.homeward.fixture"
    static let launchTimeout: TimeInterval = 20
    static let terminationTimeout: TimeInterval = 15
    static let forceTerminationUpperBound: TimeInterval = 36
    static let firmGracePeriod: TimeInterval = 30
    static let graceLowerBoundTolerance: TimeInterval = 5
    static let pollInterval: TimeInterval = 0.05
    static let pollMilliseconds = 50
}
