import AppKit
import Foundation
import Testing
@testable import Homeward
import HomewardCore

// 1 - Name: Homeward application-model test file.
// 2 - Description: Verifies model startup generations, mutation/load serialization, recovery, catalog reconciliation, notes, and runtime safety policy.
// 3 - Assumptions: Tests use isolated repositories, injected adapters, and no running application control targets.
// 4 - Expectations: Model operations preserve fail-open behavior, serialize persistence, and maintain policy invariants.

/// 1 - Name: Homeward application-model suite.
/// 2 - Description: Covers app composition, bootstrap ordering, recovery, catalog state, notes behavior, and safety-action ordering.
/// 3 - Assumptions: Repository creation does not write until an explicit save and all fixtures are isolated.
/// 4 - Expectations: Startup and mutation failures remain recoverable while runtime safety actions apply immediately.
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

    /// 1 - Name: Session-only termination identity matching.
    /// 2 - Description: Distinguishes an exact process session from a reused process identifier without PID fallback.
    /// 3 - Assumptions: Every actionable termination event must include its launch-derived session identity.
    /// 4 - Expectations: Only an exact nonnil session matches.
    @Test
    func terminationIdentityRequiresExactSession() {
        let expected = ProcessSessionID(rawValue: "42-original")
        let replacement = ProcessSessionID(rawValue: "42-replacement")

        #expect(AppModel.terminationMatches(
            expectedSessionID: expected,
            terminatedSessionID: expected
        ))
        #expect(!AppModel.terminationMatches(
            expectedSessionID: expected,
            terminatedSessionID: replacement
        ))
        #expect(!AppModel.terminationMatches(
            expectedSessionID: expected,
            terminatedSessionID: nil
        ))
        #expect(!AppModel.terminationMatches(
            expectedSessionID: nil,
            terminatedSessionID: expected
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

    /// 1 - Name: Startup notes load loses to reset.
    /// 2 - Description: Resets Saved Thoughts while the independently owned startup read remains suspended.
    /// 3 - Assumptions: The persistence read can finish after cancellation and reset shares the notes mutation gate.
    /// 4 - Expectations: Reset waits for the read boundary and the stale document is never published afterward.
    @Test
    func startupNotesLoadCannotPublishAfterReset() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let loadGate = NotesLoadRaceGate(
            firstDocument: try NotesDocument(
                notes: [TomorrowNote(text: "Stale startup thought")]
            )
        )
        let mutationGate = NotesMutationGate()
        let model = try AppModel(
            repository: HomewardRepository(directoryURL: fixture.directoryURL),
            catalogDiscoverer: { [] },
            notesLoader: { await loadGate.load() },
            notesResetter: { await mutationGate.reset() }
        )
        await model.start()
        await loadGate.waitUntilFirstLoadStarts()

        let reset = Task { @MainActor in
            await model.resetSavedThoughts()
        }
        await Task.yield()
        #expect(!(await mutationGate.didReset))

        await loadGate.releaseFirstLoad()
        #expect(await reset.value)
        #expect(await mutationGate.didReset)
        #expect(model.notes.notes.isEmpty)
        #expect(model.notesHealth == .available)
    }

    /// 1 - Name: Retry notes load supersedes startup.
    /// 2 - Description: Starts Retry while the original startup notes read remains suspended.
    /// 3 - Assumptions: The first read ignores cancellation and a second read returns a newer document.
    /// 4 - Expectations: Retry waits for serialization and publishes only its current-generation result.
    @Test
    func retryNotesLoadPublishesOnlyCurrentGeneration() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let loadGate = NotesLoadRaceGate(
            firstDocument: try NotesDocument(
                notes: [TomorrowNote(text: "Stale startup thought")]
            ),
            retryDocument: try NotesDocument(
                notes: [TomorrowNote(text: "Current retry thought")]
            )
        )
        let model = try AppModel(
            repository: HomewardRepository(directoryURL: fixture.directoryURL),
            catalogDiscoverer: { [] },
            notesLoader: { await loadGate.load() }
        )
        await model.start()
        await loadGate.waitUntilFirstLoadStarts()

        let retry = Task { @MainActor in
            await model.retryNotesLoad()
        }
        await Task.yield()
        await loadGate.releaseFirstLoad()

        #expect(await retry.value)
        #expect(await loadGate.loadCount == 2)
        #expect(model.notes.notes.map(\.text) == ["Current retry thought"])
        #expect(model.notesHealth == .available)
    }

    /// 1 - Name: Startup notes load loses to restore.
    /// 2 - Description: Restores a validated backup while the original startup notes read remains suspended.
    /// 3 - Assumptions: The repository contains a previous valid document and the injected first read returns stale content.
    /// 4 - Expectations: Restore wins the shared mutation boundary and stale startup content cannot replace it.
    @Test
    func startupNotesLoadCannotPublishAfterRestore() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let repository = HomewardRepository(directoryURL: fixture.directoryURL)
        _ = try await repository.saveNotes(
            NotesDocument(notes: [TomorrowNote(text: "Restored thought")])
        )
        _ = try await repository.saveNotes(
            NotesDocument(notes: [TomorrowNote(text: "Current thought")])
        )
        let loadGate = NotesLoadRaceGate(
            firstDocument: try NotesDocument(
                notes: [TomorrowNote(text: "Stale startup thought")]
            )
        )
        let model = try AppModel(
            repository: repository,
            catalogDiscoverer: { [] },
            notesLoader: { await loadGate.load() }
        )
        await model.start()
        await loadGate.waitUntilFirstLoadStarts()

        let restore = Task { @MainActor in
            await model.restorePreviousNotes()
        }
        await Task.yield()
        await loadGate.releaseFirstLoad()

        #expect(await restore.value)
        #expect(model.notes.notes.map(\.text) == ["Restored thought"])
        #expect(model.notesHealth == .available)
    }

    /// 1 - Name: Startup notes load loses to shutdown.
    /// 2 - Description: Completes a cancellation-insensitive startup read after bounded termination preparation returns.
    /// 3 - Assumptions: Shutdown invalidates note generations and waits only for its documented monotonic bound.
    /// 4 - Expectations: Late notes never publish after shutdown even though persistence eventually returns them.
    @Test
    func startupNotesLoadCannotPublishAfterShutdown() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let testClock = TestElapsedClock()
        let loadGate = NotesLoadRaceGate(
            firstDocument: try NotesDocument(
                notes: [TomorrowNote(text: "Late shutdown thought")]
            )
        )
        let model = try AppModel(
            repository: HomewardRepository(directoryURL: fixture.directoryURL),
            elapsedClock: testClock.clock,
            catalogDiscoverer: { [] },
            notesLoader: { await loadGate.load() }
        )
        await model.start()
        await loadGate.waitUntilFirstLoadStarts()

        await model.prepareForTermination()
        await loadGate.releaseFirstLoad()
        await loadGate.waitUntilFirstLoadFinishes()
        while model.hasPrioritySaveOrErrorPresentation {
            await Task.yield()
        }

        #expect(model.notes.notes.isEmpty)
        #expect(model.notesHealth == .loading)
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

    /// 1 - Name: Cancelled bootstrap is not discovery failure.
    /// 2 - Description: Cancels a suspended catalog discovery before starting a replacement bootstrap generation.
    /// 3 - Assumptions: Task cancellation is control flow rather than evidence that application discovery failed.
    /// 4 - Expectations: Cancellation publishes no unavailable health or discovery error and the retry reaches ready.
    @Test
    func cancelledBootstrapDoesNotPublishDiscoveryFailure() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let gate = CancellableBootstrapDiscoveryGate()
        let model = try AppModel(
            repository: HomewardRepository(directoryURL: fixture.directoryURL),
            catalogDiscoverer: { try await gate.discover() }
        )
        let first = Task { @MainActor in
            await model.start()
        }
        await gate.waitUntilFirstDiscoveryStarts()

        first.cancel()
        _ = await first.value

        #expect(model.health == .starting)
        #expect(model.catalogHealth == .loading)
        #expect(model.lastError == nil)

        var retryTask: Task<Void, Never>?
        model.installBootstrapRetryHandler {
            retryTask = Task { @MainActor in
                await model.start()
            }
        }
        model.markStartupDelayed()
        model.retryStartup()
        await retryTask?.value

        #expect(model.health == .ready)
        #expect(model.catalogHealth == .available)
        #expect(model.lastError == nil)
    }

    /// 1 - Name: Retry generation defeats stale discovery failure.
    /// 2 - Description: Starts a retry before releasing an older discovery that then fails out of order.
    /// 3 - Assumptions: The replacement generation can queue while the first catalog refresh owns discovery.
    /// 4 - Expectations: Obsolete failure publishes neither health nor error and successful retry clears discovery error state.
    @Test
    func successfulBootstrapRetryWinsStaleDiscoveryFailure() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let gate = BootstrapFailureOrderingGate()
        let model = try AppModel(
            repository: HomewardRepository(directoryURL: fixture.directoryURL),
            catalogDiscoverer: { try await gate.discover() }
        )
        let first = Task { @MainActor in
            await model.start()
        }
        await gate.waitUntilFirstDiscoveryStarts()
        var retryTask: Task<Void, Never>?
        model.installBootstrapRetryHandler {
            retryTask = Task { @MainActor in
                await model.start()
            }
        }

        model.markStartupDelayed()
        model.retryStartup()
        await Task.yield()
        gate.releaseFirstDiscovery()
        _ = await first.value
        await retryTask?.value

        #expect(model.health == .ready)
        #expect(model.catalogHealth == .available)
        #expect(model.lastError == nil)
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
