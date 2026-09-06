import AppKit
import Darwin
import HomewardCore
import XCTest

// 1 - Name: Homeward shell journey test file.
// 2 - Description: Drives production Homeward source through a separately identified test-shell build and isolated deterministic scenarios.
// 3 - Assumptions: Every case owns its storage, uses preview-only identities, and never controls an installed user application.
// 4 - Expectations: Critical onboarding, navigation, recovery, schedule, and notes journeys remain usable in the Release configuration.

/// 1 - Name: Homeward shell journey suite.
/// 2 - Description: Exercises coherent user journeys against the test-only Homeward shell rather than isolated view units.
/// 3 - Assumptions: Existing lower-level suites cover combinatorial domain behavior while this suite proves representative UI-to-persistence integration.
/// 4 - Expectations: Every required journey reaches its expected semantic UI state without retries, ordering dependencies, or shared storage.
@MainActor
final class HomewardJourneyUITests: XCTestCase {
    private var fixture: ShellApplicationFixture?

    override func tearDownWithError() throws {
        try fixture?.remove()
        fixture = nil
    }

    /// 1 - Name: First-launch onboarding journey.
    /// 2 - Description: Starts from empty storage, confirms the default schedule, and reaches the work-app requirement.
    /// 3 - Assumptions: The default schedule is valid but must be explicitly confirmed before setup can advance.
    /// 4 - Expectations: Setup starts at step one and then exposes a visible, programmatic blocker until an app is selected.
    func testFirstLaunchBeginsCompleteOnboardingJourney() throws {
        let app = try launch(.firstLaunch)
        XCTAssertTrue(element("onboarding.step.1", in: app).waitForExistence(
            timeout: ShellPolicy.launchTimeout
        ))
        let save = try require(
            app.buttons["schedule.save"],
            description: "schedule save button"
        )
        save.click()
        XCTAssertTrue(element("onboarding.step.2", in: app).waitForExistence(
            timeout: ShellPolicy.navigationTimeout
        ))
        XCTAssertTrue(element("onboarding.blocker", in: app).exists)
        XCTAssertFalse(app.buttons["Continue"].isEnabled)
    }

    /// 1 - Name: Explicit preview choice journey.
    /// 2 - Description: Opens onboarding review with completed essentials and chooses the explicit preview-skip path.
    /// 3 - Assumptions: Preview is optional and skipping it applies only to the current onboarding decision.
    /// 4 - Expectations: Run Preview, Skip Preview, and Start Homeward are separately visible, and skipping explains that preview remains available.
    func testOnboardingReviewOffersRunAndSkipPreview() throws {
        let app = try launch(.review)
        XCTAssertTrue(element("onboarding.step.5", in: app).waitForExistence(
            timeout: ShellPolicy.launchTimeout
        ))
        _ = try require(
            app.buttons["onboarding.runPreview"],
            description: "run preview button"
        )
        let skip = try require(
            app.buttons["onboarding.skipPreview"],
            description: "skip preview button"
        )
        _ = try require(
            app.buttons["onboarding.start"],
            description: "start Homeward button"
        )
        skip.click()
        XCTAssertTrue(
            app.staticTexts[
                "Preview skipped. You can run it later from Work Apps."
            ].waitForExistence(timeout: ShellPolicy.navigationTimeout)
        )
    }

