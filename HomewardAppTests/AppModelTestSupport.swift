import AppKit
import Foundation
import UserNotifications
@testable import Homeward
import HomewardCore

// 1 - Name: Homeward application-model shared test support.
// 2 - Description: Provides deterministic gates, spies, builders, clocks, and filesystem fixtures shared by focused suites.
// 3 - Assumptions: Helpers remain test-only, isolated from user data, and never control installed applications.
// 4 - Expectations: Focused suites share consistent concurrency and persistence fixtures without duplicating setup.

/// 1 - Name: Notes mutation gate.
/// 2 - Description: Suspends one note save and records when reset reaches persistence.
/// 3 - Assumptions: The app model serializes both operations before invoking these closures.
/// 4 - Expectations: Tests can prove reset does not overtake an in-flight save.
actor NotesMutationGate {
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
final class CatalogDiscoveryGate {
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
final class NotificationHandlerSpy: HomewardNotificationHandling {
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
final class WarningClientRecorder {
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
            pendingIdentifiers: { [self] in
                Array(pendingIdentifiers)
            },
            deliveredIdentifiers: { [self] in
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
actor ConfigurationSaveGate {
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
enum CatalogFixtureError: Error {
    case discoveryFailed
}

/// 1 - Name: Catalog application fixture.
/// 2 - Description: Builds a display-ready application descriptor without touching an installed app.
/// 3 - Assumptions: Catalog reconciliation consumes immutable metadata and does not control candidates.
/// 4 - Expectations: Tests can model duplicate bundle identifiers at distinct paths.
@MainActor
func catalogApplication(
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
func waitForNotesLoad(_ model: AppModel) async {
    while model.notesHealth == .loading {
        await Task.yield()
    }
}

/// 1 - Name: Deterministic elapsed clock.
/// 2 - Description: Advances monotonic test time whenever production code requests a sleep.
/// 3 - Assumptions: Tests execute clock access on the main actor.
/// 4 - Expectations: Grace and shutdown bounds can be tested without wall-clock delays.
@MainActor
final class TestElapsedClock {
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
enum RepositoryFixtureError: Error {
    case unavailable
}

/// 1 - Name: Application-model filesystem fixture.
/// 2 - Description: Allocates a unique temporary repository location for each test.
/// 3 - Assumptions: No production data is stored beneath the generated path.
/// 4 - Expectations: Cleanup removes all configuration and note artifacts created by a test.
struct AppModelFixture {
    let directoryURL: URL

    init() {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("HomewardAppModelTests-\(UUID().uuidString)")
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
