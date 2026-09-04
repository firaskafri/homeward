import AppKit
import XCTest
@testable import Homeward

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
        let fixtureURL = try fixtureURL()
        let expectation = expectation(description: "Fixture launch observed")
        let observer = FixtureLaunchObserver(
            expectation: expectation,
            expectedIdentity: FixturePolicy.identity(at: fixtureURL)
        )
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            observer,
            selector: #selector(FixtureLaunchObserver.applicationDidLaunch(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: NSWorkspace.shared
        )
        defer { center.removeObserver(observer) }
        let startedAt = Date()

        let application = try await launchFixture(
            mode: .immediate,
            fixtureURL: fixtureURL
        )
        addTeardownBlock { @MainActor in
            try await self.terminateFixtureIfNeeded(
                application,
                fixtureURL: fixtureURL
            )
        }
        await fulfillment(
            of: [expectation],
            timeout: FixturePolicy.launchObservationTimeout
        )

        XCTAssertEqual(observer.processIdentifier, application.processIdentifier)
        let observedAt = try XCTUnwrap(observer.observedAt)
        XCTAssertLessThan(observedAt.timeIntervalSince(startedAt), 2)
    }

    /// 1 - Name: Normal termination fixture.
    /// 2 - Description: Launches the immediate fixture and requests ordinary termination.
    /// 3 - Assumptions: The fixture delegate returns terminate-now.
    /// 4 - Expectations: The fixture exits within two seconds without a force request.
    func testNormalTerminationFixture() async throws {
        let fixtureURL = try fixtureURL()
        let application = try await launchFixture(
            mode: .immediate,
            fixtureURL: fixtureURL
        )
        addTeardownBlock { @MainActor in
            try await self.terminateFixtureIfNeeded(
                application,
                fixtureURL: fixtureURL
            )
        }

        XCTAssertTrue(application.terminate())
        let terminated = await waitUntilTerminated(
            application,
            timeout: FixturePolicy.terminationTimeout
        )
        XCTAssertTrue(terminated)
    }

    /// 1 - Name: Delayed normal termination fixture.
    /// 2 - Description: Confirms an accepted normal-quit request can remain pending before observed exit.
    /// 3 - Assumptions: The fixture replies after the configured short delay.
    /// 4 - Expectations: It remains alive briefly and then exits without force termination.
    func testDelayedTerminationFixture() async throws {
        let fixtureURL = try fixtureURL()
        let application = try await launchFixture(
            mode: .delayed,
            delay: FixturePolicy.delayedTermination,
            fixtureURL: fixtureURL
        )
        addTeardownBlock { @MainActor in
            try await self.terminateFixtureIfNeeded(
                application,
                fixtureURL: fixtureURL
            )
        }

        XCTAssertTrue(application.terminate())
        try await Task.sleep(
            for: .seconds(FixturePolicy.preDelayObservation)
        )
        XCTAssertFalse(application.isTerminated)
        let terminated = await waitUntilTerminated(
            application,
            timeout: FixturePolicy.terminationTimeout
        )
        XCTAssertTrue(terminated)
    }

    /// 1 - Name: Refused normal termination and explicit force.
    /// 2 - Description: Launches the refusing fixture, confirms normal quit does not end it, then force-terminates it.
    /// 3 - Assumptions: The test validates the exact fixture path and bundle identifier before the destructive request.
    /// 4 - Expectations: Normal termination leaves it running and force termination ends it within two seconds.
    func testRefusedTerminationFixture() async throws {
        let fixtureURL = try fixtureURL()
        let application = try await launchFixture(
            mode: .refuse,
            fixtureURL: fixtureURL
        )
        addTeardownBlock { @MainActor in
            try await self.terminateFixtureIfNeeded(
                application,
                fixtureURL: fixtureURL
            )
        }

        _ = application.terminate()
        try await Task.sleep(
            for: .seconds(FixturePolicy.delayedTermination)
        )
        XCTAssertFalse(application.isTerminated)
        XCTAssertTrue(application.forceTerminate())
        let terminated = await waitUntilTerminated(
            application,
            timeout: FixturePolicy.terminationTimeout
        )
        XCTAssertTrue(terminated)
    }

    private func launchFixture(
        mode: FixturePolicy.Mode,
        delay: TimeInterval? = nil,
        fixtureURL: URL? = nil
    ) async throws -> NSRunningApplication {
        let url: URL
        if let fixtureURL {
            url = fixtureURL
        } else {
            url = try self.fixtureURL()
        }
        try await terminateExistingFixtures(at: url)
        let fixtureIdentity = FixturePolicy.identity(at: url)
        guard fixtureIdentity.matches(
            bundleIdentifier: Bundle(url: url)?.bundleIdentifier,
            bundleURL: url
        ) else {
            throw FixtureError.invalidFixtureIdentity(url)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        var environment = ["HOMEWARD_FIXTURE_MODE": mode.rawValue]
        if let delay {
            environment["HOMEWARD_FIXTURE_DELAY"] = String(delay)
        }
        configuration.environment = environment
        configuration.activates = false
        let application = try await NSWorkspace.shared.openApplication(
            at: url,
            configuration: configuration
        )
        guard fixtureIdentity.matches(
            bundleIdentifier: application.bundleIdentifier,
            bundleURL: application.bundleURL
        ) else {
            throw FixtureError.invalidFixtureIdentity(url)
        }
        return application
    }

    private func terminateExistingFixtures(at fixtureURL: URL) async throws {
        let fixtureIdentity = FixturePolicy.identity(at: fixtureURL)
        for application in NSRunningApplication.runningApplications(
            withBundleIdentifier: fixtureIdentity.bundleIdentifier
        ) where fixtureIdentity.matches(
            bundleIdentifier: application.bundleIdentifier,
            bundleURL: application.bundleURL
        ) {
            _ = application.forceTerminate()
            guard await waitUntilTerminated(
                application,
                timeout: FixturePolicy.terminationTimeout
            ) else {
                throw FixtureError.terminationTimedOut(fixtureURL)
            }
        }
    }

    private func fixtureURL() throws -> URL {
        var productsURL = Bundle(for: Self.self).bundleURL
        for _ in 0..<FixturePolicy.productsAncestorDepth {
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
            do {
                try await Task.sleep(
                    for: .seconds(FixturePolicy.pollInterval)
                )
            } catch {
                return application.isTerminated
            }
        }
        return application.isTerminated
    }

    private func terminateFixtureIfNeeded(
        _ application: NSRunningApplication,
        fixtureURL: URL
    ) async throws {
        guard FixturePolicy.identity(at: fixtureURL).matches(
            bundleIdentifier: application.bundleIdentifier,
            bundleURL: application.bundleURL
        ) else {
            throw FixtureError.invalidFixtureIdentity(fixtureURL)
        }
        guard !application.isTerminated else {
            return
        }
        _ = application.forceTerminate()
        guard await waitUntilTerminated(
            application,
            timeout: FixturePolicy.terminationTimeout
        ) else {
            throw FixtureError.terminationTimedOut(fixtureURL)
        }
    }
}