    /// 1 - Name: Preview missing-application recovery journey.
    /// 2 - Description: Runs preview for a selected preview-only identity that is deliberately not running.
    /// 3 - Assumptions: The shell catalog resolves the selection without mapping it to an installed application.
    /// 4 - Expectations: Preview gives reason-specific recovery guidance and ends without an irreversible-quit warning.
    func testPreviewExplainsMissingApplication() throws {
        let app = try launch(.review)
        XCTAssertTrue(element("onboarding.step.5", in: app).waitForExistence(
            timeout: ShellPolicy.launchTimeout
        ))
        try require(
            app.buttons["onboarding.runPreview"],
            description: "run preview button"
        ).click()
        XCTAssertTrue(element("preview.view", in: app).waitForExistence(
            timeout: ShellPolicy.navigationTimeout
        ))

        let picker = try require(
            app.popUpButtons.firstMatch,
            description: "preview application picker"
        )
        picker.click()
        try require(
            app.menuItems["Studio"],
            description: "Studio preview option"
        ).click()
        try require(
            app.buttons["Run Preview"],
            description: "run preview confirmation"
        ).click()
        let previewStatus = try require(
            element("preview.status", in: app),
            description: "preview status"
        )
        XCTAssertTrue(
            (previewStatus.value as? String)?
                .contains("Open Studio, then run the preview again.") == true
        )
        try require(
            app.buttons["preview.end"].firstMatch,
            description: "end preview button"
        ).click()
        XCTAssertFalse(app.buttons["Continue Preview"].exists)
    }

    /// 1 - Name: Completed-setup management journey.
    /// 2 - Description: Launches completed setup and traverses every primary management destination.
    /// 3 - Assumptions: The shell catalog resolves the persisted preview application and the schedule is available all day.
    /// 4 - Expectations: Today, Schedule, Work Apps, Closing, and Saved Thoughts are reachable through production navigation.
    func testCompletedSetupTraversesPrimaryDestinations() throws {
        let app = try launch(.completed)
        XCTAssertTrue(element("today.view", in: app).waitForExistence(
            timeout: ShellPolicy.launchTimeout
        ))
        for destination in [
            "Today",
            "Schedule",
            "Work Apps",
            "Closing & Warnings",
            "Saved Thoughts",
        ] {
            let button = try require(
                element("navigation.\(destination)", in: app),
                description: "\(destination) navigation button"
            )
            button.click()
        }
        XCTAssertTrue(element("notes.review", in: app).exists)
    }

    /// 1 - Name: Configuration recovery journey.
    /// 2 - Description: Starts with corrupt settings and verifies that recovery supersedes ordinary schedule state.
    /// 3 - Assumptions: The shell writes malformed configuration into isolated storage before app bootstrap.
    /// 4 - Expectations: Closing is paused, recovery actions are visible, and no schedule claim is presented.
    func testCorruptConfigurationFailsOpenIntoRecovery() throws {
        let app = try launch(.configurationRecovery)
        XCTAssertTrue(element("recovery.view", in: app).waitForExistence(
            timeout: ShellPolicy.launchTimeout
        ))
        XCTAssertTrue(app.staticTexts["App closing is paused"].exists)
        XCTAssertTrue(app.buttons["Retry"].exists)
        XCTAssertFalse(app.staticTexts["Work available"].exists)
        XCTAssertFalse(app.staticTexts["Work is closed"].exists)
    }

    /// 1 - Name: Notes recovery isolation journey.
    /// 2 - Description: Starts with valid completed settings and corrupt notes, then opens Saved Thoughts.
    /// 3 - Assumptions: Configuration and notes are stored separately and only notes are malformed.
    /// 4 - Expectations: Runtime remains operational while Saved Thoughts offers notes-only recovery.
    func testNotesRecoveryDoesNotPauseRuntime() throws {
        let app = try launch(.notesRecovery)
        XCTAssertTrue(element("today.view", in: app).waitForExistence(
            timeout: ShellPolicy.launchTimeout
        ))
        try require(
            element("navigation.Saved Thoughts", in: app),
            description: "Saved Thoughts navigation button"
        ).click()
        XCTAssertTrue(element("notes.review", in: app).waitForExistence(
            timeout: ShellPolicy.navigationTimeout
        ))
        XCTAssertTrue(app.staticTexts["Saved thoughts are unavailable"].exists)
        XCTAssertFalse(app.buttons["Restore Previous Settings…"].exists)
    }

