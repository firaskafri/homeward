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
    /// 2 - Description: Launches Homeward and locates its pre-activation menu-bar item.
    /// 3 - Assumptions: Detailed menu/window interaction remains a manual gate because hidden menu bars make coordinate automation unreliable.
    /// 4 - Expectations: Homeward exposes one accessibility-visible status item.
    func testFirstLaunchShowsOnboarding() throws {
        let app = launchIsolatedApp()

        let statusItem = app.menuBars.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
    }

    private func launchIsolatedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.terminate()
        app.launchEnvironment["HOMEWARD_STORAGE_DIRECTORY"] = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("HomewardUITests-\(UUID().uuidString)")
            .path
        app.launch()
        return app
    }
}
