import AppKit
import XCTest

// 1 - Name: macOS platform integration test file.
// 2 - Description: Exercises normal and forced termination only against the dedicated Homeward fixture application.
// 3 - Assumptions: The fixture target is built beside Homeward and uniquely identified by its test bundle identifier.
// 4 - Expectations: Public NSWorkspace and NSRunningApplication APIs provide the lifecycle behavior required by the MVP.

/// 1 - Name: macOS platform integration suite.
/// 2 - Description: Validates destructive lifecycle APIs behind a hard fixture-only path and bundle-identity check.
/// 3 - Assumptions: No real user application can satisfy both fixture checks.
/// 4 - Expectations: Immediate quit succeeds, refusal remains running, and explicit force terminates only the fixture.
@MainActor
final class PlatformIntegrationTests: XCTestCase {
    /// 1 - Name: Fixture launch observation latency.
    /// 2 - Description: Observes a fixture launch through the public NSWorkspace notification center.
    /// 3 - Assumptions: The local fixture starts under normal machine load and no previous fixture remains running.
    /// 4 - Expectations: The matching launch notification arrives within the PRD’s two-second request budget.
    func testFixtureLaunchObservationLatency() async throws {
        let expectation = expectation(description: "Fixture launch observed")
        let observer = FixtureLaunchObserver(expectation: expectation)
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            observer,
            selector: #selector(FixtureLaunchObserver.applicationDidLaunch(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: NSWorkspace.shared
        )
        defer { center.removeObserver(observer) }
        let startedAt = Date()

        let application = try await launchFixture(mode: "immediate")
        await fulfillment(of: [expectation], timeout: 2)

        XCTAssertEqual(observer.processIdentifier, application.processIdentifier)
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 2)
        _ = application.forceTerminate()
        _ = await waitUntilTerminated(application, timeout: 2)
    }

    /// 1 - Name: Normal termination fixture.
    /// 2 - Description: Launches the immediate fixture and requests ordinary termination.
    /// 3 - Assumptions: The fixture delegate returns terminate-now.
    /// 4 - Expectations: The fixture exits within two seconds without a force request.
    func testNormalTerminationFixture() async throws {
        let application = try await launchFixture(mode: "immediate")

        XCTAssertTrue(application.terminate())
        let terminated = await waitUntilTerminated(application, timeout: 2)
        XCTAssertTrue(terminated)
    }

    /// 1 - Name: Refused normal termination and explicit force.
    /// 2 - Description: Launches the refusing fixture, confirms normal quit does not end it, then force-terminates it.
    /// 3 - Assumptions: The test validates the exact fixture path and bundle identifier before the destructive request.
    /// 4 - Expectations: Normal termination leaves it running and force termination ends it within two seconds.
    func testRefusedTerminationFixture() async throws {
        let application = try await launchFixture(mode: "refuse")

        _ = application.terminate()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(application.isTerminated)
        XCTAssertTrue(application.forceTerminate())
        let terminated = await waitUntilTerminated(application, timeout: 2)
        XCTAssertTrue(terminated)
    }

    private func launchFixture(mode: String) async throws -> NSRunningApplication {
        let url = try fixtureURL()
        await terminateExistingFixtures(at: url)
        XCTAssertEqual(
            Bundle(url: url)?.bundleIdentifier,
            "com.firaskafri.homeward.fixture"
        )
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.environment = ["HOMEWARD_FIXTURE_MODE": mode]
        configuration.activates = false
        return try await NSWorkspace.shared.openApplication(
            at: url,
            configuration: configuration
        )
    }

    private func terminateExistingFixtures(at fixtureURL: URL) async {
        let expectedPath = fixtureURL.standardizedFileURL.path
        for application in NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.firaskafri.homeward.fixture"
        ) where application.bundleURL?.standardizedFileURL.path == expectedPath {
            _ = application.forceTerminate()
            _ = await waitUntilTerminated(application, timeout: 2)
        }
    }

    private func fixtureURL() throws -> URL {
        var productsURL = Bundle(for: Self.self).bundleURL
        for _ in 0..<4 {
            productsURL.deleteLastPathComponent()
        }
        let fixtureURL = productsURL.appendingPathComponent("HomewardFixture.app")
        guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
            throw FixtureError.fixtureNotBuilt(fixtureURL)
        }
        return fixtureURL
    }

    private func waitUntilTerminated(
        _ application: NSRunningApplication,
        timeout: TimeInterval
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if application.isTerminated {
                return true
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return application.isTerminated
    }
}

/// 1 - Name: Fixture launch observer.
/// 2 - Description: Bridges the NSWorkspace Objective-C notification into deterministic test state.
/// 3 - Assumptions: Selector callbacks are delivered on the main thread for the workspace main notification center.
/// 4 - Expectations: Only the dedicated fixture fulfills the expectation.
@MainActor
private final class FixtureLaunchObserver: NSObject {
    private let expectation: XCTestExpectation
    private(set) var processIdentifier: Int32?

    init(expectation: XCTestExpectation) {
        self.expectation = expectation
    }

    @objc
    func applicationDidLaunch(_ notification: Notification) {
        guard let application = notification.userInfo?[
            NSWorkspace.applicationUserInfoKey
        ] as? NSRunningApplication,
              application.bundleIdentifier == "com.firaskafri.homeward.fixture"
        else {
            return
        }
        processIdentifier = application.processIdentifier
        expectation.fulfill()
    }
}

private enum FixtureError: Error {
    case fixtureNotBuilt(URL)
}
