import AppKit
import XCTest

// 1 - Name: Homeward Release lifecycle E2E file.
// 2 - Description: Exercises the exact Release Homeward app through real workspace notifications and fixture-only process control.
// 3 - Assumptions: Tests run serially in an unlocked active session with no installed Homeward or stale fixture process running.
// 4 - Expectations: Gentle attention, Firm, Stop, and process-session safety work through the production enforcement path without controlling user applications.

/// 1 - Name: Homeward Release lifecycle E2E suite.
/// 2 - Description: Launches the built Release app and adjacent refusing fixture to verify Gentle attention, full Firm grace, Stop, and relaunch isolation.
/// 3 - Assumptions: Homeward is configured from isolated storage and automated control policy permits only the exact adjacent fixture.
/// 4 - Expectations: Every destructive request is identity checked, Firm never shortens its grace period, and teardown leaves no controlled process.
@MainActor
final class ReleaseLifecycleE2ETests: XCTestCase {
    private var fixture: ReleaseE2EFixture?

    override func tearDownWithError() throws {
        try fixture?.remove()
        fixture = nil
    }

    /// 1 - Name: Refusing fixture readiness.
    /// 2 - Description: Verifies the Release-suite fixture receives its configured mode before Homeward can act on it.
    /// 3 - Assumptions: The dedicated fixture is launched from the exact adjacent products path and has completed startup.
    /// 4 - Expectations: The fixture refuses a direct normal quit request and remains alive.
    func testRefusingFixtureIsReadyBeforeEnforcement() async throws {
        let fixture = try makeFixture()
        let application = try await fixture.launchFixture()
        let processIdentifier = application.processIdentifier

        _ = application.terminate()
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(fixture.isRunning(
            processIdentifier: processIdentifier
        ))
    }

    /// 1 - Name: Gentle needs-attention actions.
    /// 2 - Description: Runs a refusing fixture under Gentle policy until the production attention delay expires.
    /// 3 - Assumptions: Gentle never force-terminates and the fixture remains the exact live process selected in policy.
    /// 4 - Expectations: Show App and Leave Open This Time are offered, and leaving open removes the row without terminating the fixture.
    func testGentleRefusalOffersSafeActions() async throws {
        let fixture = try makeFixture()
        let homeward = try await fixture.launchHomeward(closeMode: .gentle)
        let application = try await fixture.launchFixture()
        let processIdentifier = application.processIdentifier

        guard homeward.descendants(matching: .any)["closing.panel"]
            .waitForExistence(timeout: ReleaseE2EPolicy.launchTimeout) else {
            XCTFail("Gentle closing panel did not appear")
            return
        }
        guard homeward.buttons["Show Homeward Fixture"]
            .waitForExistence(timeout: ReleaseE2EPolicy.launchTimeout) else {
            XCTFail("Show App action did not appear")
            return
        }
        let leaveOpen = homeward.buttons["Leave Open This Time"]
        guard leaveOpen.exists else {
            XCTFail("Leave Open This Time action did not appear")
            return
        }
        leaveOpen.click()

        XCTAssertTrue(fixture.isRunning(
            processIdentifier: processIdentifier
        ))
        XCTAssertFalse(
            homeward.buttons["Leave Open This Time"].waitForExistence(
                timeout: 1
            )
        )
    }

    /// 1 - Name: Firm full grace.
    /// 2 - Description: Runs a refusing fixture through one complete Firm deadline.
    /// 3 - Assumptions: The visible countdown follows Homeward's normal-quit request and refusal prevents an ordinary exit.
    /// 4 - Expectations: The fixture remains alive for the full visible grace period before exact-session force termination.
    func testFirmHonorsFullGracePeriod() async throws {
        let fixture = try makeFixture()
        _ = try await fixture.launchHomeward(closeMode: .firm)
        let fixtureLaunchUptime = ProcessInfo.processInfo.systemUptime
        let first = try await fixture.launchFixture()
        let firstProcessIdentifier = first.processIdentifier
        XCTAssertTrue(fixture.waitUntilTerminated(
            processIdentifier: firstProcessIdentifier,
            timeout: ReleaseE2EPolicy.forceTerminationUpperBound
        ))
        XCTAssertGreaterThanOrEqual(
            ProcessInfo.processInfo.systemUptime - fixtureLaunchUptime,
            ReleaseE2EPolicy.firmGracePeriod
                - ReleaseE2EPolicy.graceLowerBoundTolerance
        )
    }

    /// 1 - Name: Blocked relaunch process isolation.
    /// 2 - Description: Launches the refusing fixture twice while the exact Release app enforces a blocked Gentle policy.
    /// 3 - Assumptions: Leave Open applies only to one process session and teardown can safely end that exact fixture.
    /// 4 - Expectations: The second process has a new identity and receives a fresh attention action.
    func testBlockedRelaunchUsesNewProcessSession() async throws {
        let fixture = try makeFixture()
        let homeward = try await fixture.launchHomeward(closeMode: .gentle)

        let first = try await fixture.launchFixture()
        let firstProcessIdentifier = first.processIdentifier
        let firstLeaveOpen = homeward.buttons["Leave Open This Time"]
        guard firstLeaveOpen.waitForExistence(
            timeout: ReleaseE2EPolicy.launchTimeout
        ) else {
            XCTFail("First Gentle attention action did not appear")
            return
        }
        firstLeaveOpen.click()
        try fixture.terminateControlledFixture()

        let second = try await fixture.launchFixture()
        XCTAssertNotEqual(
            second.processIdentifier,
            firstProcessIdentifier
        )
        XCTAssertTrue(
            homeward.buttons["Leave Open This Time"].waitForExistence(
                timeout: ReleaseE2EPolicy.launchTimeout
            )
        )
    }

    /// 1 - Name: Firm Stop safety.
    /// 2 - Description: Stops an active Firm countdown and observes the refusing fixture past its original deadline.
    /// 3 - Assumptions: Stop is available while the safety panel is visible and immediately cancels in-memory force escalation.
    /// 4 - Expectations: The fixture remains alive beyond the original 30-second deadline and is terminated only by identity-checked teardown.
    func testStopForceQuitCancelsOriginalDeadline() async throws {
        let fixture = try makeFixture()
        let homeward = try await fixture.launchHomeward(closeMode: .firm)
        let fixtureLaunchUptime = ProcessInfo.processInfo.systemUptime
        let application = try await fixture.launchFixture()
        let processIdentifier = application.processIdentifier
        let stop = homeward.buttons["closing.stopForce"]
        guard stop.waitForExistence(
            timeout: ReleaseE2EPolicy.launchTimeout
        ) else {
            XCTFail("Stop Force Quit was not available")
            return
        }
        stop.click()

        let paused = NSPredicate(format: "label CONTAINS[c] %@", "paused")
        let pausedState = homeward.staticTexts.matching(paused).firstMatch
        XCTAssertTrue(pausedState.waitForExistence(
            timeout: ReleaseE2EPolicy.launchTimeout
        ))
        fixture.waitUntilUptime(
            fixtureLaunchUptime
                + ReleaseE2EPolicy.firmGracePeriod
                + ReleaseE2EPolicy.graceLowerBoundTolerance
        )
        XCTAssertTrue(fixture.isRunning(
            processIdentifier: processIdentifier
        ))
    }

    private func makeFixture() throws -> ReleaseE2EFixture {
        let fixture = try ReleaseE2EFixture()
        self.fixture = fixture
        return fixture
    }
}
