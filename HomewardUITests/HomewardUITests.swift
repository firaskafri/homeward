import AppKit
import Darwin
import XCTest

// 1 - Name: Homeward UI test file.
// 2 - Description: Verifies startup, exact-build reopening, recovery, readiness transitions, navigation, constrained Work Apps layout, and responsive schedule editing and copying with isolated scenario fixtures.
// 3 - Assumptions: UI scenarios use temporary storage, inert platform adapters, preview-only application identities, simulated external approvals, and the production window hierarchy.
// 4 - Expectations: Critical states, installation guidance, and split-view content remain visible without selecting, launching, or controlling any installed user application.

/// 1 - Name: Homeward UI test suite.
/// 2 - Description: Exercises exact-build launch/reopen, recovery, installation and approval transitions, long content, Work Apps viewport containment, and native schedule selection, time, overnight, copy, and save workflows.
/// 3 - Assumptions: Each test launches one named scenario whose files, preview catalog, external status transitions, and runtime adapters are isolated from user state.
/// 4 - Expectations: Native surfaces remain ordered and reachable, expose clear next actions and confirmations, and keep automated lifecycle control fixture-only.
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
    /// 2 - Description: Launches a completed setup and sends a bounded reopen request to its verified build-products path.
    /// 3 - Assumptions: The running process path and bundle identifier must match the UI target before Launch Services is invoked.
    /// 4 - Expectations: The window starts suppressed and only that exact test build can be reopened to Today.
    func testCompletedSetupReopensToday() throws {
        let app = try launch(.completedSetup)

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
                .waitForExistence(timeout: UITestPolicy.bootstrapRetryTimeout)
        )
    }

    /// 1 - Name: Configuration-recovery isolation.
    /// 2 - Description: Launches with corrupt settings through an isolated storage scenario.
    /// 3 - Assumptions: No configuration can be trusted and no catalog application can be controlled.
    /// 4 - Expectations: Recovery supersedes schedule UI and exposes only settings-recovery actions.
    func testConfigurationRecoverySupersedesScheduleState() throws {
        let app = try launch(.configurationRecovery)

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

    /// 1 - Name: Work Apps catalog layout.
    /// 2 - Description: Opens Work Apps with an isolated preview catalog and verifies its controls remain above the catalog rows.
    /// 3 - Assumptions: The test window uses the production split-view layout while catalog discovery returns only inert preview identities.
    /// 4 - Expectations: The picker, chooser, and first catalog row are visible in document order without content underlapping the title bar.
    func testWorkAppsCatalogStartsBelowPickerControls() throws {
        let app = try launch(.outsideApplications)
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

        let picker = app.descendants(matching: .any)["apps.view"]
        let chooser = app.buttons["Choose Application…"].firstMatch
        let toolbar = app.toolbars.firstMatch
        let firstCatalogRow = app.descendants(matching: .any)[
            "apps.row.com.homeward.preview.studio"
        ]
        XCTAssertTrue(
            picker.waitForExistence(timeout: UITestPolicy.navigationTimeout)
        )
        XCTAssertTrue(
            chooser.waitForExistence(timeout: UITestPolicy.navigationTimeout)
        )
        XCTAssertTrue(toolbar.exists)
        XCTAssertTrue(
            firstCatalogRow.waitForExistence(
                timeout: UITestPolicy.navigationTimeout
            )
        )
        XCTAssertGreaterThanOrEqual(
            chooser.frame.minY,
            toolbar.frame.maxY
        )
        XCTAssertGreaterThanOrEqual(
            firstCatalogRow.frame.minY,
            chooser.frame.maxY
        )
    }

    /// 1 - Name: Compact schedule selector reachability.
    /// 2 - Description: Shrinks first-launch setup to its minimum width and selects days at the start and end of the week.
    /// 3 - Assumptions: The empty isolated repository supplies the default workweek and the native window honors its SwiftUI minimum.
    /// 4 - Expectations: Every day remains reachable and selecting a day updates the single focused editor without horizontal scrolling.
    func testScheduleSelectorsRemainReachableAtMinimumWidth() throws {
        let app = try launch(.firstLaunch)
        let window = app.windows.firstMatch
        XCTAssertTrue(
            window.waitForExistence(timeout: UITestPolicy.launchTimeout)
        )
        resizeWindowToMinimum(window)
        XCTAssertLessThanOrEqual(window.frame.width, 700)

        let monday = scheduleElement(
            "schedule.day.monday.selector",
            in: app
        )
        let sunday = scheduleElement(
            "schedule.day.sunday.selector",
            in: app
        )
        XCTAssertTrue(
            monday.waitForExistence(timeout: UITestPolicy.navigationTimeout)
        )
        XCTAssertTrue(
            sunday.waitForExistence(timeout: UITestPolicy.navigationTimeout)
        )
        XCTAssertTrue(
            scheduleElement("schedule.day.monday.mode", in: app)
                .waitForExistence(timeout: UITestPolicy.navigationTimeout)
        )
        let tuesday = scheduleElement(
            "schedule.day.tuesday.selector",
            in: app
        )
        XCTAssertTrue(
            tuesday.waitForExistence(timeout: UITestPolicy.navigationTimeout)
        )
        tuesday.click()
        XCTAssertTrue(
            scheduleElement("schedule.day.tuesday.mode", in: app)
                .waitForExistence(timeout: UITestPolicy.navigationTimeout)
        )
        XCTAssertEqual(
            scheduleElement(
                "schedule.day.monday.selector",
                in: app
            ).value as? String,
            "Not selected"
        )

        XCTAssertTrue(sunday.isHittable)
        sunday.click()
        XCTAssertTrue(
            scheduleElement("schedule.day.sunday.mode", in: app)
                .waitForExistence(timeout: UITestPolicy.navigationTimeout)
        )
    }

    /// 1 - Name: Schedule mode and action states.
    /// 2 - Description: Reselects Monday's current mode, changes it to all-day availability, then resets the draft.
    /// 3 - Assumptions: First-launch setup has an unconfirmed default schedule and persistence has not started.
    /// 4 - Expectations: Reselecting the current mode is a no-op, while a real mode change enables reset and updates the day tile.
    func testScheduleModeSwitchingAndResetSaveStates() throws {
        let app = try launch(.firstLaunch)
        XCTAssertTrue(
            scheduleElement("schedule.day.monday.selector", in: app)
                .waitForExistence(timeout: UITestPolicy.launchTimeout)
        )
        let reset = app.buttons["schedule.reset"]
        let save = app.buttons["schedule.save"]
        XCTAssertFalse(reset.isEnabled)
        XCTAssertTrue(save.isEnabled)
        XCTAssertEqual(save.label, "Save & Continue")
        XCTAssertTrue(
            scheduleElement("schedule.day.monday.start", in: app).exists
        )

        let scheduledHours = app.radioButtons["Scheduled hours"].firstMatch
        XCTAssertTrue(scheduledHours.exists)
        scheduledHours.click()
        XCTAssertFalse(reset.isEnabled)

        let availableAllDay = app.radioButtons["Available all day"].firstMatch
        XCTAssertTrue(
            availableAllDay.waitForExistence(
                timeout: UITestPolicy.navigationTimeout
            )
        )
        XCTAssertTrue(availableAllDay.isHittable)
        availableAllDay.click()

        XCTAssertTrue(reset.isEnabled)
        XCTAssertTrue(
            scheduleElement(
                "schedule.day.monday.selector",
                in: app
            ).label.contains("Available all day")
        )
        reset.click()
        XCTAssertFalse(reset.isEnabled)
        XCTAssertTrue(
            scheduleElement(
                "schedule.day.monday.selector",
                in: app
            ).label.contains("9:00")
        )
    }

    /// 1 - Name: Focused schedule time picker.
    /// 2 - Description: Opens the redesigned start-time control from Monday's focused editor.
    /// 3 - Assumptions: The default workweek selects Monday and exposes its scheduled-hours controls.
    /// 4 - Expectations: Time editing opens a dedicated hour-and-minute popover instead of inline steppers.
    func testScheduleTimePickerUsesFocusedPopover() throws {
        let app = try launch(.firstLaunch)
        let startTime = scheduleElement(
            "schedule.day.monday.start",
            in: app
        )
        XCTAssertTrue(
            startTime.waitForExistence(timeout: UITestPolicy.launchTimeout)
        )
        scrollToVisible(startTime, in: app.scrollViews.firstMatch)
        XCTAssertTrue(startTime.isHittable)

        startTime.click()

        XCTAssertTrue(
            app.staticTexts["Uses your Mac’s time format"]
                .waitForExistence(timeout: UITestPolicy.navigationTimeout)
        )
        XCTAssertTrue(app.buttons["Done"].exists)
    }

    /// 1 - Name: Schedule copy workflow.
    /// 2 - Description: Applies Monday's default scheduled rule first to matching weekdays and then to both weekend days.
    /// 3 - Assumptions: The first-launch schedule starts with Monday scheduled and the weekend closed.
    /// 4 - Expectations: A no-op copy stays clean while a changed copy updates both weekend tiles and enables reset.
    func testScheduleCopiesSelectedDayToWeekend() throws {
        let app = try launch(.firstLaunch)
        let copyMenu = app.menuButtons["schedule.copy.destination"]
        XCTAssertTrue(
            copyMenu.waitForExistence(timeout: UITestPolicy.launchTimeout)
        )
        copyMenu.click()

        let weekdays = app.menuItems["Weekdays"]
        XCTAssertTrue(
            weekdays.waitForExistence(timeout: UITestPolicy.navigationTimeout)
        )
        weekdays.click()
        XCTAssertFalse(app.buttons["schedule.reset"].isEnabled)

        copyMenu.click()
        let weekend = app.menuItems["Weekend"]
        XCTAssertTrue(
            weekend.waitForExistence(timeout: UITestPolicy.navigationTimeout)
        )
        weekend.click()

        XCTAssertTrue(app.buttons["schedule.reset"].isEnabled)
        XCTAssertTrue(
            scheduleElement(
                "schedule.day.saturday.selector",
                in: app
            ).label.contains("9:00")
        )
        XCTAssertTrue(
            scheduleElement(
                "schedule.day.sunday.selector",
                in: app
            ).label.contains("9:00")
        )
    }

    /// 1 - Name: Overnight destination label.
    /// 2 - Description: Enables Monday overnight hours and inspects its destination-day control.
    /// 3 - Assumptions: Changing the native switch updates only the in-memory draft.
    /// 4 - Expectations: Monday names Tuesday and its day tile summary updates when enabled.
    func testScheduleOvernightControlNamesDestinationDay() throws {
        let app = try launch(.firstLaunch)
        XCTAssertTrue(
            scheduleElement("schedule.day.monday.selector", in: app)
                .waitForExistence(timeout: UITestPolicy.launchTimeout)
        )
        let mondayOvernight = scheduleElement(
            "schedule.day.monday.overnight",
            in: app
        )
        XCTAssertTrue(
            mondayOvernight.waitForExistence(
                timeout: UITestPolicy.navigationTimeout
            )
        )
        XCTAssertEqual(mondayOvernight.label, "Ends Tuesday")
        scrollToVisible(mondayOvernight, in: app.scrollViews.firstMatch)
        XCTAssertTrue(mondayOvernight.isHittable)
        mondayOvernight.click()
        let mondaySummary = scheduleElement(
            "schedule.day.monday.selector",
            in: app
        )
        let updatedSummary = expectation(
            for: NSPredicate(format: "label CONTAINS %@", "Tuesday"),
            evaluatedWith: mondaySummary
        )
        wait(for: [updatedSummary], timeout: UITestPolicy.navigationTimeout)
    }

    /// 1 - Name: Onboarding schedule save progression.
    /// 2 - Description: Saves the unchanged default schedule through the editor-owned primary onboarding action.
    /// 3 - Assumptions: The first-launch schedule is valid but still requires explicit confirmation.
    /// 4 - Expectations: Save & Continue persists confirmation and advances directly to the Work Apps step with no outer Continue action.
    func testOnboardingScheduleSaveContinuesToWorkApps() throws {
        let app = try launch(.firstLaunch)
        XCTAssertTrue(
            scheduleElement("schedule.day.monday.selector", in: app)
                .waitForExistence(timeout: UITestPolicy.launchTimeout)
        )
        let save = app.buttons["schedule.save"]
        XCTAssertTrue(
            save.waitForExistence(timeout: UITestPolicy.launchTimeout)
        )
        XCTAssertEqual(save.label, "Save & Continue")
        XCTAssertFalse(app.buttons["Continue"].exists)

        save.click()

        XCTAssertTrue(
            app.descendants(matching: .any)["onboarding.step.2"]
                .waitForExistence(timeout: UITestPolicy.launchTimeout)
        )
        XCTAssertTrue(app.staticTexts["Choose your work apps"].exists)
    }

    /// 1 - Name: Start-at-Login approval guidance.
    /// 2 - Description: Opens Step 4 while Start at Login requires approval.
    /// 3 - Assumptions: The isolated Login Items adapter remains read-only and never opens System Settings.
    /// 4 - Expectations: Step 4 provides both the system-settings route and an explicit status refresh.
    func testStepFourExplainsLoginApproval() throws {
        let app = try launch(.loginApproval)
        XCTAssertTrue(
            app.descendants(matching: .any)["onboarding.step.4"]
                .waitForExistence(timeout: UITestPolicy.launchTimeout)
        )
        XCTAssertTrue(app.staticTexts["Approval required"].exists)
        XCTAssertTrue(app.buttons["startAtLogin.openSettings"].exists)
        XCTAssertTrue(app.buttons["startAtLogin.checkAgain"].exists)
    }

    /// 1 - Name: Start-at-Login enabled confirmation.
    /// 2 - Description: Opens Step 4 after the platform reports that Start at Login is enabled.
    /// 3 - Assumptions: The isolated Login Items adapter starts enabled without changing external system state.
    /// 4 - Expectations: Step 4 shows a concise success state and explains its effect without redundant actions.
    func testStepFourConfirmsLoginIsEnabled() throws {
        let app = try launch(.loginEnabled)
        XCTAssertTrue(
            app.descendants(matching: .any)["onboarding.step.4"]
                .waitForExistence(timeout: UITestPolicy.launchTimeout)
        )
        XCTAssertTrue(app.staticTexts["On"].exists)
        XCTAssertTrue(
            app.staticTexts[
                "Homeward starts automatically when you log in."
            ].exists
        )
        XCTAssertFalse(app.buttons["startAtLogin.checkAgain"].exists)
    }

    /// 1 - Name: Moved-application restart guidance.
    /// 2 - Description: Opens Step 4 after the isolated Homeward bundle has moved into Applications while still running.
    /// 3 - Assumptions: The fixture reports the moved bundle without launching, quitting, or revealing any real application.
    /// 4 - Expectations: Step 4 confirms the move, explains why restart is required, and offers a focused completion action.
    func testStepFourExplainsRestartAfterMove() throws {
        let app = try launch(.movedToApplications)
        XCTAssertTrue(
            app.descendants(matching: .any)["onboarding.step.4"]
                .waitForExistence(timeout: UITestPolicy.launchTimeout)
        )

        XCTAssertTrue(app.staticTexts["Restart required"].exists)
        XCTAssertTrue(
            app.staticTexts[
                "Homeward is in Applications. Quit and reopen it before enabling Start at Login."
            ].exists
        )
        XCTAssertTrue(app.buttons["startAtLogin.showInFinder"].exists)
        XCTAssertTrue(app.buttons["startAtLogin.quit"].exists)
        XCTAssertFalse(app.staticTexts["Move to Applications"].exists)
    }

    private func launch(
        _ scenario: IsolatedApplicationFixture.Scenario
    ) throws -> XCUIApplication {
        let fixture = try IsolatedApplicationFixture(
            scenario: scenario,
            bundle: Bundle(for: Self.self)
        )
        self.fixture = fixture
        return try fixture.launch()
    }

    private func reopenHomeward(_ app: XCUIApplication) throws {
        XCTAssertTrue(
            app.menuBars.statusItems.firstMatch
                .waitForExistence(timeout: UITestPolicy.launchTimeout)
        )
        guard let fixture else {
            throw FixtureError.missingFixture
        }
        try fixture.reopen(app)
    }

    private func scheduleElement(
        _ identifier: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func resizeWindowToMinimum(_ window: XCUIElement) {
        let origin = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0, dy: 0)
        )
        let resizeHandle = origin.withOffset(
            CGVector(
                dx: window.frame.width - 2,
                dy: window.frame.height - 2
            )
        )
        let target = origin.withOffset(CGVector(dx: 500, dy: 400))
        resizeHandle.press(
            forDuration: 0.1,
            thenDragTo: target,
            withVelocity: .slow,
            thenHoldForDuration: 0.1
        )
    }

    private func scrollToVisible(
        _ element: XCUIElement,
        in scrollView: XCUIElement
    ) {
        for _ in 0..<UITestPolicy.maximumScrollAttempts
        where !element.isHittable {
            scrollView.swipeUp()
        }
    }

}

