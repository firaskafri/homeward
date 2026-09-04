import Foundation
import Testing
@testable import Homeward
import HomewardCore

// 1 - Name: Homeward application-model test file.
// 2 - Description: Verifies app-layer defaults, recovery, validation, and runtime safety policy exposed to the native UI.
// 3 - Assumptions: Tests use isolated repositories and never provide a running application termination target.
// 4 - Expectations: Initialization, persistence failures, and policy changes fail open without weakening safety actions.

/// 1 - Name: Homeward application-model suite.
/// 2 - Description: Covers app composition, storage recovery, and safety-action ordering outside the pure core package.
/// 3 - Assumptions: Repository creation does not write until an explicit save and fixtures are isolated.
/// 4 - Expectations: Startup and mutation failures remain recoverable while runtime force pauses apply immediately.
@Suite("Homeward application model")
@MainActor
struct AppModelTests {
    /// 1 - Name: Safe initialization defaults.
    /// 2 - Description: Creates the production model without starting platform observation.
    /// 3 - Assumptions: No persisted configuration is loaded until start is called.
    /// 4 - Expectations: Gentle mode and incomplete onboarding prevent termination.
    @Test
    func safeInitializationDefaults() throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let model = try AppModel(
            repository: HomewardRepository(directoryURL: fixture.directoryURL)
        )