    /// 1 - Name: End-work-now journey.
    /// 2 - Description: Confirms the primary action from an available completed configuration.
    /// 3 - Assumptions: No selected process is running, so the override cannot control another application.
    /// 4 - Expectations: Today transitions to closed state, offers thought capture, and preserves Gentle configuration.
    func testEndWorkNowPresentsClosedGentleState() throws {
        let app = try launch(.completed)
        XCTAssertTrue(element("today.view", in: app).waitForExistence(
            timeout: ShellPolicy.launchTimeout
        ))
        try endWorkNow(in: app)
        XCTAssertTrue(element("today.state", in: app).exists)
        XCTAssertTrue(app.buttons["today.saveThought"].exists)
        try require(
            element("navigation.Closing & Warnings", in: app),
            description: "Closing & Warnings navigation button"
        ).click()
        XCTAssertTrue(element("closing.settings", in: app).waitForExistence(
            timeout: ShellPolicy.navigationTimeout
        ))
        XCTAssertTrue(app.radioButtons["Gentle Close"].exists)
    }

    /// 1 - Name: Return to weekly schedule consequence journey.
    /// 2 - Description: Removes a temporary availability override whose underlying weekly schedule is currently closed.
    /// 3 - Assumptions: The scenario starts available only because of a bounded today-only override and uses Gentle Close.
    /// 4 - Expectations: Homeward explains the exact immediate Gentle consequence and requires confirmation before applying the weekly schedule.
    func testReturnToWeeklyScheduleConfirmsImmediateClose() throws {
        let app = try launch(.temporarilyAvailable)
        XCTAssertTrue(element("today.view", in: app).waitForExistence(
            timeout: ShellPolicy.launchTimeout
        ))
        try require(
            app.menuButtons["today.changeToday"],
            description: "Change Today Only menu"
        ).click()
        let returnAction = try require(
            app.menuButtons["today.changeToday"]
                .menuItems["Return to Weekly Schedule"],
            description: "Return to Weekly Schedule action"
        )
        returnAction.click()

        let confirmation = try require(
            app.sheets.firstMatch.buttons["Return & Close"],
            description: "Return & Close confirmation"
        )
        XCTAssertTrue(
            app.staticTexts[
                "The weekly schedule is closed now. Homeward will begin Gentle Close after the change is saved."
            ].exists
        )
        confirmation.click()
        XCTAssertTrue(app.buttons["today.saveThought"].waitForExistence(
            timeout: ShellPolicy.navigationTimeout
        ))
    }

    private func launch(
        _ scenario: ShellApplicationFixture.Scenario
    ) throws -> XCUIApplication {
        let fixture = try ShellApplicationFixture(
            scenario: scenario,
            bundle: Bundle(for: Self.self)
        )
        self.fixture = fixture
        return try fixture.launch()
    }

