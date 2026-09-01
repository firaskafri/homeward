import XCTest

// 1 - Name: Homeward UI test file.
// 2 - Description: Verifies the first-launch setup surface is reachable without interacting with real work applications.
// 3 - Assumptions: UI tests use a clean test container and never enable enforcement.
// 4 - Expectations: The app exposes its onboarding promise and primary controls to accessibility automation.

/// 1 - Name: Homeward UI test suite.
/// 2 - Description: Exercises safe first-launch navigation through the application UI.
/// 3 - Assumptions: The test runner starts with no completed Homeward configuration.
/// 4 - Expectations: Onboarding opens as an accessible native window.
@MainActor
final class HomewardUITests: XCTestCase {
    /// 1 - Name: First-launch onboarding.
    /// 2 - Description: Launches Homeward in an isolated UI-test container and reaches the first onboarding step.
    /// 3 - Assumptions: UI-test mode presents the same onboarding content without changing production launch behavior.
    /// 4 - Expectations: The schedule save and Continue actions are accessibility-visible.
    func testFirstLaunchShowsOnboarding() throws {
        let app = launchIsolatedApp()

        XCTAssertTrue(app.buttons["Save Schedule"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Continue"].exists)
    }

    /// 1 - Name: Schedule controls accessibility.
    /// 2 - Description: Verifies each weekday exposes an independently accessible mode control.
    /// 3 - Assumptions: The default Monday-through-Friday schedule is loaded from HomewardCore.
    /// 4 - Expectations: Seven mode controls and the copy action are discoverable.
    func testScheduleControlsAreAccessible() {
        let app = launchIsolatedApp()

        XCTAssertTrue(app.buttons["Save Schedule"].waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(app.popUpButtons.count, 7)
        XCTAssertTrue(app.menuButtons["Copy to…"].exists)
    }

    private func launchIsolatedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.terminate()
        app.launchEnvironment["HOMEWARD_STORAGE_DIRECTORY"] = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("HomewardUITests-\(UUID().uuidString)")
            .path
        app.launchEnvironment["HOMEWARD_UI_TEST_MODE"] = "1"
        app.launch()
        return app
    }
}