        #expect(model.configuration.closeMode == .gentle)
        #expect(!model.configuration.completedOnboarding)
        #expect(model.closingRows.isEmpty)
    }

    /// 1 - Name: Protected application policy.
    /// 2 - Description: Confirms Homeward and critical system applications are always excluded.
    /// 3 - Assumptions: Protection is bundle-identifier based and has no user override.
    /// 4 - Expectations: Finder, System Settings, and Homeward are present in the denylist.
    @Test
    func protectedApplicationPolicy() {
        #expect(SelectedApplication.protectedBundleIdentifiers.contains("com.apple.finder"))
        #expect(SelectedApplication.protectedBundleIdentifiers.contains("com.apple.SystemSettings"))
        #expect(SelectedApplication.protectedBundleIdentifiers.contains("com.firaskafri.homeward"))
    }

    /// 1 - Name: Custom cutoff override pair.
    /// 2 - Description: Verifies the app model stores availability until cutoff and blocking afterward as one logical change.
    /// 3 - Assumptions: The selected cutoff is a valid future instant within the current local day.
    /// 4 - Expectations: The configuration contains one allow and one future block override.
    @Test
    func customCutoffOverridePair() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let calendar = Calendar.autoupdatingCurrent
        let now = try #require(calendar.date(
            from: DateComponents(
                year: 2026,
                month: 9,
                day: 7,
                hour: 12
            )
        ))
        let model = try AppModel(
            repository: HomewardRepository(
                directoryURL: fixture.directoryURL
            ),
            nowProvider: { now }
        )
        let cutoff = now.addingTimeInterval(30)

        await model.chooseCutoff(cutoff)

        let custom = model.configuration.overrides.filter {
            $0.kind == .customCutoff
        }
        #expect(custom.count == 2)
        #expect(Set(custom.map(\.effect)) == [.allow, .block])
    }

    /// 1 - Name: Continuous schedule early ending.
    /// 2 - Description: Ends work temporarily when every weekday is otherwise available all day.
    /// 3 - Assumptions: A continuously available schedule has no natural weekly boundary.
    /// 4 - Expectations: The temporary block ends at the next local day boundary, not distant future.
    @Test
    func continuousScheduleEndWorkExpiresAtNextDay() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let calendar = Calendar.autoupdatingCurrent
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 7,
            hour: 12
        )))
        let model = try AppModel(
            repository: HomewardRepository(directoryURL: fixture.directoryURL),
            nowProvider: { now }
        )
        let rules = Dictionary(
            uniqueKeysWithValues: Weekday.allCases.map {
                ($0, DayRule.availableAllDay)
            }
        )
        await model.setSchedule(try WeeklySchedule(rules: rules))

        await model.endWorkNow()

        let endWorkOverride = try #require(
            model.configuration.overrides.first(where: {
                $0.kind == .endWorkNow
            })
        )
        let expectedExpiry = ScheduleResolver().nextLocalDayBoundary(
            after: now,
            calendar: calendar
        )
        #expect(endWorkOverride.expiresAt == expectedExpiry)
    }

    /// 1 - Name: Stop Force Quit runtime latch.
    /// 2 - Description: Applies the safety action before relying on persistence.
    /// 3 - Assumptions: No running targets are required to create the blocked-interval pause.
    /// 4 - Expectations: Runtime policy and persisted configuration both report force escalation paused.
    @Test
    func stopForceQuitCreatesSafetyLatch() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let model = try AppModel(repository: HomewardRepository(
            directoryURL: fixture.directoryURL
        ))

        await model.stopForceQuit()

        #expect(model.forceEscalationPaused)
        #expect(model.configuration.overrides.contains {
            $0.kind == .forceEscalationPaused
        })
    }

    /// 1 - Name: Stop Force Quit precedes pending persistence.
    /// 2 - Description: Requests the safety latch while another configuration save is deliberately suspended.
    /// 3 - Assumptions: Runtime cancellation must not wait for unrelated disk activity.
    /// 4 - Expectations: Force escalation is paused before the pending save is released.
    @Test
    func stopForceQuitPrecedesPendingPersistence() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let saveGate = ConfigurationSaveGate()
        let model = try AppModel(
            repository: HomewardRepository(directoryURL: fixture.directoryURL),
            configurationSaver: { configuration in
                try await saveGate.save(configuration)
            }
        )
        let pendingSave = Task { @MainActor in
            await model.setWarning(.fifteenMinute, enabled: false)
        }
        await saveGate.waitUntilFirstSaveStarts()
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        let stopTask = Task { @MainActor in
            startedContinuation.yield()
            await model.stopForceQuit()
        }
        var startedIterator = started.makeAsyncIterator()
        _ = await startedIterator.next()
        await Task.yield()

        #expect(model.forceEscalationPaused)

        await saveGate.releaseFirstSave()
        await pendingSave.value
        await stopTask.value
    }

    /// 1 - Name: Concurrent warning updates.
    /// 2 - Description: Queues two field-level warning changes while the first save is suspended.
    /// 3 - Assumptions: Configuration writes are serialized and each mutation reads the latest committed state.
    /// 4 - Expectations: Both warning choices persist without a lost update.
    @Test
    func concurrentWarningUpdatesAreSerialized() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let saveGate = ConfigurationSaveGate()
        let model = try AppModel(
            repository: HomewardRepository(directoryURL: fixture.directoryURL),
            configurationSaver: { configuration in
                try await saveGate.save(configuration)
            }
        )
        let firstUpdate = Task { @MainActor in
            await model.setWarning(.fifteenMinute, enabled: false)
        }
        await saveGate.waitUntilFirstSaveStarts()
        let secondUpdate = Task { @MainActor in
            await model.setWarning(.fiveMinute, enabled: false)
        }

        await saveGate.releaseFirstSave()
        await firstUpdate.value
        await secondUpdate.value

        #expect(
            !model.configuration.warningPreferences
                .fifteenMinuteWarningEnabled
        )
        #expect(
            !model.configuration.warningPreferences
                .fiveMinuteWarningEnabled
        )
    }

    /// 1 - Name: Stop Force Quit survives save failure.
    /// 2 - Description: Forces pause persistence to fail after applying the in-memory safety latch.
    /// 3 - Assumptions: A regular file at the repository directory path deterministically prevents writes.
    /// 4 - Expectations: Runtime force escalation remains paused and the failure is recoverable in the session.
    @Test
    func stopForceQuitSurvivesSaveFailure() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        try Data().write(to: fixture.directoryURL)
        let model = try AppModel(repository: HomewardRepository(
            directoryURL: fixture.directoryURL
        ))

        await model.stopForceQuit()

        #expect(model.forceEscalationPaused)
        #expect(model.configuration.overrides.allSatisfy {
            $0.kind != .forceEscalationPaused
        })
        #expect(model.lastError != nil)
    }

    /// 1 - Name: Return to weekly schedule preserves force pause.
    /// 2 - Description: Removes today-only availability policy without bypassing an explicit Firm safety pause.
    /// 3 - Assumptions: Stop Force Quit and availability overrides have distinct purposes.
    /// 4 - Expectations: Only the force-pause override remains.
    @Test
    func returnToWeeklySchedulePreservesForcePause() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let model = try AppModel(repository: HomewardRepository(
            directoryURL: fixture.directoryURL
        ))
        await model.stopForceQuit()
        await model.createExtension(minutes: 10)

        await model.returnToWeeklySchedule()

        #expect(model.configuration.overrides.allSatisfy {
            $0.kind == .forceEscalationPaused
        })
    }

    /// 1 - Name: Protected app rejected at model boundary.
    /// 2 - Description: Attempts to add Finder without going through the picker.
    /// 3 - Assumptions: Persisted and programmatic inputs are untrusted.
    /// 4 - Expectations: Finder is not selected and an explanatory error is published.
    @Test
    func protectedAppRejectedAtModelBoundary() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let model = try AppModel(repository: HomewardRepository(
            directoryURL: fixture.directoryURL
        ))
        let finder = SelectedApplication(
            bundleIdentifier: "com.apple.finder",
            bundlePath: "/System/Library/CoreServices/Finder.app",
            displayName: "Finder"
        )

        await model.addApplication(finder)

        #expect(model.configuration.selectedApplications.isEmpty)
        #expect(model.lastError != nil)
    }

    /// 1 - Name: Invalid extension duration.
    /// 2 - Description: Attempts to create an extension outside the policy allowlist.
    /// 3 - Assumptions: Callers and notification actions are untrusted inputs despite fixed UI choices.
    /// 4 - Expectations: No override is saved and a validation error is published.
    @Test
    func invalidExtensionDurationIsRejected() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let model = try AppModel(repository: HomewardRepository(
            directoryURL: fixture.directoryURL
        ))

        await model.createExtension(minutes: 11)

        #expect(model.configuration.overrides.isEmpty)
        #expect(model.lastError == "Choose a supported extension duration.")
    }

    /// 1 - Name: Corrupt startup configuration recovery.
    /// 2 - Description: Starts the model with undecodable active configuration data.
    /// 3 - Assumptions: Unverified settings must never activate application enforcement.
    /// 4 - Expectations: Startup enters the recoverable unavailable state with no closing rows.
    @Test
    func corruptStartupConfigurationRequiresRecovery() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(
            at: fixture.directoryURL,
            withIntermediateDirectories: true
        )
        try Data("corrupt".utf8).write(
            to: fixture.directoryURL.appendingPathComponent("configuration.json")
        )
        let model = try AppModel(repository: HomewardRepository(
            directoryURL: fixture.directoryURL
        ))

        await model.start()

        #expect(model.health == .configurationUnavailable)
        #expect(model.closingRows.isEmpty)
        #expect(model.lastError != nil)
    }

    /// 1 - Name: Initial window launch policy.
    /// 2 - Description: Chooses visible startup for new or corrupt state and quiet startup after completed setup.
    /// 3 - Assumptions: The synchronous launch decision reads the same validated configuration format as the repository.
    /// 4 - Expectations: Missing and corrupt files present a window; a completed configuration suppresses it.
    @Test
    func initialWindowLaunchPolicy() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        #expect(HomewardRepository.shouldPresentMainWindow(
            directoryURL: fixture.directoryURL
        ))

        var configuration = try HomewardConfiguration.initial()
        configuration.onboardingScheduleConfirmed = true
        configuration.completedOnboarding = true
        _ = try await HomewardRepository(
            directoryURL: fixture.directoryURL
        ).saveConfiguration(configuration)
        #expect(!HomewardRepository.shouldPresentMainWindow(
            directoryURL: fixture.directoryURL
        ))

        try Data("corrupt".utf8).write(
            to: fixture.directoryURL.appendingPathComponent(
                "configuration.json"
            )
        )
        #expect(HomewardRepository.shouldPresentMainWindow(
            directoryURL: fixture.directoryURL
        ))
    }

    /// 1 - Name: Notification cutoff payload.
    /// 2 - Description: Round-trips the warning cutoff used to reject stale notification actions.
    /// 3 - Assumptions: User-notification payloads preserve numeric property-list values.
    /// 4 - Expectations: Valid payloads recover the cutoff; missing or nonfinite context is rejected.
    @Test
    func notificationCutoffPayloadRoundTrips() {
        let cutoff = Date(timeIntervalSince1970: 1_789_000_000.25)
        let payload = HomewardNotificationService.warningUserInfo(cutoff: cutoff)

        #expect(
            HomewardNotificationService.warningActionContext(from: payload)
                == WarningActionContext(cutoff: cutoff)
        )
        #expect(HomewardNotificationService.warningActionContext(from: [:]) == nil)
        #expect(HomewardNotificationService.warningActionContext(
            from: ["homeward-warning-cutoff": Double.infinity]
        ) == nil)
    }

    /// 1 - Name: Stale notification action.
    /// 2 - Description: Routes a closing action whose cutoff differs from the active work-window cutoff.
    /// 3 - Assumptions: The weekly schedule is available at the fixed Monday test time.
    /// 4 - Expectations: The stale action makes no availability-policy change.
    @Test
    func staleNotificationActionIsIgnored() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let calendar = Calendar.autoupdatingCurrent
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 7,
            hour: 16,
            minute: 50
        )))
        let currentCutoff = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 7,
            hour: 17
        )))
        let model = try AppModel(
            repository: HomewardRepository(directoryURL: fixture.directoryURL),
            nowProvider: { now }
        )

        await model.applyNotificationAction(
            HomewardNotificationService.startClosingAction,
            context: WarningActionContext(
                cutoff: currentCutoff.addingTimeInterval(60)
            )
        )

        #expect(model.configuration.overrides.isEmpty)
    }

    /// 1 - Name: Repository validates decoded configuration.
    /// 2 - Description: Writes a syntactically valid but protected selection directly to storage.
    /// 3 - Assumptions: Persisted configuration is untrusted and decoding enforces domain invariants.
    /// 4 - Expectations: Repository load rejects the protected persisted policy.
    @Test
    func repositoryValidatesDecodedConfiguration() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(
            at: fixture.directoryURL,
            withIntermediateDirectories: true
        )
        var configuration = try HomewardConfiguration.initial()
        configuration.selectedApplications = [
            SelectedApplication(
                bundleIdentifier: "com.apple.finder",
                bundlePath: "/System/Library/CoreServices/Finder.app",
                displayName: "Finder"
            ),
        ]
        let data = try JSONEncoder().encode(configuration)
        try data.write(
            to: fixture.directoryURL.appendingPathComponent("configuration.json")
        )
        let repository = HomewardRepository(directoryURL: fixture.directoryURL)

        await #expect(throws: ConfigurationError.protectedApplicationSelection(
            "com.apple.finder"
        )) {
            _ = try await repository.loadConfiguration()
        }
    }
}

/// 1 - Name: Configuration save gate.
/// 2 - Description: Suspends the first injected save to expose runtime safety-action ordering.
/// 3 - Assumptions: Later saves may proceed normally once the first operation is released.
/// 4 - Expectations: Tests can deterministically observe and release the pending persistence operation.
private actor ConfigurationSaveGate {
    private var firstSaveStarted = false
    private var firstSaveContinuation: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func save(
        _ configuration: HomewardConfiguration
    ) async throws -> HomewardConfiguration {
        if !firstSaveStarted {
            firstSaveStarted = true
            let waiters = startWaiters
            startWaiters.removeAll()
            waiters.forEach { $0.resume() }
            await withCheckedContinuation { continuation in
                firstSaveContinuation = continuation
            }
        }
        return configuration
    }

    func waitUntilFirstSaveStarts() async {
        guard !firstSaveStarted else {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func releaseFirstSave() {
        firstSaveContinuation?.resume()
        firstSaveContinuation = nil
    }
}

private struct AppModelFixture {
    let directoryURL: URL

    init() {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("HomewardAppModelTests-\(UUID().uuidString)")
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