    private func element(
        _ identifier: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func require(
        _ element: XCUIElement,
        description: String,
        timeout: TimeInterval = ShellPolicy.navigationTimeout,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> XCUIElement {
        try XCTUnwrap(
            element.waitForExistence(timeout: timeout) ? element : nil,
            "Missing \(description)",
            file: file,
            line: line
        )
    }

    private func endWorkNow(in app: XCUIApplication) throws {
        let action = try require(
            app.buttons["today.endWork"],
            description: "End Work Now action"
        )
        action.click()
        let confirmation = try require(
            app.sheets.firstMatch.buttons["End Work Now"],
            description: "End Work Now confirmation"
        )
        confirmation.click()
        XCTAssertTrue(app.buttons["today.saveThought"].waitForExistence(
            timeout: ShellPolicy.navigationTimeout
        ))
    }
}

/// 1 - Name: Isolated shell application fixture.
/// 2 - Description: Seeds temporary storage, launches the exact shell product, and performs identity-checked cleanup.
/// 3 - Assumptions: Xcode places the UI runner and HomewardTestShell in one Release products directory.
/// 4 - Expectations: Tests never attach to or terminate an installed application or a shell from another build directory.
@MainActor
private final class ShellApplicationFixture {
    enum Scenario {
        case firstLaunch
        case review
        case completed
        case temporarilyAvailable
        case configurationRecovery
        case notesRecovery

        var runtimeScenario: String {
            switch self {
            case .review, .completed, .temporarilyAvailable, .notesRecovery:
                "outsideApplications"
            case .firstLaunch, .configurationRecovery:
                "standard"
            }
        }

        var onboardingStep: Int? {
            self == .review ? 4 : (self == .firstLaunch ? 0 : nil)
        }

        var requiresReopen: Bool {
            switch self {
            case .completed, .temporarilyAvailable, .notesRecovery:
                true
            case .firstLaunch, .review, .configurationRecovery:
                false
            }
        }
    }

    private let scenario: Scenario
    private let directory: URL
    private let readyURL: URL
    private let applicationURL: URL
    private var application: XCUIApplication?

    init(scenario: Scenario, bundle: Bundle) throws {
        self.scenario = scenario
        applicationURL = try BuiltApplicationLocator.application(
            named: "HomewardTestShell.app",
            bundleIdentifier: ShellPolicy.bundleIdentifier,
            testBundle: bundle
        )
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "HomewardJourneyUITests-\(UUID().uuidString)",
                isDirectory: true
            )
        readyURL = directory.appendingPathComponent("runtime-ready")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try seedStorage()
    }

    func launch() throws -> XCUIApplication {
        try rejectUnexpectedRunningShells()
        let app = XCUIApplication()
        app.launchEnvironment["HOMEWARD_STORAGE_DIRECTORY"] = directory.path
        app.launchEnvironment["HOMEWARD_UI_TESTING"] = "1"
        app.launchEnvironment["HOMEWARD_UI_TEST_SCENARIO"] =
            scenario.runtimeScenario
        app.launchEnvironment["HOMEWARD_TEST_READY_FILE"] = readyURL.path
        app.launchArguments += [
            "--homeward-shell-storage=\(directory.path)",
            "--homeward-shell-runtime=\(scenario.runtimeScenario)",
            "--homeward-test-ready-file=\(readyURL.path)",
        ]
        if let onboardingStep = scenario.onboardingStep {
            app.launchArguments += ["-onboardingStep", "\(onboardingStep)"]
        }
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-ApplePersistenceIgnoreState", "YES",
        ]
        application = app
        app.launch()
        if scenario == .configurationRecovery {
            guard app.descendants(matching: .any)["recovery.view"]
                .waitForExistence(timeout: ShellPolicy.launchTimeout) else {
                throw ShellFixtureError.shellDidNotStart
            }
        } else {
            let readyDeadline = ProcessInfo.processInfo.systemUptime
                + ShellPolicy.launchTimeout
            while !FileManager.default.fileExists(atPath: readyURL.path),
                  ProcessInfo.processInfo.systemUptime < readyDeadline {
                Thread.sleep(forTimeInterval: ShellPolicy.pollInterval)
            }
            guard FileManager.default.fileExists(atPath: readyURL.path) else {
                throw ShellFixtureError.shellDidNotStart
            }
        }
        if scenario.requiresReopen {
            try reopen(app)
        }
        return app
    }

    func remove() throws {
        if let application,
           application.state == .runningBackground
            || application.state == .runningForeground {
            guard exactRunningShell() != nil else {
                throw ShellFixtureError.runningIdentityMismatch
            }
            application.terminate()
            let deadline = ProcessInfo.processInfo.systemUptime
                + ShellPolicy.terminationTimeout
            while application.state != .notRunning,
                  ProcessInfo.processInfo.systemUptime < deadline {
                Thread.sleep(forTimeInterval: ShellPolicy.pollInterval)
            }
            guard application.state == .notRunning else {
                throw ShellFixtureError.terminationTimedOut
            }
        }
        try? FileManager.default.removeItem(at: directory)
    }

