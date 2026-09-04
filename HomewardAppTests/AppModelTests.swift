import AppKit
import AppKit
import Foundation
import Testing
import UserNotifications
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

    /// 1 - Name: Unavailable storage recovery.
    /// 2 - Description: Starts the app model when its storage directory cannot be resolved.
    /// 3 - Assumptions: Built-in defaults remain valid while repository access fails.
    /// 4 - Expectations: Startup remains alive, pauses enforcement, and exposes recovery.
    @Test
    func unavailableStorageEntersRecovery() async throws {
        let repository = HomewardRepository(
            directoryProvider: { throw RepositoryFixtureError.unavailable }
        )
        let model = try AppModel(repository: repository)

        await model.start()

        #expect(model.health == .configurationUnavailable)
        #expect(model.lastError != nil)
        #expect(model.closingRows.isEmpty)
    }

    /// 1 - Name: Onboarding requires a resolvable application.
    /// 2 - Description: Attempts completion with only an unavailable selected app.
    /// 3 - Assumptions: The schedule has been explicitly confirmed.
    /// 4 - Expectations: Completion fails open until an available app is selected.
    @Test
    func onboardingRejectsOnlyUnresolvedApplications() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let model = try AppModel(
            repository: HomewardRepository(directoryURL: fixture.directoryURL)
        )
        await model.start()
        await model.setSchedule(model.configuration.schedule)
        await model.addApplication(SelectedApplication(
            bundleIdentifier: "com.example.missing",
            bundlePath: "/Applications/Missing.app",
            displayName: "Missing",
            isResolvable: false
        ))

        let completed = await model.completeOnboarding()
        #expect(!completed)
        #expect(!model.configuration.completedOnboarding)
    }

    /// 1 - Name: Closing panel presentation priority.
    /// 2 - Description: Compares the Firm safety panel level with ordinary floating feedback panels.
    /// 3 - Assumptions: Blocked-launch and notes panels use the standard floating level.
    /// 4 - Expectations: Closing controls remain above lower-priority automatic panels.
    @Test
    func closingPanelStaysAboveFeedbackPanels() throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let model = try AppModel(
            repository: HomewardRepository(directoryURL: fixture.directoryURL)
        )
        let controller = ClosingPanelController(model: model)

        #expect(
            controller.window?.level.rawValue
                == NSWindow.Level.floating.rawValue + 1
        )
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
        await model.start()
        let cutoff = now.addingTimeInterval(30)

        await model.chooseCutoff(cutoff)

        let custom = model.configuration.overrides.filter {
            $0.kind == .customCutoff
        }
        #expect(custom.count == 2)
        #expect(Set(custom.map(\.effect)) == [.allow, .block])
    }

    /// 1 - Name: Expired custom cutoff.
    /// 2 - Description: Rejects a cutoff that became stale while its panel remained open.
    /// 3 - Assumptions: Ending work immediately is a separate explicit action.
    /// 4 - Expectations: No blocking override is created and the user receives a cutoff error.
    @Test
    func expiredCustomCutoffDoesNotEndWork() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_789_000_000)
        let model = try AppModel(
            repository: HomewardRepository(directoryURL: fixture.directoryURL),
            nowProvider: { now }
        )
        await model.start()

        let succeeded = await model.chooseCutoff(now)
        #expect(!succeeded)
        #expect(model.configuration.overrides.isEmpty)
        #expect(model.lastError == "Choose a cutoff later than the current time.")
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
        await model.start()
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

    /// 1 - Name: Immediate-close schedule preview.
    /// 2 - Description: Evaluates a blocked replacement schedule using the model clock.
    /// 3 - Assumptions: A completed setup uses the default available Monday noon schedule.
    /// 4 - Expectations: Replacing it with an all-blocked week requires confirmation.
    @Test
    func scheduleChangeDetectsImmediateClose() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let calendar = Calendar.autoupdatingCurrent
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 7,
            hour: 12
        )))
        let repository = HomewardRepository(directoryURL: fixture.directoryURL)
        var configuration = try HomewardConfiguration.initial()
        configuration.onboardingScheduleConfirmed = true
        configuration.completedOnboarding = true
        _ = try await repository.saveConfiguration(configuration)
        let model = try AppModel(
            repository: repository,
            nowProvider: { now },
            catalogDiscoverer: { [] }
        )
        await model.start()
        let blockedRules = Dictionary(
            uniqueKeysWithValues: Weekday.allCases.map {
                ($0, DayRule.blockedAllDay)
            }
        )

        #expect(model.scheduleChangeRequiresImmediateClose(
            try WeeklySchedule(rules: blockedRules)
        ))
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
        await model.start()

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
        await model.start()
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
        _ = await pendingSave.value
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
        await model.start()
        let firstUpdate = Task { @MainActor in
            await model.setWarning(.fifteenMinute, enabled: false)
        }
        await saveGate.waitUntilFirstSaveStarts()
        let secondUpdate = Task { @MainActor in
            await model.setWarning(.fiveMinute, enabled: false)
        }

        await saveGate.releaseFirstSave()
        _ = await firstUpdate.value
        _ = await secondUpdate.value

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
        await model.start()

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
        await model.start()
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
        await model.start()
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
        await model.start()

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

    /// 1 - Name: Configuration backup recovery activation.
    /// 2 - Description: Restores a validated previous configuration after active storage becomes corrupt.
    /// 3 - Assumptions: Runtime activation may revalidate selections only after the recovery write lock is released.
    /// 4 - Expectations: Recovery completes without deadlock and reaches ready state.
    @Test
    func configurationBackupRecoveryReactivatesRuntime() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let repository = HomewardRepository(directoryURL: fixture.directoryURL)
        let first = try HomewardConfiguration.initial()
        var second = first
        second.warningPreferences.fiveMinuteWarningEnabled = false
        _ = try await repository.saveConfiguration(first)
        _ = try await repository.saveConfiguration(second)
        try Data("corrupt".utf8).write(
            to: fixture.directoryURL.appendingPathComponent(
                "configuration.json"
            )
        )
        let model = try AppModel(
            repository: repository,
            catalogDiscoverer: { [] }
        )
        await model.start()
        #expect(model.health == .configurationUnavailable)

        let restored = await model.restorePreviousConfiguration()

        #expect(restored)
        #expect(model.health == .ready)
        #expect(model.configuration.schedule == first.schedule)
        #expect(
            model.configuration.warningPreferences
                == first.warningPreferences
        )
        #expect(
            model.configuration.policyGeneration
                > first.policyGeneration
        )
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
        let payload = HomewardNotificationService.warningUserInfo(
            cutoff: cutoff,
            policyGeneration: 7
        )

        #expect(
            HomewardNotificationService.warningActionContext(from: payload)
                == WarningActionContext(
                    cutoff: cutoff,
                    policyGeneration: 7
                )
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
                cutoff: currentCutoff.addingTimeInterval(60),
                policyGeneration: model.configuration.policyGeneration
            )
        )

        #expect(model.configuration.overrides.isEmpty)
    }

    /// 1 - Name: Operation result independence.
    /// 2 - Description: Performs a successful settings mutation while an older global error remains published.
    /// 3 - Assumptions: Error presentation may outlive the operation that produced it.
    /// 4 - Expectations: The mutation reports success from its own result rather than global error state.
    @Test
    func successfulOperationReturnsTrueWithExistingError() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let model = try AppModel(repository: HomewardRepository(
            directoryURL: fixture.directoryURL
        ))
        await model.start()
        #expect(await !model.createExtension(minutes: 11))

        let succeeded = await model.setWarning(
            .fiveMinute,
            enabled: false
        )

        #expect(succeeded)
        #expect(model.lastError == "Choose a supported extension duration.")
    }

    /// 1 - Name: Extension date arithmetic failure.
    /// 2 - Description: Injects a calendar-addition failure into extension creation.
    /// 3 - Assumptions: A failed expiry calculation must not silently skip a requested operation.
    /// 4 - Expectations: Creation returns false, publishes its existing operation error, and saves no override.
    @Test
    func extensionDateArithmeticFailureIsReported() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let model = try AppModel(
            repository: HomewardRepository(directoryURL: fixture.directoryURL),
            dateByAdding: { _, _, _ in nil }
        )
        await model.start()

        let succeeded = await model.createExtension(minutes: 10)

        #expect(!succeeded)
        #expect(model.configuration.overrides.isEmpty)
        #expect(model.lastError == "The extension could not be created.")
    }

    /// 1 - Name: Extension replaces future availability policy.
    /// 2 - Description: Replaces a custom cutoff pair containing active and future availability overrides.
    /// 3 - Assumptions: A new extension supersedes every unexpired today-only availability decision.
    /// 4 - Expectations: Only the new fixed extension remains among availability overrides.
    @Test
    func extensionClearsAllUnexpiredAvailabilityOverrides() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_789_000_000)
        let model = try AppModel(
            repository: HomewardRepository(directoryURL: fixture.directoryURL),
            nowProvider: { now }
        )
        await model.start()
        #expect(await model.chooseCutoff(now.addingTimeInterval(30 * 60)))

        #expect(await model.createExtension(minutes: 10))

        let availabilityOverrides = model.configuration.overrides.filter {
            $0.kind != .forceEscalationPaused
        }
        #expect(availabilityOverrides.count == 1)
        #expect(availabilityOverrides.first?.kind == .fixedExtension)
    }

    /// 1 - Name: Termination identity matching.
    /// 2 - Description: Distinguishes an exact process session from a reused process identifier.
    /// 3 - Assumptions: Missing launch identity cannot prove which process generation terminated.
    /// 4 - Expectations: Only an exact session matches; every PID-only event fails open.
    @Test
    func terminationIdentityRejectsPIDReuse() {
        let expected = ProcessSessionID(rawValue: "42-original")
        let replacement = ProcessSessionID(rawValue: "42-replacement")

        #expect(AppModel.terminationMatches(
            expectedSessionID: expected,
            expectedProcessIdentifier: 42,
            terminatedSessionID: expected,
            terminatedProcessIdentifier: 42,
            hasLiveSessionForProcessIdentifier: true
        ))
        #expect(!AppModel.terminationMatches(
            expectedSessionID: expected,
            expectedProcessIdentifier: 42,
            terminatedSessionID: replacement,
            terminatedProcessIdentifier: 42,
            hasLiveSessionForProcessIdentifier: false
        ))
        #expect(!AppModel.terminationMatches(
            expectedSessionID: expected,
            expectedProcessIdentifier: 42,
            terminatedSessionID: nil,
            terminatedProcessIdentifier: 42,
            hasLiveSessionForProcessIdentifier: true
        ))
        #expect(!AppModel.terminationMatches(
            expectedSessionID: expected,
            expectedProcessIdentifier: 42,
            terminatedSessionID: nil,
            terminatedProcessIdentifier: 42,
            hasLiveSessionForProcessIdentifier: false
        ))
    }

    /// 1 - Name: Note reset mutation serialization.
    /// 2 - Description: Requests a reset while a note save is deliberately suspended.
    /// 3 - Assumptions: Reset and save share one notes mutation boundary.
    /// 4 - Expectations: Reset waits for the save and leaves the authoritative notes document empty.
    @Test
    func resetSavedThoughtsWaitsForPendingSave() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let gate = NotesMutationGate()
        let model = try AppModel(
            repository: HomewardRepository(directoryURL: fixture.directoryURL),
            notesSaver: { try await gate.save($0) },
            notesResetter: { await gate.reset() }
        )
        await model.start()
        await waitForNotesLoad(model)
        let save = Task { @MainActor in
            await model.saveNote("Ship the follow-up")
        }
        await gate.waitUntilSaveStarts()
        let reset = Task { @MainActor in
            await model.resetSavedThoughts()
        }
        await Task.yield()

        #expect(!(await gate.didReset))

        await gate.releaseSave()
        #expect(await save.value)
        #expect(await reset.value)
        #expect(await gate.didReset)
        #expect(model.notes.notes.isEmpty)
    }

    /// 1 - Name: Onboarding confirmation save race.
    /// 2 - Description: Dirties the schedule draft while a confirmed schedule save is suspended.
    /// 3 - Assumptions: Draft edits are synchronous while persistence can suspend.
    /// 4 - Expectations: Completion remains unconfirmed after the stale save returns.
    @Test
    func onboardingDirtyStateWinsPendingSave() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let saveGate = ConfigurationSaveGate()
        let model = try AppModel(
            repository: HomewardRepository(directoryURL: fixture.directoryURL),
            configurationSaver: { try await saveGate.save($0) }
        )
        await model.start()
        let schedule = try WeeklySchedule.defaultWorkWeek()
        let save = Task { @MainActor in
            await model.setSchedule(schedule)
        }
        await saveGate.waitUntilFirstSaveStarts()

        model.markOnboardingScheduleDirty()
        await saveGate.releaseFirstSave()

        #expect(await save.value)
        #expect(!model.configuration.onboardingScheduleConfirmed)
    }

    /// 1 - Name: Catalog refresh latest result.
    /// 2 - Description: Coalesces a second refresh while the first discovery result is suspended.
    /// 3 - Assumptions: The first result is stale as soon as another refresh is requested.
    /// 4 - Expectations: Only the latest catalog is published and both callers complete together.
    @Test
    func catalogRefreshCoalescesAndPublishesLatestResult() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let gate = CatalogDiscoveryGate()
        let model = try AppModel(
            repository: HomewardRepository(directoryURL: fixture.directoryURL),
            catalogDiscoverer: { await gate.discover() }
        )
        let first = Task { @MainActor in
            await model.refreshCatalog()
        }
        await gate.waitUntilFirstDiscoveryStarts()
        let second = Task { @MainActor in
            await model.refreshCatalog()
        }
        await Task.yield()
        gate.releaseFirstDiscovery()
        _ = await first.value
        _ = await second.value

        #expect(gate.discoveryCount == 2)
        #expect(model.catalog.map(\.selection.displayName) == ["Latest"])
    }

    /// 1 - Name: Startup selection revalidation.
    /// 2 - Description: Loads a previously resolvable selection whose application is now missing.
    /// 3 - Assumptions: Persisted resolution metadata is only a cache and cannot authorize enforcement.
    /// 4 - Expectations: Startup marks the selection unresolved before the model becomes ready.
    @Test
    func startupRevalidatesSelectionsBeforeReadiness() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let repository = HomewardRepository(
            directoryURL: fixture.directoryURL
        )
        var configuration = try HomewardConfiguration.initial()
        configuration.selectedApplications = [
            SelectedApplication(
                bundleIdentifier: "com.example.missing",
                bundlePath: "/Applications/Missing.app",
                displayName: "Missing",
                isResolvable: true
            ),
        ]
        configuration.onboardingScheduleConfirmed = true
        configuration.completedOnboarding = true
        _ = try await repository.saveConfiguration(configuration)
        let model = try AppModel(
            repository: repository,
            catalogDiscoverer: { [] }
        )

        await model.start()

        #expect(model.health == .ready)
        #expect(
            model.configuration.selectedApplications.first?.isResolvable
                == false
        )
        #expect(model.closingRows.isEmpty)
    }

    /// 1 - Name: Warning scheduling latest wins.
    /// 2 - Description: Supersedes a suspended warning replacement with a newer cutoff.
    /// 3 - Assumptions: Notification-center additions may finish after a newer request starts.
    /// 4 - Expectations: Partial stale requests are removed and only latest-cutoff warnings remain.
    @Test
    func warningReplacementRemovesPartialStaleRequests() async throws {
        let recorder = WarningClientRecorder()
        let service = HomewardNotificationService(
            client: recorder.client,
            nowProvider: { Date(timeIntervalSince1970: 1_789_000_000) }
        )
        let handler = NotificationHandlerSpy()
        service.start(handler: handler)
        let firstCutoff = Date(timeIntervalSince1970: 1_789_010_000)
        let latestCutoff = Date(timeIntervalSince1970: 1_789_020_000)
        let first = Task { @MainActor in
            try await service.replaceWarnings(
                cutoff: firstCutoff,
                policyGeneration: 1,
                preferences: WarningPreferences(),
                includeExtension: false
            )
        }
        await recorder.waitUntilFirstAddStarts()
        let latest = Task { @MainActor in
            try await service.replaceWarnings(
                cutoff: latestCutoff,
                policyGeneration: 2,
                preferences: WarningPreferences(),
                includeExtension: false
            )
        }
        try await latest.value
        recorder.releaseFirstAdd()
        try await first.value

        #expect(recorder.pendingIdentifiers.count == 2)
        #expect(recorder.pendingIdentifiers.allSatisfy {
            $0.contains(String(latestCutoff.timeIntervalSince1970))
        })
    }

    /// 1 - Name: Notification shutdown cleanup.
    /// 2 - Description: Stops the service while an immediate status notification is being added.
    /// 3 - Assumptions: Notification-center writes may complete after application termination begins.
    /// 4 - Expectations: A late request is removed and cannot survive service shutdown.
    @Test
    func notificationStopRemovesInFlightStatus() async throws {
        let recorder = WarningClientRecorder()
        let service = HomewardNotificationService(client: recorder.client)
        let handler = NotificationHandlerSpy()
        service.start(handler: handler)
        let post = Task { @MainActor in
            try await service.post(
                .closingComplete(nextAvailability: nil)
            )
        }
        await recorder.waitUntilFirstAddStarts()

        service.stop()
        recorder.releaseFirstAdd()
        try await post.value

        #expect(recorder.pendingIdentifiers.isEmpty)
    }

    /// 1 - Name: Policy cleanup removes in-flight status.
    /// 2 - Description: Runs all-owned cleanup while a typed status request is still being added.
    /// 3 - Assumptions: Policy changes may race with notification-center completion.
    /// 4 - Expectations: The late status observes invalidation and removes itself from pending and delivered collections.
    @Test
    func allOwnedCleanupInvalidatesInFlightStatus() async throws {
        let recorder = WarningClientRecorder()
        let service = HomewardNotificationService(client: recorder.client)
        service.start(handler: NotificationHandlerSpy())
        let post = Task { @MainActor in
            try await service.post(
                .blockedLaunch(nextAvailability: nil)
            )
        }
        await recorder.waitUntilFirstAddStarts()

        await service.removeAllOwned()
        recorder.releaseFirstAdd()
        try await post.value

        #expect(recorder.pendingIdentifiers.isEmpty)
        #expect(recorder.deliveredIdentifiers.isEmpty)
    }

    /// 1 - Name: Pre-onboarding notification suppression.
    /// 2 - Description: Grants notification permission while setup is still incomplete.
    /// 3 - Assumptions: The current time is inside the default work window warning period.
    /// 4 - Expectations: No actionable warning is scheduled before onboarding completes.
    @Test
    func onboardingDoesNotScheduleWarnings() async throws {
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
        let recorder = WarningClientRecorder(
            authorizationStatus: .authorized,
            suspendFirstAdd: false
        )
        let service = HomewardNotificationService(
            client: recorder.client,
            nowProvider: { now }
        )
        let model = try AppModel(
            repository: HomewardRepository(
                directoryURL: fixture.directoryURL
            ),
            nowProvider: { now },
            catalogDiscoverer: { [] },
            notificationService: service
        )
        await model.start()

        let authorized = await model.requestNotificationPermission()
        #expect(authorized)

        #expect(recorder.pendingIdentifiers.isEmpty)
    }

    /// 1 - Name: Pre-onboarding notification action.
    /// 2 - Description: Routes a current warning action before setup activation.
    /// 3 - Assumptions: The action cutoff exactly matches the default work-window cutoff.
    /// 4 - Expectations: The action cannot create an availability override before onboarding completes.
    @Test
    func onboardingIgnoresNotificationActions() async throws {
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
        let cutoff = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 7,
            hour: 17
        )))
        let model = try AppModel(
            repository: HomewardRepository(
                directoryURL: fixture.directoryURL
            ),
            nowProvider: { now }
        )

        await model.applyNotificationAction(
            HomewardNotificationService.startClosingAction,
            context: WarningActionContext(
                cutoff: cutoff,
                policyGeneration: model.configuration.policyGeneration
            )
        )

        #expect(model.configuration.overrides.isEmpty)
    }

    /// 1 - Name: Warning copy privacy.
    /// 2 - Description: Schedules wind-down warnings without exposing selected application names.
    /// 3 - Assumptions: Notification previews may appear on a shared or locked screen.
    /// 4 - Expectations: Every warning uses generic work-app language.
    @Test
    func warningCopyIsPrivateByDefault() async throws {
        let recorder = WarningClientRecorder(suspendFirstAdd: false)
        let service = HomewardNotificationService(
            client: recorder.client,
            nowProvider: { Date(timeIntervalSince1970: 1_789_000_000) }
        )
        let handler = NotificationHandlerSpy()
        service.start(handler: handler)

        try await service.replaceWarnings(
            cutoff: Date(timeIntervalSince1970: 1_789_010_000),
            policyGeneration: 1,
            preferences: WarningPreferences(),
            includeExtension: false
        )

        #expect(!recorder.addedBodies.isEmpty)
        #expect(recorder.addedBodies.contains {
            $0.hasPrefix("Finish your current thought. Work apps will close at ")
        })
        #expect(recorder.addedBodies.allSatisfy { !$0.contains("Editor") })
    }

    /// 1 - Name: Notification authorization loss cleanup.
    /// 2 - Description: Refreshes denied authorization while owned warning and status requests are present.
    /// 3 - Assumptions: Homeward ownership is represented by warning and status identifier prefixes.
    /// 4 - Expectations: Status becomes denied and all owned pending and delivered requests are removed.
    @Test
    func authorizationLossRemovesWarnings() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let recorder = WarningClientRecorder(
            authorizationStatus: .denied,
            pendingIdentifiers: [
                "homeward-warning-existing",
                "homeward-status-existing",
            ],
            deliveredIdentifiers: ["homeward-status-delivered"]
        )
        let service = HomewardNotificationService(client: recorder.client)
        let model = try AppModel(
            repository: HomewardRepository(directoryURL: fixture.directoryURL),
            notificationService: service
        )

        await model.refreshSystemStatuses()

        #expect(model.notificationStatus == .denied)
        #expect(recorder.pendingIdentifiers.isEmpty)
        #expect(recorder.deliveredIdentifiers.isEmpty)
    }

    /// 1 - Name: Unknown login-item status.
    /// 2 - Description: Maps a future ServiceManagement state and attempts to disable it.
    /// 3 - Assumptions: Unknown framework states cannot safely be treated as already disabled.
    /// 4 - Expectations: UI status is unavailable and disable throws an explicit service error.
    @Test
    func unknownLoginStatusIsUnavailableAndDisableThrows() throws {
        let service = LoginItemService(statusProvider: { .unavailable })

        #expect(service.status == .unavailable)
        #expect(throws: LoginItemService.ServiceError.unavailable) {
            try service.disable()
        }
    }

    /// 1 - Name: Failed login operation status refresh.
    /// 2 - Description: Attempts registration while the platform reports an unavailable state.
    /// 3 - Assumptions: Platform failure status is authoritative even when the operation throws.
    /// 4 - Expectations: Enable returns false and the model refreshes its displayed status to unavailable.
    @Test
    func failedLoginOperationRefreshesStatus() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let service = LoginItemService(statusProvider: { .unavailable })
        let model = try AppModel(
            repository: HomewardRepository(directoryURL: fixture.directoryURL),
            catalogDiscoverer: { [] },
            loginItemService: service,
            installationLocationService: InstallationLocationService(
                statusProvider: { .applications }
            )
        )
        await model.start()

        #expect(!model.enableStartAtLogin())
        #expect(model.loginItemStatus == .unavailable)
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

    /// 1 - Name: Startup policy mutation gate.
    /// 2 - Description: Attempts a policy write before configuration verification completes.
    /// 3 - Assumptions: Model construction alone does not verify the user’s persisted configuration.
    /// 4 - Expectations: The mutation is rejected and built-in initial policy remains unchanged.
    @Test
    func startupRejectsPolicyMutation() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let model = try AppModel(
            repository: HomewardRepository(directoryURL: fixture.directoryURL)
        )

        let succeeded = await model.setWarning(
            .fifteenMinute,
            enabled: false
        )

        #expect(!succeeded)
        #expect(
            model.configuration.warningPreferences
                .fifteenMinuteWarningEnabled
        )
    }

    /// 1 - Name: Delayed startup retry handoff.
    /// 2 - Description: Publishes delayed startup and invokes the delegate-owned retry callback.
    /// 3 - Assumptions: The application delegate installs one callback before exposing Retry.
    /// 4 - Expectations: Retry returns the model to starting and requests one fresh bootstrap attempt.
    @Test
    func delayedStartupRetryRequestsFreshBootstrap() throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let model = try AppModel(
            repository: HomewardRepository(directoryURL: fixture.directoryURL)
        )
        var retryCount = 0
        model.installBootstrapRetryHandler {
            retryCount += 1
        }
        model.markStartupDelayed()

        model.retryStartup()

        #expect(model.health == .starting)
        #expect(retryCount == 1)
    }

    /// 1 - Name: Catalog discovery failure state.
    /// 2 - Description: Starts with verified settings while application discovery throws.
    /// 3 - Assumptions: Enforcement cannot start until selected applications are resolved successfully.
    /// 4 - Expectations: Startup stays fail-open, reports discovery failure, and retains verified selection state.
    @Test
    func catalogDiscoveryFailureRetainsVerifiedSelections() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let repository = HomewardRepository(directoryURL: fixture.directoryURL)
        var configuration = try HomewardConfiguration.initial()
        configuration.selectedApplications = [
            SelectedApplication(
                bundleIdentifier: "com.example.editor",
                bundlePath: "/Applications/Editor.app",
                displayName: "Editor"
            ),
        ]
        _ = try await repository.saveConfiguration(configuration)
        let model = try AppModel(
            repository: repository,
            catalogDiscoverer: {
                throw CatalogFixtureError.discoveryFailed
            }
        )

        await model.start()

        #expect(model.health == .applicationResolutionUnavailable)
        #expect(model.catalogHealth == .unavailable)
        #expect(
            model.configuration.selectedApplications.first?.isResolvable
                == true
        )
        #expect(model.closingRows.isEmpty)
    }

    /// 1 - Name: Duplicate bundle exact-path resolution.
    /// 2 - Description: Resolves a saved bundle identifier when two discovered copies share it.
    /// 3 - Assumptions: The saved standardized path is one of the discovered candidates.
    /// 4 - Expectations: The exact saved copy remains resolvable without being retargeted.
    @Test
    func duplicateBundleUsesExactSavedPath() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let repository = HomewardRepository(directoryURL: fixture.directoryURL)
        var configuration = try HomewardConfiguration.initial()
        configuration.selectedApplications = [
            SelectedApplication(
                bundleIdentifier: "com.example.editor",
                bundlePath: "/Applications/Editor.app",
                displayName: "Editor"
            ),
        ]
        _ = try await repository.saveConfiguration(configuration)
        let candidates = [
            catalogApplication(
                named: "Editor",
                bundleIdentifier: "com.example.editor",
                path: "/Applications/Editor.app"
            ),
            catalogApplication(
                named: "Editor Copy",
                bundleIdentifier: "com.example.editor",
                path: "/Users/test/Applications/Editor.app"
            ),
        ]
        let model = try AppModel(
            repository: repository,
            catalogDiscoverer: { candidates }
        )

        await model.start()

        #expect(model.health == .ready)
        #expect(
            model.configuration.selectedApplications.first?.bundlePath
                == "/Applications/Editor.app"
        )
        #expect(
            model.configuration.selectedApplications.first?.isResolvable
                == true
        )
    }

    /// 1 - Name: Duplicate bundle ambiguity fails open.
    /// 2 - Description: Resolves a missing saved path against two discovered copies with the same bundle identifier.
    /// 3 - Assumptions: Neither candidate has the exact saved path and no unique bundle match exists.
    /// 4 - Expectations: The saved selection remains at its original path and becomes unresolved.
    @Test
    func duplicateBundleAmbiguityFailsOpen() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let repository = HomewardRepository(directoryURL: fixture.directoryURL)
        var configuration = try HomewardConfiguration.initial()
        configuration.selectedApplications = [
            SelectedApplication(
                bundleIdentifier: "com.example.editor",
                bundlePath: "/Missing/Editor.app",
                displayName: "Editor"
            ),
        ]
        _ = try await repository.saveConfiguration(configuration)
        let candidates = [
            catalogApplication(
                named: "Editor",
                bundleIdentifier: "com.example.editor",
                path: "/Applications/Editor.app"
            ),
            catalogApplication(
                named: "Editor Copy",
                bundleIdentifier: "com.example.editor",
                path: "/Users/test/Applications/Editor.app"
            ),
        ]
        let model = try AppModel(
            repository: repository,
            catalogDiscoverer: { candidates }
        )

        await model.start()

        #expect(model.health == .ready)
        #expect(
            model.configuration.selectedApplications.first?.bundlePath
                == "/Missing/Editor.app"
        )
        #expect(
            model.configuration.selectedApplications.first?.isResolvable
                == false
        )
    }

    /// 1 - Name: Stale schedule draft rejection.
    /// 2 - Description: Saves another policy field after a schedule editor captures its base revision.
    /// 3 - Assumptions: Every successful configuration save advances the model revision.
    /// 4 - Expectations: The stale schedule is rejected and the newer warning policy remains authoritative.
    @Test
    func staleScheduleDraftDoesNotOverwriteNewerPolicy() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let model = try AppModel(
            repository: HomewardRepository(directoryURL: fixture.directoryURL),
            catalogDiscoverer: { [] }
        )
        await model.start()
        let draftRevision = model.policyRevision
        #expect(await model.setWarning(.fiveMinute, enabled: false))
        var rules = model.configuration.schedule.rules
        rules[.monday] = .availableAllDay

        let saved = await model.setSchedule(
            try WeeklySchedule(rules: rules),
            expectedRevision: draftRevision
        )

        #expect(!saved)
        #expect(
            !model.configuration.warningPreferences.fiveMinuteWarningEnabled
        )
        #expect(model.configuration.schedule.rules[.monday] != .availableAllDay)
    }

    /// 1 - Name: Stale work-app edit rejection.
    /// 2 - Description: Adds an application from a work-app view whose base policy revision is outdated.
    /// 3 - Assumptions: Another successful settings save occurred after the view captured its revision.
    /// 4 - Expectations: The stale selection is not added and the newer policy remains intact.
    @Test
    func staleWorkAppEditDoesNotOverwriteNewerPolicy() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let model = try AppModel(
            repository: HomewardRepository(directoryURL: fixture.directoryURL),
            catalogDiscoverer: { [] }
        )
        await model.start()
        let draftRevision = model.policyRevision
        #expect(await model.setWarning(.fiveMinute, enabled: false))

        let added = await model.addApplication(
            SelectedApplication(
                bundleIdentifier: "com.example.editor",
                bundlePath: "/Applications/Editor.app",
                displayName: "Editor"
            ),
            expectedRevision: draftRevision
        )

        #expect(!added)
        #expect(model.configuration.selectedApplications.isEmpty)
        #expect(
            !model.configuration.warningPreferences.fiveMinuteWarningEnabled
        )
    }

    /// 1 - Name: Commit-time immediate-close confirmation.
    /// 2 - Description: Attempts to replace an active saved schedule with an all-closed week.
    /// 3 - Assumptions: Setup is complete and the fixed model time is inside the saved work window.
    /// 4 - Expectations: An unconfirmed commit is rejected and an explicitly confirmed retry succeeds.
    @Test
    func scheduleCommitRecomputesImmediateCloseConsequence() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 7,
            hour: 12
        )))
        let repository = HomewardRepository(directoryURL: fixture.directoryURL)
        var configuration = try HomewardConfiguration.initial()
        configuration.selectedApplications = [
            SelectedApplication(
                bundleIdentifier: "com.example.editor",
                bundlePath: "/Applications/Editor.app",
                displayName: "Editor"
            ),
        ]
        configuration.onboardingScheduleConfirmed = true
        configuration.completedOnboarding = true
        _ = try await repository.saveConfiguration(configuration)
        let candidate = catalogApplication(
            named: "Editor",
            bundleIdentifier: "com.example.editor",
            path: "/Applications/Editor.app"
        )
        let model = try AppModel(
            repository: repository,
            nowProvider: { now },
            catalogDiscoverer: { [candidate] }
        )
        await model.start()
        let blocked = try WeeklySchedule(
            rules: Dictionary(
                uniqueKeysWithValues: Weekday.allCases.map {
                    ($0, DayRule.blockedAllDay)
                }
            )
        )
        let revision = model.policyRevision

        #expect(!(await model.setSchedule(
            blocked,
            expectedRevision: revision
        )))
        #expect(model.resolvedSchedule.isAvailable)
        #expect(await model.setSchedule(
            blocked,
            expectedRevision: revision,
            confirmsImmediateClose: true
        ))
        #expect(!model.resolvedSchedule.isAvailable)
    }

    /// 1 - Name: Notes load failure health.
    /// 2 - Description: Starts enforcement successfully with corrupt notes storage.
    /// 3 - Assumptions: Configuration and notes use independent files and empty notes is a valid document.
    /// 4 - Expectations: Runtime becomes ready while notes report unavailable rather than empty.
    @Test
    func notesFailureDoesNotDelayRuntimeReadiness() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(
            at: fixture.directoryURL,
            withIntermediateDirectories: true
        )
        try Data("corrupt".utf8).write(
            to: fixture.directoryURL.appendingPathComponent("notes.json")
        )
        let model = try AppModel(
            repository: HomewardRepository(directoryURL: fixture.directoryURL),
            catalogDiscoverer: { [] }
        )

        await model.start()
        await waitForNotesLoad(model)

        #expect(model.health == .ready)
        #expect(model.notesHealth == .unavailable)
        #expect(model.visibleNotes.isEmpty)
    }

    /// 1 - Name: Notes backup restoration.
    /// 2 - Description: Restores the last validated notes document through repository recovery APIs.
    /// 3 - Assumptions: A second successful save creates an explicit previous-document candidate.
    /// 4 - Expectations: Recovery replaces active notes without changing configuration storage.
    @Test
    func repositoryRestoresPreviousNotes() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let repository = HomewardRepository(directoryURL: fixture.directoryURL)
        let first = try NotesDocument(
            notes: [TomorrowNote(text: "First")]
        )
        let second = try NotesDocument(
            notes: [TomorrowNote(text: "Second")]
        )
        _ = try await repository.saveNotes(first)
        _ = try await repository.saveNotes(second)
        let candidate = try #require(
            try await repository.notesRecoveryCandidate()
        )

        _ = try await repository.replaceNotesDuringRecovery(candidate)

        #expect(try await repository.loadNotes() == first)
    }

    /// 1 - Name: Notes recovery preserves configuration.
    /// 2 - Description: Restores a validated previous notes document after the active notes file becomes corrupt.
    /// 3 - Assumptions: Configuration and notes have independent stores and generations.
    /// 4 - Expectations: Thoughts recover while the app-closing policy remains byte-for-byte equivalent.
    @Test
    func notesRecoveryDoesNotChangeConfiguration() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let repository = HomewardRepository(directoryURL: fixture.directoryURL)
        var configuration = try HomewardConfiguration.initial()
        configuration.advancePolicyGeneration(after: 9)
        _ = try await repository.saveConfiguration(configuration)
        _ = try await repository.saveNotes(
            NotesDocument(notes: [TomorrowNote(text: "Recover me")])
        )
        _ = try await repository.saveNotes(
            NotesDocument(notes: [TomorrowNote(text: "Current")])
        )
        try Data("corrupt".utf8).write(
            to: fixture.directoryURL.appendingPathComponent("notes.json")
        )
        let model = try AppModel(
            repository: repository,
            catalogDiscoverer: { [] }
        )
        await model.start()
        await waitForNotesLoad(model)
        let policyBeforeRecovery = model.configuration

        #expect(model.notesRecoveryCandidateAvailable)
        #expect(await model.restorePreviousNotes())
        #expect(model.notes.notes.map(\.text) == ["Recover me"])
        #expect(model.configuration == policyBeforeRecovery)
    }

    /// 1 - Name: Bounded shutdown save wait.
    /// 2 - Description: Begins termination while a configuration save remains suspended.
    /// 3 - Assumptions: The injected elapsed clock advances independently of wall-clock schedule time.
    /// 4 - Expectations: Shutdown returns after its monotonic bound without cancelling the in-flight durable save.
    @Test
    func terminationWaitForPendingSaveIsBounded() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let saveGate = ConfigurationSaveGate()
        let testClock = TestElapsedClock()
        let model = try AppModel(
            repository: HomewardRepository(directoryURL: fixture.directoryURL),
            elapsedClock: testClock.clock,
            configurationSaver: { try await saveGate.save($0) },
            catalogDiscoverer: { [] }
        )
        await model.start()
        let save = Task { @MainActor in
            await model.setWarning(.fiveMinute, enabled: false)
        }
        await saveGate.waitUntilFirstSaveStarts()

        await model.prepareForTermination()

        #expect(testClock.totalSlept >= .seconds(2))
        await saveGate.releaseFirstSave()
        _ = await save.value
    }

    /// 1 - Name: Current notification action confirmation.
    /// 2 - Description: Routes a generation-bound warning action through Today's shared confirmation intent.
    /// 3 - Assumptions: The saved schedule is currently available and setup is complete.
    /// 4 - Expectations: The action does not mutate policy until confirmation, then applies End Work Now.
    @Test
    func currentNotificationActionRequiresSharedConfirmation() async throws {
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
        let cutoff = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 7,
            hour: 17
        )))
        let repository = HomewardRepository(directoryURL: fixture.directoryURL)
        let selection = SelectedApplication(
            bundleIdentifier: "com.example.fixture",
            bundlePath: "/Applications/HomewardFixture.app",
            displayName: "Private App Name"
        )
        var configuration = try HomewardConfiguration.initial()
        configuration.selectedApplications = [selection]
        configuration.onboardingScheduleConfirmed = true
        configuration.completedOnboarding = true
        _ = try await repository.saveConfiguration(configuration)
        let model = try AppModel(
            repository: repository,
            nowProvider: { now },
            catalogDiscoverer: {
                [catalogApplication(
                    named: selection.displayName,
                    bundleIdentifier: selection.bundleIdentifier!,
                    path: selection.bundlePath
                )]
            }
        )
        var routedDestination: HomewardRoute?
        model.installRouteHandler { routedDestination = $0 }
        await model.start()

        await model.applyNotificationAction(
            HomewardNotificationService.startClosingAction,
            context: WarningActionContext(
                cutoff: cutoff,
                policyGeneration: model.configuration.policyGeneration
            )
        )

        #expect(model.configuration.overrides.isEmpty)
        #expect(model.pendingPolicyConfirmation == .endWorkNow)
        #expect(routedDestination == .today)
        #expect(await model.confirmPolicyAction())
        #expect(model.configuration.overrides.contains {
            $0.kind == .endWorkNow
        })
    }

    /// 1 - Name: Stale and malformed notification routing.
    /// 2 - Description: Handles warning actions from a prior generation and with missing context.
    /// 3 - Assumptions: The stale cutoff still matches, so generation is independently validated.
    /// 4 - Expectations: Neither action changes policy and both route to Today with a calm explanation.
    @Test
    func staleNotificationGenerationRoutesWithoutMutation() async throws {
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
        let cutoff = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 7,
            hour: 17
        )))
        let repository = HomewardRepository(directoryURL: fixture.directoryURL)
        var configuration = try HomewardConfiguration.initial()
        configuration.selectedApplications = [
            SelectedApplication(
                bundleIdentifier: "com.example.fixture",
                bundlePath: "/Applications/HomewardFixture.app",
                displayName: "Private App Name"
            ),
        ]
        configuration.onboardingScheduleConfirmed = true
        configuration.completedOnboarding = true
        _ = try await repository.saveConfiguration(configuration)
        let model = try AppModel(
            repository: repository,
            nowProvider: { now },
            catalogDiscoverer: {
                [catalogApplication(
                    named: "Private App Name",
                    bundleIdentifier: "com.example.fixture",
                    path: "/Applications/HomewardFixture.app"
                )]
            }
        )
        var routedDestination: HomewardRoute?
        model.installRouteHandler { routedDestination = $0 }
        await model.start()
        let staleGeneration = model.configuration.policyGeneration
        #expect(await model.setWarning(.fiveMinute, enabled: false))
        #expect(model.configuration.policyGeneration != staleGeneration)

        await model.applyNotificationAction(
            HomewardNotificationService.startClosingAction,
            context: WarningActionContext(
                cutoff: cutoff,
                policyGeneration: staleGeneration
            )
        )

        #expect(model.configuration.overrides.isEmpty)
        #expect(model.pendingPolicyConfirmation == nil)
        #expect(routedDestination == .today)
        #expect(
            model.todayExplanation
                == "This notification is no longer current. No changes were made."
        )

        model.clearTodayExplanation()
        routedDestination = nil
        await model.applyNotificationAction(
            HomewardNotificationService.startClosingAction,
            context: nil
        )
        #expect(model.configuration.overrides.isEmpty)
        #expect(routedDestination == .today)
        #expect(model.todayExplanation != nil)
    }

    /// 1 - Name: Generic blocked-launch notification.
    /// 2 - Description: Builds the typed blocked-launch event for lock-screen-safe delivery.
    /// 3 - Assumptions: Selected app identity and thought content are never event inputs.
    /// 4 - Expectations: Approved generic title and body contain no app name, path, identifier, or thought.
    @Test
    func blockedLaunchNotificationIsGeneric() {
        let event = HomewardNotificationService.StatusEvent.blockedLaunch(
            nextAvailability: nil
        )

        #expect(event.title == "A work app was closed")
        #expect(event.body == "No work window is scheduled.")
        #expect(!event.title.contains("Private App Name"))
        #expect(!event.body.contains("/Applications"))
        #expect(!event.body.contains("com.example"))
        #expect(!event.body.contains("secret thought"))
    }

    /// 1 - Name: All-owned notification cleanup.
    /// 2 - Description: Removes Homeward warning and status requests from pending and delivered collections.
    /// 3 - Assumptions: Requests owned by another subsystem do not use a Homeward identifier prefix.
    /// 4 - Expectations: Every owned request is removed while unrelated notifications remain.
    @Test
    func allOwnedNotificationCleanupPreservesUnrelatedRequests() async {
        let recorder = WarningClientRecorder(
            pendingIdentifiers: [
                "homeward-warning-one",
                "homeward-status-two",
                "other-pending",
            ],
            deliveredIdentifiers: [
                "homeward-warning-three",
                "homeward-status-four",
                "other-delivered",
            ]
        )
        let service = HomewardNotificationService(client: recorder.client)

        await service.removeAllOwned()

        #expect(recorder.pendingIdentifiers == ["other-pending"])
        #expect(recorder.deliveredIdentifiers == ["other-delivered"])
    }

    /// 1 - Name: Saved-thought session concealment.
    /// 2 - Description: Moves an available saved thought through active and inactive session states.
    /// 3 - Assumptions: The fixed time is in a normal base work window and notes load independently.
    /// 4 - Expectations: Count remains generic while content appears only in the active session and redacts immediately on inactivity.
    @Test
    func savedThoughtContentRequiresActiveBaseWindow() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let calendar = Calendar.autoupdatingCurrent
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 7,
            hour: 12
        )))
        let repository = HomewardRepository(directoryURL: fixture.directoryURL)
        _ = try await repository.saveNotes(
            NotesDocument(notes: [TomorrowNote(text: "Private thought")])
        )
        let model = try AppModel(
            repository: repository,
            nowProvider: { now },
            catalogDiscoverer: { [] }
        )
        await model.start()
        await waitForNotesLoad(model)
        let monitor = WorkspaceMonitor()

        model.workspaceMonitor(
            monitor,
            sessionActiveDidChange: false
        )
        #expect(model.availableNotesCount == 1)
        #expect(model.visibleNotes.isEmpty)

        model.workspaceMonitor(
            monitor,
            sessionActiveDidChange: true
        )
        await Task.yield()
        #expect(model.visibleNotes.map(\.text) == ["Private thought"])

        model.workspaceMonitor(
            monitor,
            sessionActiveDidChange: false
        )
        #expect(model.visibleNotes.isEmpty)
    }

    /// 1 - Name: Outside-Applications login protection.
    /// 2 - Description: Attempts to enable Start at Login for a copy launched outside /Applications.
    /// 3 - Assumptions: Installation status is injected and no file move is attempted by the model.
    /// 4 - Expectations: Registration is disabled with an explanation and Show in Finder remains available.
    @Test
    func outsideApplicationsDisablesStartAtLogin() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let appURL = URL(fileURLWithPath: "/Downloads/Homeward.app")
        var didReveal = false
        let installation = InstallationLocationService(
            statusProvider: { .outsideApplications(appURL) },
            reveal: { url in didReveal = url == appURL }
        )
        let model = try AppModel(
            repository: HomewardRepository(directoryURL: fixture.directoryURL),
            catalogDiscoverer: { [] },
            installationLocationService: installation
        )
        await model.start()
        await model.refreshSystemStatuses()

        #expect(!model.enableStartAtLogin())
        #expect(
            model.lastError
                == "Move Homeward to Applications before enabling Start at Login."
        )
        model.showInstallationInFinder()
        #expect(didReveal)
    }

    /// 1 - Name: Presentation precedence and counts.
    /// 2 - Description: Resolves recovery and Firm-pause snapshots with simultaneous passive attention.
    /// 3 - Assumptions: Recovery and Firm safety outrank schedule, thoughts, and readiness counts.
    /// 4 - Expectations: Titles and primary actions follow normative precedence without exposing thought content.
    @Test
    func presentationSnapshotUsesNormativePrecedence() throws {
        let schedule = ScheduleResolver().resolve(
            schedule: try WeeklySchedule.defaultWorkWeek(),
            overrides: [],
            at: Date(timeIntervalSince1970: 1_789_000_000),
            calendar: .autoupdatingCurrent,
            warnings: WarningPreferences()
        )

        let recovery = HomewardPresentationSnapshot.resolve(
            health: .configurationUnavailable,
            onboardingComplete: true,
            schedule: schedule,
            closingCount: 2,
            forceEscalationPaused: true,
            savedThoughtCount: 3,
            attentionCount: 4
        )
        let firmPause = HomewardPresentationSnapshot.resolve(
            health: .ready,
            onboardingComplete: true,
            schedule: schedule,
            closingCount: 2,
            forceEscalationPaused: true,
            savedThoughtCount: 3,
            attentionCount: 4
        )

        #expect(recovery.title == "App closing is paused")
        #expect(recovery.primaryAction == .openRecovery)
        #expect(firmPause.title == "Force quit is paused")
        #expect(firmPause.primaryAction == .resumeFirmClosing)
        #expect(firmPause.savedThoughtCount == 3)
        #expect(!firmPause.accessibilityValue.contains("thought text"))
    }

    /// 1 - Name: Firm safety suppresses passive panels.
    /// 2 - Description: Evaluates event-priority admission while the Firm safety surface is active.
    /// 3 - Assumptions: Higher numeric priority represents a surface that must remain unobscured.
    /// 4 - Expectations: Passive panels stay below save/error and Firm safety while recovery can supersede both.
    @Test
    func firmSafetySuppressesPassivePresentation() {
        #expect(!PresentationCoordinator.permits(
            .blockedLaunch,
            over: .firmSafety
        ))
        #expect(!PresentationCoordinator.permits(
            .thoughtAvailability,
            over: .firmSafety
        ))
        #expect(!PresentationCoordinator.permits(
            .blockedLaunch,
            over: .saveOrError
        ))
        #expect(PresentationCoordinator.permits(
            .recovery,
            over: .firmSafety
        ))
    }

    /// 1 - Name: Configuration reset preserves saved thoughts.
    /// 2 - Description: Replaces corrupt settings with fresh setup while a valid notes document exists.
    /// 3 - Assumptions: Configuration and notes are independent repository documents.
    /// 4 - Expectations: Configuration recovery reaches ready state and loads the unchanged thought.
    @Test
    func configurationResetPreservesSavedThoughts() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let repository = HomewardRepository(directoryURL: fixture.directoryURL)
        let note = try TomorrowNote(text: "Keep this thought")
        _ = try await repository.saveNotes(
            NotesDocument(notes: [note])
        )
        try Data("corrupt".utf8).write(
            to: fixture.directoryURL.appendingPathComponent(
                "configuration.json"
            )
        )
        let model = try AppModel(
            repository: repository,
            catalogDiscoverer: { [] }
        )
        await model.start()
        #expect(model.health == .configurationUnavailable)

        #expect(await model.replaceWithFreshSetup())
        await waitForNotesLoad(model)

        #expect(model.health == .ready)
        #expect(!model.configuration.completedOnboarding)
        #expect(model.notes.notes == [note])
    }

    /// 1 - Name: Completed thought restoration.
    /// 2 - Description: Completes one thought and restores the returned value in the same review session.
    /// 3 - Assumptions: Completion is provisional until the review surface is dismissed or explicitly confirmed.
    /// 4 - Expectations: Restore preserves identity and returns the thought to deterministic chronological order.
    @Test
    func completedThoughtCanBeRestoredInSession() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let repository = HomewardRepository(directoryURL: fixture.directoryURL)
        let first = try TomorrowNote(
            id: UUID(
                uuidString: "00000000-0000-0000-0000-000000000001"
            )!,
            text: "First",
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let second = try TomorrowNote(
            id: UUID(
                uuidString: "00000000-0000-0000-0000-000000000002"
            )!,
            text: "Second",
            createdAt: Date(timeIntervalSince1970: 2)
        )
        _ = try await repository.saveNotes(
            NotesDocument(notes: [first, second])
        )
        let model = try AppModel(
            repository: repository,
            catalogDiscoverer: { [] }
        )
        await model.start()
        await waitForNotesLoad(model)

        let completed = try #require(
            await model.completeNote(id: first.id)
        )
        #expect(model.notes.notes == [second])
        #expect(await model.restoreNote(completed))

        #expect(model.notes.notes == [first, second])
    }
}

