import XCTest

// 1 - Name: Homeward UI test file.
// 2 - Description: Verifies startup, recovery, readiness, and primary navigation with isolated scenario fixtures.
// 3 - Assumptions: UI scenarios use temporary storage, inert platform adapters, and preview-only application identities.
// 4 - Expectations: Critical states remain reachable without selecting, launching, or controlling any installed user application.

/// 1 - Name: Homeward UI test suite.
/// 2 - Description: Exercises safe launch, retry, recovery separation, installation gating, and long-content navigation.
/// 3 - Assumptions: Each test launches one named scenario whose files and runtime adapters are isolated from user state.
/// 4 - Expectations: Native surfaces expose the expected state while automated lifecycle control remains fixture-only.
@MainActor
final class HomewardUITests: XCTestCase {
    private var fixture: IsolatedApplicationFixture?

    override func tearDown() async throws {
        try fixture?.remove()
        fixture = nil
    }

    /// 1 - Name: First-launch onboarding.
    /// 2 - Description: Launches Homeward and verifies setup is visible without relying on its menu-bar item.
    /// 3 - Assumptions: Storage is empty and the standard defaults override starts setup at step one.
    /// 4 - Expectations: Homeward exposes its status item and opens the first onboarding step.
    func testFirstLaunchShowsOnboarding() throws {
        let app = try launch(.firstLaunch)
        defer { app.terminate() }

        let statusItem = app.menuBars.statusItems.firstMatch
        XCTAssertTrue(
            statusItem.waitForExistence(timeout: UITestPolicy.launchTimeout)
        )
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: UITestPolicy.launchTimeout))
        XCTAssertTrue(
            app.descendants(matching: .any)["onboarding.step.1"]
                .waitForExistence(timeout: UITestPolicy.launchTimeout)
        )
    }

    /// 1 - Name: Completed-setup reopen.
    /// 2 - Description: Launches a completed setup and sends a bounded Launch Services reopen request.
    /// 3 - Assumptions: Preview-only application identities cannot match or close a real running process.
    /// 4 - Expectations: The window starts suppressed and reopening makes Today reachable.
    func testCompletedSetupReopensToday() throws {
        let app = try launch(.completedSetup)
        defer { app.terminate() }

        let window = app.windows.firstMatch
        XCTAssertFalse(window.waitForExistence(timeout: 1))
        let statusItem = app.menuBars.statusItems.firstMatch
        XCTAssertTrue(
            statusItem.waitForExistence(timeout: UITestPolicy.launchTimeout)
        )
        try reopenHomeward(app)

        XCTAssertTrue(
            window.waitForExistence(timeout: UITestPolicy.launchTimeout)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["today.view"]
                .waitForExistence(timeout: UITestPolicy.launchTimeout)
        )
    }

    /// 1 - Name: Delayed-startup retry.
    /// 2 - Description: Holds the first isolated catalog scan past the startup threshold and retries bootstrap.
    /// 3 - Assumptions: The scenario fixture releases subsequent catalog scans without touching installed applications.
    /// 4 - Expectations: Homeward states that closing has not started, offers Retry, and reaches onboarding after retry.
    func testDelayedStartupExplainsSafetyAndRetries() throws {
        let app = try launch(.delayedStartupRetry)
        defer { app.terminate() }
        try reopenHomeward(app)

        XCTAssertTrue(
            app.descendants(matching: .any)["startup.delayed"]
                .waitForExistence(timeout: UITestPolicy.launchTimeout)
        )
        XCTAssertTrue(
            app.staticTexts[
                "This is taking longer than expected. App closing has not started."
            ].exists
        )
        let retry = app.buttons["Retry"]
        XCTAssertTrue(retry.exists)
        retry.click()

        XCTAssertTrue(
            app.descendants(matching: .any)["onboarding.step.1"]
                .waitForExistence(timeout: UITestPolicy.launchTimeout)
        )
    }

    /// 1 - Name: Configuration-recovery isolation.
    /// 2 - Description: Launches with corrupt settings through an isolated storage scenario.
    /// 3 - Assumptions: No configuration can be trusted and no catalog application can be controlled.
    /// 4 - Expectations: Recovery supersedes schedule UI and exposes only settings-recovery actions.
    func testConfigurationRecoverySupersedesScheduleState() throws {
        let app = try launch(.configurationRecovery)
        defer { app.terminate() }

        XCTAssertTrue(
            app.descendants(matching: .any)["recovery.view"]
                .waitForExistence(timeout: UITestPolicy.launchTimeout)
        )
        XCTAssertTrue(app.staticTexts["App closing is paused"].exists)
        XCTAssertTrue(app.buttons["Retry"].exists)
        XCTAssertTrue(app.buttons["Restore Previous Settings…"].exists)
        XCTAssertTrue(app.buttons["Reset Setup…"].exists)
        XCTAssertFalse(app.staticTexts["Work available"].exists)
        XCTAssertFalse(app.staticTexts["Work is closed"].exists)
    }

    /// 1 - Name: Notes-recovery isolation.
    /// 2 - Description: Opens Saved Thoughts with valid completed settings and corrupt notes storage.
    /// 3 - Assumptions: The all-day fixture keeps thought review eligible while catalog and system integrations remain inert.
    /// 4 - Expectations: Runtime stays ready and Saved Thoughts offers notes-only recovery instead of configuration recovery.
    func testNotesRecoveryRemainsSeparateFromConfiguration() throws {
        let app = try launch(.notesRecovery)
        defer { app.terminate() }
        try reopenHomeward(app)

        let savedThoughtsNavigation = app.descendants(matching: .any)[
            "navigation.Saved Thoughts"
        ]
        XCTAssertTrue(
            savedThoughtsNavigation.waitForExistence(
                timeout: UITestPolicy.launchTimeout
            )
        )
        savedThoughtsNavigation.click()
        XCTAssertTrue(
            app.descendants(matching: .any)["notes.review"]
                .waitForExistence(timeout: UITestPolicy.launchTimeout)
        )
        XCTAssertTrue(
            app.staticTexts["Saved thoughts are unavailable"].exists
        )
        XCTAssertTrue(app.buttons["Retry"].exists)
        XCTAssertTrue(app.buttons["Reset Saved Thoughts…"].exists)
        XCTAssertFalse(
            app.buttons["Restore Previous Settings…"].exists
        )
    }

    /// 1 - Name: Installation-location login gating.
    /// 2 - Description: Opens Settings through the readiness attention action in the isolated outside-Applications scenario.
    /// 3 - Assumptions: Preview selections resolve, login-item and Finder adapters are inert, and no settings action button is invoked.
    /// 4 - Expectations: Start at Login is replaced by move guidance, Show in Finder, and Check Again.
    func testOutsideApplicationsShowsStartAtLoginGate() throws {
        let app = try launch(.outsideApplications)
        defer { app.terminate() }
        try reopenHomeward(app)
        app.activate()
        XCTAssertTrue(
            app.descendants(matching: .any)["today.view"]
                .waitForExistence(timeout: UITestPolicy.launchTimeout)
        )
        let attention = app.buttons.matching(
            NSPredicate(
                format: "label BEGINSWITH %@",
                "Homeward Needs Attention"
            )
        ).firstMatch
        XCTAssertTrue(
            attention.waitForExistence(timeout: UITestPolicy.navigationTimeout)
        )
        attention.click()

        XCTAssertTrue(
            app.descendants(matching: .any)["general.settings"]
                .waitForExistence(timeout: UITestPolicy.launchTimeout)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["settings.installationReason"]
                .exists
        )
        XCTAssertTrue(app.buttons["Show in Finder"].exists)
        XCTAssertTrue(app.buttons["Check Again"].exists)
    }

    /// 1 - Name: Long application-name reachability.
    /// 2 - Description: Opens Work Apps with a deliberately long preview-only application name.
    /// 3 - Assumptions: The application picker remains inert and the chooser is not invoked.
    /// 4 - Expectations: The full name and Choose Application action remain reachable.
    func testLongApplicationNameKeepsWorkAppsActionsReachable() throws {
        let app = try launch(.longContent)
        defer { app.terminate() }
        try reopenHomeward(app)

        let workAppsNavigation = app.descendants(matching: .any)[
            "navigation.Work Apps"
        ]
        XCTAssertTrue(
            workAppsNavigation.waitForExistence(
                timeout: UITestPolicy.launchTimeout
            )
        )
        workAppsNavigation.click()
        XCTAssertTrue(
            app.descendants(matching: .any)["apps.view"]
                .waitForExistence(timeout: UITestPolicy.navigationTimeout)
        )
        XCTAssertTrue(
            app.staticTexts["A Deliberately Long Work Application Name"]
                .waitForExistence(timeout: UITestPolicy.navigationTimeout)
        )
        XCTAssertTrue(app.buttons["Choose Application…"].firstMatch.exists)
    }

    private func launch(
        _ scenario: IsolatedApplicationFixture.Scenario
    ) throws -> XCUIApplication {
        let fixture = try IsolatedApplicationFixture(
            scenario: scenario,
            bundle: Bundle(for: Self.self)
        )
        self.fixture = fixture
        return fixture.launch()
    }

    private func reopenHomeward(_ app: XCUIApplication) throws {
        XCTAssertTrue(
            app.menuBars.statusItems.firstMatch
                .waitForExistence(timeout: UITestPolicy.launchTimeout)
        )
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

/// 1 - Name: Isolated UI application fixture.
/// 2 - Description: Maps named UI scenarios to temporary repository files and inert runtime adapters.
/// 3 - Assumptions: Bundled JSON resources contain preview-only identities and the application enforces UI-test isolation.
/// 4 - Expectations: Every launch receives unique storage and one scenario value, then removes all generated files.
@MainActor
private final class IsolatedApplicationFixture {
    enum Scenario {
        case firstLaunch
        case completedSetup
        case delayedStartupRetry
        case configurationRecovery
        case notesRecovery
        case outsideApplications
        case longContent

        var configurationResource: String? {
            switch self {
            case .firstLaunch, .delayedStartupRetry:
                nil
            case .completedSetup, .outsideApplications:
                "configuration"
            case .configurationRecovery:
                "corrupt"
            case .notesRecovery, .longContent:
                "configuration-available"
            }
        }

        var notesResource: String? {
            switch self {
            case .notesRecovery:
                "corrupt"
            default:
                nil
            }
        }

        var runtimeValue: String {
            switch self {
            case .delayedStartupRetry:
                "delayedStartupRetry"
            case .outsideApplications:
                "outsideApplications"
            default:
                "standard"
            }
        }

        var resetsOnboardingStep: Bool {
            self == .firstLaunch || self == .delayedStartupRetry
        }
    }

    private let scenario: Scenario
    private let directory: URL

    init(scenario: Scenario, bundle: Bundle) throws {
        self.scenario = scenario
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HomewardUITests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try Self.copy(
            resource: scenario.configurationResource,
            to: "configuration.json",
            bundle: bundle,
            directory: directory
        )
        try Self.copy(
            resource: scenario.notesResource,
            to: "notes.json",
            bundle: bundle,
            directory: directory
        )
    }

    func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.terminate()
        waitForTermination(of: app)
        if scenario.resetsOnboardingStep {
            app.launchArguments += [
                "-\(UITestPolicy.onboardingStepPreference)",
                "0",
            ]
        }
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["HOMEWARD_STORAGE_DIRECTORY"] = directory.path
        app.launchEnvironment[UITestPolicy.runtimeIsolationEnvironment] = "1"
        app.launchEnvironment[UITestPolicy.scenarioEnvironment] =
            scenario.runtimeValue
        app.launch()
        application = app
        return app
    }

    func remove() throws {
        if let application {
            application.terminate()
            waitForTermination(of: application)
        }
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    private var application: XCUIApplication?

    private func waitForTermination(of app: XCUIApplication) {
        let deadline = Date().addingTimeInterval(
            UITestPolicy.processTerminationTimeout
        )
        while app.state != .notRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    private static func copy(
        resource: String?,
        to destination: String,
        bundle: Bundle,
        directory: URL
    ) throws {
        guard let resource else {
            return
        }
        guard let resourceURL = bundle.url(
            forResource: resource,
            withExtension: "json"
        ) else {
            throw FixtureError.missingResource(resource)
        }
        try FileManager.default.copyItem(
            at: resourceURL,
            to: directory.appendingPathComponent(destination)
        )
    }
}

private enum FixtureError: Error {
    case missingResource(String)
    case reopenFailed(Int32)
    case reopenTimedOut
}

private enum UITestPolicy {
    static let launchTimeout: TimeInterval = 15
    static let navigationTimeout: TimeInterval = 5
    static let onboardingStepPreference = "onboardingStep"
    static let runtimeIsolationEnvironment = "HOMEWARD_UI_TESTING"
    static let scenarioEnvironment = "HOMEWARD_UI_TEST_SCENARIO"
    static let processTerminationTimeout: TimeInterval = 5
}
