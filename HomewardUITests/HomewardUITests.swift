import XCTest

// 1 - Name: Homeward UI test file.
// 2 - Description: Verifies first-launch setup and completed-setup reopening without interacting with real work applications.
// 3 - Assumptions: UI tests use isolated configuration storage and never enable enforcement.
// 4 - Expectations: Onboarding opens initially, while a completed setup stays hidden until a bounded reopen request.

/// 1 - Name: Homeward UI test suite.
/// 2 - Description: Exercises safe first-launch and completed-setup navigation through the application UI.
/// 3 - Assumptions: Each test controls its configuration through isolated storage.
/// 4 - Expectations: Onboarding opens automatically and Launch Services can reopen a suppressed Today window.
@MainActor
final class HomewardUITests: XCTestCase {
    private var storageDirectory: URL?

    override func tearDown() async throws {
        if let storageDirectory,
           FileManager.default.fileExists(atPath: storageDirectory.path) {
            try FileManager.default.removeItem(at: storageDirectory)
        }
        storageDirectory = nil
    }

    /// 1 - Name: First-launch onboarding.
    /// 2 - Description: Launches Homeward and verifies setup is visible without relying on its menu-bar item.
    /// 3 - Assumptions: Storage is empty and the standard defaults override starts setup at step one.
    /// 4 - Expectations: Homeward exposes its status item and opens the first onboarding step.
    func testFirstLaunchShowsOnboarding() throws {
        let app = try launchIsolatedApp(resetOnboardingStep: true)
        defer { app.terminate() }

        let statusItem = app.menuBars.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)["onboarding.step.1"]
                .waitForExistence(timeout: 5)
        )
    }

    /// 1 - Name: Completed-setup reopen.
    /// 2 - Description: Launches a deterministic completed setup, proves its Today window is suppressed, and requests a reopen.
    /// 3 - Assumptions: Preview-only application identities cannot match or close a real running process.
    /// 4 - Expectations: No window exists before reopening, then Launch Services makes Today reachable.
    func testCompletedSetupReopensToday() throws {
        let app = try launchIsolatedApp(configurationFixture: "configuration")
        defer { app.terminate() }

        let window = app.windows.firstMatch
        XCTAssertFalse(window.waitForExistence(timeout: 1))
        let statusItem = app.menuBars.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
        try reopenHomeward()

        XCTAssertTrue(window.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)["overview.view"]
                .waitForExistence(timeout: 5)
        )
    }

    private func launchIsolatedApp(
        configurationFixture: String? = nil,
        resetOnboardingStep: Bool = false
    ) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.terminate()
        let directory = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("HomewardUITests-\(UUID().uuidString)")
        storageDirectory = directory
        if let configurationFixture {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let bundle = Bundle(for: Self.self)
            guard let fixtureURL = bundle.url(
                forResource: configurationFixture,
                withExtension: "json"
            ) else {
                throw FixtureError.missingConfiguration
            }
            try FileManager.default.copyItem(
                at: fixtureURL,
                to: directory.appendingPathComponent("configuration.json")
            )
        }
        if resetOnboardingStep {
            app.launchArguments += [
                "-\(UITestPolicy.onboardingStepPreference)",
                "0",
            ]
        }
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["HOMEWARD_STORAGE_DIRECTORY"] = directory.path
        app.launch()
        return app
    }

    private func reopenHomeward() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-b", "com.firaskafri.homeward"]
        try process.run()
        let deadline = Date().addingTimeInterval(
            UITestPolicy.processTerminationTimeout
        )
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard !process.isRunning else {
            process.terminate()
            throw FixtureError.reopenTimedOut
        }
        guard process.terminationStatus == 0 else {
            throw FixtureError.reopenFailed(process.terminationStatus)
        }
    }
}

private enum FixtureError: Error {
    case missingConfiguration
    case reopenFailed(Int32)
    case reopenTimedOut
}

private enum UITestPolicy {
    static let onboardingStepPreference = "onboardingStep"
    static let processTerminationTimeout: TimeInterval = 5
}
