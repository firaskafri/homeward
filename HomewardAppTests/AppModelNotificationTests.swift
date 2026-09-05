import Foundation
import Testing
import UserNotifications
@testable import Homeward
import HomewardCore

// 1 - Name: Homeward notification test file.
// 2 - Description: Verifies notification payloads, authorization reconciliation, scheduling races, cleanup, privacy, and model action routing.
// 3 - Assumptions: Notification Center behavior, including request/status races, is represented by an in-memory client and isolated model fixtures.
// 4 - Expectations: Authoritative authorization wins over request errors, only current actions mutate policy, and owned requests clean up deterministically.

/// 1 - Name: Homeward notification suite.
/// 2 - Description: Covers authorization reconciliation, warning payload validation, latest-wins scheduling, lifecycle cleanup, and private copy.
/// 3 - Assumptions: Injected notification callbacks expose authorization races and all pending and delivered identifiers without system access.
/// 4 - Expectations: Current system authorization clears stale errors, while stale or malformed actions fail closed and current actions use shared confirmation.
@Suite("Homeward notifications")
@MainActor
struct AppModelNotificationTests {
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

    /// 1 - Name: Authorized status after request error.
    /// 2 - Description: Reconciles a thrown authorization request whose subsequent system status is authorized.
    /// 3 - Assumptions: Notification Center status is authoritative when its request callback reports a contradictory transient error.
    /// 4 - Expectations: Permission succeeds and no stale error banner remains.
    @Test
    func authorizedStatusOverridesRequestError() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let recorder = WarningClientRecorder(
            authorizationStatus: .notDetermined,
            authorizationStatusAfterRequest: .authorized,
            authorizationRequestError: NSError(
                domain: UNErrorDomain,
                code: 1
            ),
            suspendFirstAdd: false
        )
        let service = HomewardNotificationService(client: recorder.client)
        let model = try AppModel(
            repository: HomewardRepository(directoryURL: fixture.directoryURL),
            notificationService: service
        )
        await model.start()

        let authorized = await model.requestNotificationPermission()

        #expect(authorized)
        #expect(model.notificationStatus == .authorized)
        #expect(model.lastError == nil)
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

    /// 1 - Name: Authorization refresh serialization.
    /// 2 - Description: Queues a newer authorization refresh while an older denied read remains suspended.
    /// 3 - Assumptions: App activation and a manual status check may request refreshes concurrently.
    /// 4 - Expectations: Refreshes execute in request order and the model finishes with the newest authorization state.
    @Test
    func authorizationRefreshesAreSerialized() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let gate = AuthorizationStatusGate()
        let service = HomewardNotificationService(
            client: HomewardNotificationService.Client(
                authorizationStatus: { await gate.status() },
                requestAuthorization: { false },
                add: { _ in },
                pendingIdentifiers: { [] },
                deliveredIdentifiers: { [] },
                removePending: { _ in },
                removeDelivered: { _ in },
                setCategories: { _ in },
                setDelegate: { _ in }
            )
        )
        let model = try AppModel(
            repository: HomewardRepository(
                directoryURL: fixture.directoryURL
            ),
            loginItemService: LoginItemService(
                statusProvider: { .notRegistered }
            ),
            installationLocationService: InstallationLocationService(
                statusProvider: { .applications }
            ),
            notificationService: service
        )
        let olderRefresh = Task { @MainActor in
            await model.refreshSystemStatuses()
        }
        await gate.waitUntilFirstRequestStarts()

        let newerRefresh = Task { @MainActor in
            await model.refreshSystemStatuses()
        }
        await Task.yield()
        await gate.releaseFirstRequest()
        await olderRefresh.value
        await newerRefresh.value

        #expect(model.notificationStatus == .authorized)
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
}