/// 1 - Name: Fixture launch observer.
/// 2 - Description: Bridges the NSWorkspace Objective-C notification into deterministic test state.
/// 3 - Assumptions: Selector callbacks are delivered on the main thread for the workspace main notification center.
/// 4 - Expectations: Only the dedicated fixture fulfills the expectation.
@MainActor
private final class FixtureLaunchObserver: NSObject {
    private let expectation: XCTestExpectation
    private let expectedIdentity: ControlledApplicationIdentity
    private(set) var processIdentifier: Int32?
    private(set) var observedAt: Date?

    init(
        expectation: XCTestExpectation,
        expectedIdentity: ControlledApplicationIdentity
    ) {
        self.expectation = expectation
        self.expectedIdentity = expectedIdentity
    }

    @objc
    func applicationDidLaunch(_ notification: Notification) {
        guard let application = notification.userInfo?[
            NSWorkspace.applicationUserInfoKey
        ] as? NSRunningApplication,
              expectedIdentity.matches(
                  bundleIdentifier: application.bundleIdentifier,
                  bundleURL: application.bundleURL
              ),
              processIdentifier == nil
        else {
            return
        }
        processIdentifier = application.processIdentifier
        observedAt = Date()
        expectation.fulfill()
    }
}

private enum FixtureError: Error {
    case fixtureNotBuilt(URL)
    case invalidFixtureIdentity(URL)
    case terminationTimedOut(URL)
}

private enum FixturePolicy {
    static let productsAncestorDepth = 4
    static let pollInterval: TimeInterval = 0.05
    static let delayedTermination: TimeInterval = 0.3
    static let preDelayObservation: TimeInterval = 0.1
    static let launchObservationTimeout: TimeInterval = 2
    static let terminationTimeout: TimeInterval = 2

    @MainActor
    static func identity(at fixtureURL: URL) -> ControlledApplicationIdentity {
        RunningApplicationControlPolicy.fixtureIdentity(
            productsDirectoryURL: fixtureURL.deletingLastPathComponent()
        )
    }

    enum Mode: String {
        case immediate
        case delayed
        case refuse
    }
}