/// 1 - Name: Isolated UI application fixture.
/// 2 - Description: Maps named UI scenarios to temporary repository files and inert runtime adapters.
/// 3 - Assumptions: Bundled JSON resources contain preview-only identities and the application enforces UI-test isolation.
/// 4 - Expectations: Every launch receives unique storage and one scenario value; process path and identity are verified before termination.
@MainActor
private final class IsolatedApplicationFixture {
    enum Scenario {
        case firstLaunch
        case completedSetup
        case delayedStartupRetry
        case configurationRecovery
        case loginApproval
        case loginEnabled
        case movedToApplications
        case notesRecovery
        case outsideApplications
        case longContent

        var configurationResource: String? {
            switch self {
            case .firstLaunch, .delayedStartupRetry, .loginApproval,
                 .loginEnabled, .movedToApplications:
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
            case .loginApproval:
                "loginApproval"
            case .loginEnabled:
                "loginEnabled"
            case .movedToApplications:
                "movedToApplications"
            case .outsideApplications:
                "outsideApplications"
            default:
                "standard"
            }
        }

        var initialOnboardingStep: Int? {
            switch self {
            case .firstLaunch, .delayedStartupRetry:
                0
            case .loginApproval, .loginEnabled, .movedToApplications:
                3
            default:
                nil
            }
        }
    }