/// 1 - Name: Notes mutation gate.
/// 2 - Description: Suspends one note save and records when reset reaches persistence.
/// 3 - Assumptions: The app model serializes both operations before invoking these closures.
/// 4 - Expectations: Tests can prove reset does not overtake an in-flight save.
private actor NotesMutationGate {
    private var saveStarted = false
    private var saveContinuation: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var didReset = false

    func save(_ notes: NotesDocument) async throws -> NotesDocument {
        saveStarted = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            saveContinuation = continuation
        }
        return notes
    }

    func reset() {
        didReset = true
    }

    func waitUntilSaveStarts() async {
        guard !saveStarted else {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func releaseSave() {
        saveContinuation?.resume()
        saveContinuation = nil
    }
}

/// 1 - Name: Catalog discovery gate.
/// 2 - Description: Suspends the first catalog scan and returns a distinct result for the rerun.
/// 3 - Assumptions: Catalog refresh work executes on the main actor and may reenter while suspended.
/// 4 - Expectations: Tests can distinguish stale publication from latest-result publication.
@MainActor
private final class CatalogDiscoveryGate {
    private var firstDiscoveryContinuation:
        CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var discoveryCount = 0

    func discover() async -> [CatalogApplication] {
        discoveryCount += 1
        if discoveryCount == 1 {
            let waiters = startWaiters
            startWaiters.removeAll()
            waiters.forEach { $0.resume() }
            await withCheckedContinuation { continuation in
                firstDiscoveryContinuation = continuation
            }
            return [application(named: "Stale")]
        }
        return [application(named: "Latest")]
    }

    func waitUntilFirstDiscoveryStarts() async {
        guard discoveryCount == 0 else {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func releaseFirstDiscovery() {
        firstDiscoveryContinuation?.resume()
        firstDiscoveryContinuation = nil
    }

    private func application(named name: String) -> CatalogApplication {
        CatalogApplication(
            id: "test.\(name)",
            selection: SelectedApplication(
                bundleIdentifier: "test.\(name)",
                bundlePath: "/Applications/\(name).app",
                displayName: name
            ),
            icon: NSImage(size: NSSize(width: 16, height: 16))
        )
    }
}

/// 1 - Name: Notification handler spy.
/// 2 - Description: Provides a no-op main-actor notification action target for service lifecycle tests.
/// 3 - Assumptions: Shutdown tests do not need to route a real notification action.
/// 4 - Expectations: The service can install and clear a production-shaped weak delegate safely.
@MainActor
private final class NotificationHandlerSpy: HomewardNotificationHandling {
    func handleNotificationAction(
        _ identifier: String,
        context: WarningActionContext?
    ) {}
}

/// 1 - Name: Warning-center recorder.
/// 2 - Description: Models pending warning requests while allowing the first add to complete out of order.
/// 3 - Assumptions: Notification service client callbacks are main-actor isolated in production and tests.
/// 4 - Expectations: Tests can verify stale cleanup, authorization cleanup, and latest-wins scheduling deterministically.
@MainActor
private final class WarningClientRecorder {
    private let authorizationStatus:
        HomewardNotificationService.AuthorizationStatus
    private var shouldSuspendFirstAdd: Bool
    private var firstAddContinuation:
        CheckedContinuation<Void, Never>?
    private var addStartWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var pendingIdentifiers: Set<String>
    private(set) var deliveredIdentifiers: Set<String>
    private(set) var addedBodies: [String] = []

    init(
        authorizationStatus:
            HomewardNotificationService.AuthorizationStatus = .authorized,
        pendingIdentifiers: Set<String> = [],
        deliveredIdentifiers: Set<String> = [],
        suspendFirstAdd: Bool = true
    ) {
        self.authorizationStatus = authorizationStatus
        self.pendingIdentifiers = pendingIdentifiers
        self.deliveredIdentifiers = deliveredIdentifiers
        shouldSuspendFirstAdd = suspendFirstAdd
    }

    var client: HomewardNotificationService.Client {
        HomewardNotificationService.Client(
            authorizationStatus: { [self] in authorizationStatus },
            requestAuthorization: { true },
            add: { [self] request in
                try await add(request)
            },
            pendingWarningIdentifiers: { [self] in
                Array(pendingIdentifiers)
            },
            deliveredWarningIdentifiers: { [self] in
                Array(deliveredIdentifiers)
            },
            removePending: { [self] identifiers in
                pendingIdentifiers.subtract(identifiers)
            },
            removeDelivered: { [self] identifiers in
                deliveredIdentifiers.subtract(identifiers)
            },
            setCategories: { _ in },
            setDelegate: { _ in }
        )
    }

    func waitUntilFirstAddStarts() async {
        guard shouldSuspendFirstAdd else {
            return
        }
        await withCheckedContinuation { continuation in
            addStartWaiters.append(continuation)
        }
    }

    func releaseFirstAdd() {
        firstAddContinuation?.resume()
        firstAddContinuation = nil
    }

    private func add(_ request: UNNotificationRequest) async throws {
        if shouldSuspendFirstAdd {
            shouldSuspendFirstAdd = false
            let waiters = addStartWaiters
            addStartWaiters.removeAll()
            waiters.forEach { $0.resume() }
            await withCheckedContinuation { continuation in
                firstAddContinuation = continuation
            }
        }
        pendingIdentifiers.insert(request.identifier)
        addedBodies.append(request.content.body)
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

/// 1 - Name: Catalog fixture error.
/// 2 - Description: Represents deterministic application-discovery failure.
/// 3 - Assumptions: Discovery failures are distinct from successful empty results.
/// 4 - Expectations: Tests can verify fail-open catalog recovery state.
private enum CatalogFixtureError: Error {
    case discoveryFailed
}

/// 1 - Name: Catalog application fixture.
/// 2 - Description: Builds a display-ready application descriptor without touching an installed app.
/// 3 - Assumptions: Catalog reconciliation consumes immutable metadata and does not control candidates.
/// 4 - Expectations: Tests can model duplicate bundle identifiers at distinct paths.
@MainActor
private func catalogApplication(
    named name: String,
    bundleIdentifier: String,
    path: String
) -> CatalogApplication {
    CatalogApplication(
        id: path,
        selection: SelectedApplication(
            bundleIdentifier: bundleIdentifier,
            bundlePath: path,
            displayName: name
        ),
        icon: NSImage(size: NSSize(width: 16, height: 16))
    )
}

/// 1 - Name: Notes-load completion helper.
/// 2 - Description: Waits for the independently owned notes bootstrap task to publish a terminal health state.
/// 3 - Assumptions: Isolated test repositories complete reads without external blocking.
/// 4 - Expectations: Tests observe available or unavailable notes state without timing sleeps.
@MainActor
private func waitForNotesLoad(_ model: AppModel) async {
    while model.notesHealth == .loading {
        await Task.yield()
    }
}

/// 1 - Name: Deterministic elapsed clock.
/// 2 - Description: Advances monotonic test time whenever production code requests a sleep.
/// 3 - Assumptions: Tests execute clock access on the main actor.
/// 4 - Expectations: Grace and shutdown bounds can be tested without wall-clock delays.
@MainActor
private final class TestElapsedClock {
    private var instant = ContinuousClock().now
    private(set) var totalSlept: Duration = .zero

    var clock: ElapsedClock {
        ElapsedClock(
            now: { [self] in instant },
            sleep: { [self] duration in
                totalSlept += duration
                instant = instant.advanced(by: duration)
                await Task.yield()
            }
        )
    }
}

/// 1 - Name: Repository fixture failure.
/// 2 - Description: Provides a deterministic storage-resolution failure.
/// 3 - Assumptions: The app model treats repository access errors as recoverable.
/// 4 - Expectations: Tests can exercise startup recovery without filesystem mutation.
private enum RepositoryFixtureError: Error {
    case unavailable
}

/// 1 - Name: Application-model filesystem fixture.
/// 2 - Description: Allocates a unique temporary repository location for each test.
/// 3 - Assumptions: No production data is stored beneath the generated path.
/// 4 - Expectations: Cleanup removes all configuration and note artifacts created by a test.
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
