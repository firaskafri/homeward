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
    private var storageDirectory: URL?

    override func tearDownWithError() throws {
        if let storageDirectory {
            try? FileManager.default.removeItem(at: storageDirectory)
        }
        storageDirectory = nil
    }

    /// 1 - Name: First-launch onboarding.
    /// 2 - Description: Launches Homeward and verifies setup is visible without relying on its menu-bar item.
    /// 3 - Assumptions: The isolated storage directory has no completed configuration.
    /// 4 - Expectations: Homeward exposes its status item and opens the first onboarding step.
    func testFirstLaunchShowsOnboarding() throws {
        let app = launchIsolatedApp()
        defer { app.terminate() }

        let statusItem = app.menuBars.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
        XCTAssertTrue(app.windows["Homeward"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.otherElements["onboarding.step.1"].waitForExistence(timeout: 5)
        )
    }

    private func launchIsolatedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.terminate()
        let directory = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("HomewardUITests-\(UUID().uuidString)")
        storageDirectory = directory
        app.launchEnvironment["HOMEWARD_STORAGE_DIRECTORY"] = directory.path
        app.launch()
        return app
    }
}