    private let scenario: Scenario
    private let directory: URL
    private let applicationURL: URL
    private let applicationBundleIdentifier: String
    private var application: XCUIApplication?

    init(scenario: Scenario, bundle: Bundle) throws {
        self.scenario = scenario
        let application = try Self.builtApplication(testBundle: bundle)
        applicationURL = application.url
        applicationBundleIdentifier = application.bundleIdentifier
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

    func launch() throws -> XCUIApplication {
        try terminateExistingTestApplications()
        let app = XCUIApplication()
        if let initialOnboardingStep = scenario.initialOnboardingStep {
            app.launchArguments += [
                "-\(UITestPolicy.onboardingStepPreference)",
                "\(initialOnboardingStep)",
            ]
        }
        app.launchArguments += [
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US",
            "-ApplePersistenceIgnoreState",
            "YES",
        ]
        app.launchEnvironment["HOMEWARD_STORAGE_DIRECTORY"] = directory.path
        app.launchEnvironment[UITestPolicy.runtimeIsolationEnvironment] = "1"
        app.launchEnvironment[UITestPolicy.scenarioEnvironment] =
            scenario.runtimeValue
        app.launch()
        application = app
        return app
    }

    private func terminateExistingTestApplications() throws {
        let applications = NSRunningApplication.runningApplications(
            withBundleIdentifier: applicationBundleIdentifier
        ).filter {
            $0.bundleURL?.resolvingSymlinksInPath().standardizedFileURL
                == applicationURL
        }
        for application in applications {
            try terminateTestApplication(application)
        }
    }

    func reopen(_ app: XCUIApplication) throws {
        guard app.state == .runningBackground
                || app.state == .runningForeground,
              expectedRunningApplication() != nil else {
            throw FixtureError.runningApplicationIdentityMismatch
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", applicationURL.path]
        try process.run()
        let deadline = ProcessInfo.processInfo.systemUptime
            + UITestPolicy.processTerminationTimeout
        while process.isRunning,
              ProcessInfo.processInfo.systemUptime < deadline {
            Thread.sleep(forTimeInterval: UITestPolicy.pollInterval)
        }
        guard !process.isRunning else {
            process.terminate()
            throw FixtureError.reopenTimedOut
        }
        guard process.terminationStatus == 0 else {
            throw FixtureError.reopenFailed(process.terminationStatus)
        }
    }

    func remove() throws {
        if let application,
           application.state == .runningBackground
            || application.state == .runningForeground {
            guard expectedRunningApplication() != nil else {
                throw FixtureError.runningApplicationIdentityMismatch
            }
            application.terminate()
            let deadline = ProcessInfo.processInfo.systemUptime
                + UITestPolicy.testApplicationTerminationTimeout
            while application.state != .notRunning,
                  ProcessInfo.processInfo.systemUptime < deadline {
                Thread.sleep(forTimeInterval: UITestPolicy.pollInterval)
            }
            guard application.state == .notRunning else {
                throw FixtureError.terminationTimedOut
            }
        }
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    private func expectedRunningApplication() -> NSRunningApplication? {
        let matches = NSRunningApplication.runningApplications(
            withBundleIdentifier: applicationBundleIdentifier
        ).filter {
            $0.bundleURL?.resolvingSymlinksInPath().standardizedFileURL
                == applicationURL
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private func terminateTestApplication(
        _ application: NSRunningApplication
    ) throws {
        let processIdentifier = application.processIdentifier
        _ = application.terminate()
        guard waitForProcessExit(
            processIdentifier,
            timeout: UITestPolicy.testApplicationTerminationTimeout
        ) else {
            throw FixtureError.terminationTimedOut
        }
    }

    private func waitForProcessExit(
        _ processIdentifier: pid_t,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while processIsRunning(processIdentifier),
              ProcessInfo.processInfo.systemUptime < deadline {
            Thread.sleep(forTimeInterval: UITestPolicy.pollInterval)
        }
        return !processIsRunning(processIdentifier)
    }

    private func processIsRunning(_ processIdentifier: pid_t) -> Bool {
        errno = 0
        return Darwin.kill(processIdentifier, 0) == 0 || errno != ESRCH
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

    private static func builtApplication(
        testBundle: Bundle
    ) throws -> (url: URL, bundleIdentifier: String) {
        let buildProductsURL = try BuiltApplicationLocator.productsDirectory(
            testBundle: testBundle
        )
        let unresolvedCandidate = buildProductsURL
            .appendingPathComponent("Homeward.app", isDirectory: true)
        let candidate = unresolvedCandidate
            .resolvingSymlinksInPath().standardizedFileURL
        let isSymbolicLink = (
            try? unresolvedCandidate.resourceValues(
                forKeys: [.isSymbolicLinkKey]
            ).isSymbolicLink
        ) ?? false
        guard !isSymbolicLink,
              candidate.deletingLastPathComponent() == buildProductsURL,
              FileManager.default.fileExists(atPath: candidate.path),
              let bundleIdentifier = Bundle(url: candidate)?.bundleIdentifier,
              UITestPolicy.isAllowedApplicationBundleIdentifier(
                bundleIdentifier
              ) else {
            throw FixtureError.builtApplicationIdentityMismatch(candidate.path)
        }
        return (candidate, bundleIdentifier)
    }
}

private enum FixtureError: Error {
    case builtApplicationIdentityMismatch(String)
    case missingFixture
    case missingResource(String)
    case reopenFailed(Int32)
    case reopenTimedOut
    case runningApplicationIdentityMismatch
    case terminationTimedOut
}

private enum UITestPolicy {
    static let applicationBundleIdentifier = "com.firaskafri.homeward"
    static let bootstrapRetryTimeout: TimeInterval = 30
    static let launchTimeout: TimeInterval = 15
    static let navigationTimeout: TimeInterval = 5
    static let maximumScrollAttempts = 5
    static let onboardingStepPreference = "onboardingStep"
    static let runtimeIsolationEnvironment = "HOMEWARD_UI_TESTING"
    static let scenarioEnvironment = "HOMEWARD_UI_TEST_SCENARIO"
    static let processTerminationTimeout: TimeInterval = 5
    static let testApplicationTerminationTimeout: TimeInterval = 15
    static let pollInterval: TimeInterval = 0.05

    static func isAllowedApplicationBundleIdentifier(
        _ bundleIdentifier: String
    ) -> Bool {
        bundleIdentifier == applicationBundleIdentifier
            || bundleIdentifier.hasPrefix(
                "\(applicationBundleIdentifier).uitest."
            )
    }
}