    private func seedStorage() throws {
        let configurationURL = directory.appendingPathComponent(
            "configuration.json"
        )
        let notesURL = directory.appendingPathComponent("notes.json")
        switch scenario {
        case .firstLaunch:
            return
        case .configurationRecovery:
            try Data("{ invalid".utf8).write(to: configurationURL)
        case .review, .completed, .temporarilyAvailable, .notesRecovery:
            let baseRule: DayRule = scenario == .temporarilyAvailable
                ? .blockedAllDay
                : .availableAllDay
            let schedule = try WeeklySchedule(
                rules: Dictionary(
                    uniqueKeysWithValues: Weekday.allCases.map {
                        ($0, baseRule)
                    }
                )
            )
            let overrides: [ScheduleOverride]
            if scenario == .temporarilyAvailable {
                let now = Date()
                overrides = [
                    try ScheduleOverride(
                        kind: .makeAvailable,
                        effect: .allow,
                        effectiveAt: now.addingTimeInterval(-60),
                        expiresAt: now.addingTimeInterval(60 * 60)
                    ),
                ]
            } else {
                overrides = []
            }
            let configuration = try HomewardConfiguration(
                schedule: schedule,
                selectedApplications: [
                    SelectedApplication(
                        bundleIdentifier: "com.homeward.preview.studio",
                        bundlePath: "/Applications/Studio.app",
                        displayName: "Studio",
                        developerName: "Homeward Preview"
                    ),
                ],
                closeMode: .gentle,
                overrides: overrides,
                onboardingScheduleConfirmed: true,
                completedOnboarding: scenario != .review
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(configuration).write(
                to: configurationURL,
                options: .atomic
            )
            if scenario == .notesRecovery {
                try Data("{ invalid".utf8).write(to: notesURL)
            }
        }
    }

    private func reopen(_ app: XCUIApplication) throws {
        guard app.menuBars.statusItems.firstMatch.waitForExistence(
            timeout: ShellPolicy.launchTimeout
        ), exactRunningShell() != nil else {
            throw ShellFixtureError.runningIdentityMismatch
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [applicationURL.path]
        try process.run()
        let deadline = ProcessInfo.processInfo.systemUptime
            + ShellPolicy.terminationTimeout
        while process.isRunning,
              ProcessInfo.processInfo.systemUptime < deadline {
            Thread.sleep(forTimeInterval: ShellPolicy.pollInterval)
        }
        guard !process.isRunning else {
            process.terminate()
            throw ShellFixtureError.reopenTimedOut
        }
        guard process.terminationStatus == 0 else {
            throw ShellFixtureError.reopenFailed(process.terminationStatus)
        }
        guard app.windows["homeward"].waitForExistence(
            timeout: ShellPolicy.navigationTimeout
        ) else {
            throw ShellFixtureError.reopenTimedOut
        }
    }

    private func rejectUnexpectedRunningShells() throws {
        let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: ShellPolicy.bundleIdentifier
        ).filter { !$0.isTerminated }
        guard running.isEmpty else {
            throw ShellFixtureError.unexpectedRunningApplication
        }
    }

    private func exactRunningShell() -> NSRunningApplication? {
        let matches = NSRunningApplication.runningApplications(
            withBundleIdentifier: ShellPolicy.bundleIdentifier
        ).filter {
            !$0.isTerminated
                && $0.bundleURL?
                    .resolvingSymlinksInPath()
                    .standardizedFileURL == applicationURL
        }
        return matches.count == 1 ? matches[0] : nil
    }

}

private enum ShellFixtureError: Error {
    case reopenFailed(Int32)
    case reopenTimedOut
    case runningIdentityMismatch
    case shellDidNotStart
    case terminationTimedOut
    case unexpectedRunningApplication
}

private enum ShellPolicy {
    static let bundleIdentifier =
        "com.firaskafri.homeward.testshell"
    static let launchTimeout: TimeInterval = 20
    static let navigationTimeout: TimeInterval = 8
    static let terminationTimeout: TimeInterval = 15
    static let pollInterval: TimeInterval = 0.05
}
