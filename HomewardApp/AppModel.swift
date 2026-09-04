import AppKit
import Combine
import Foundation
import HomewardCore
import UserNotifications

@MainActor
final class AppModel: NSObject, ObservableObject {
    private static let manualAvailabilityIntervalID = "manual-availability"
    private static let launchMetadataRetryLimit = 4
    private static let terminationSaveWait: Duration = .seconds(2)
    private static let terminationSavePoll: Duration = .milliseconds(25)

    enum PreviewState: Equatable {
        case idle
        case waitingForFirstExit(String)
        case waitingForRelaunch(String)
        case waitingForSecondExit(String)
        case needsAttention(String)
        case complete(String)
    }

    struct ClosingRow: Identifiable, Equatable {
        enum Status: Equatable {
            case requestingNormalQuit
            case countingDown
            case needsAttention
            case forcePaused
            case forceFailed
        }

        let sessionID: ProcessSessionID
        let enforcementIdentity: EnforcementIdentity
        let applicationName: String
        let processIdentifier: Int32
        var status: Status
        var secondsRemaining: Int?

        var id: ProcessSessionID { sessionID }
    }

    enum Health: Equatable {
        case starting
        case startupDelayed
        case ready
        case configurationUnavailable
        case applicationResolutionUnavailable
    }

    enum NotesHealth: Equatable {
        case loading
        case available
        case unavailable
    }

    enum CatalogHealth: Equatable {
        case loading
        case available
        case unavailable
    }

    enum PolicyConfirmationIntent: Equatable {
        case endWorkNow
        case gentleShortcutExtension
        case resumeFirmClosing

        var title: String {
            switch self {
            case .endWorkNow:
                "End work now?"
            case .gentleShortcutExtension:
                "Make all work apps available for 10 minutes?"
            case .resumeFirmClosing:
                "Resume Firm Closing?"
            }
        }

        var actionTitle: String {
            switch self {
            case .endWorkNow:
                "End Work Now"
            case .gentleShortcutExtension:
                "Make Work Apps Available"
            case .resumeFirmClosing:
                "Resume Firm Closing"
            }
        }

        func message(closeMode: CloseMode) -> String {
            switch self {
            case .endWorkNow:
                "Homeward will begin \(SchedulePresentation.closeModeName(closeMode)) for selected work apps."
            case .gentleShortcutExtension:
                "This today-only change makes all selected work apps available for 10 minutes."
            case .resumeFirmClosing:
                "Homeward will ask selected apps to quit normally and begin a new "
                    + "\(HomewardPolicy.firmGracePeriodDescription) grace period."
            }
        }
    }

    enum AttentionDestination: Equatable {
        case workApps
        case savedThoughts
        case settings
    }

    private enum ConfigurationRecoveryOutcome {
        case activate(resetOnboarding: Bool)
        case reject(message: String)
    }

    @Published private(set) var configuration: HomewardConfiguration
    @Published private(set) var notes: NotesDocument
    @Published private(set) var resolvedSchedule: ResolvedSchedule
    @Published private(set) var catalog: [CatalogApplication] = []
    @Published private(set) var catalogHealth: CatalogHealth = .loading
    @Published private(set) var closingRows: [ClosingRow] = []
    @Published private(set) var health: Health = .starting
    @Published private(set) var notesHealth: NotesHealth = .loading
    @Published private(set) var notesRecoveryCandidateAvailable = false
    @Published private(set) var notificationStatus:
        HomewardNotificationService.AuthorizationStatus = .notDetermined
    @Published private(set) var loginItemStatus:
        LoginItemService.Status = .notRegistered
    @Published private(set) var installationLocationStatus:
        InstallationLocationStatus = .unavailable
    @Published private(set) var pendingPolicyConfirmation:
        PolicyConfirmationIntent?
    @Published private(set) var todayExplanation: String?
    @Published private(set) var lastError: String? {
        didSet {
            guard let lastError, oldValue != lastError, let application = NSApp else {
                return
            }
            NSAccessibility.post(
                element: application,
                notification: .announcementRequested,
                userInfo: [
                    .announcement: lastError,
                    .priority: NSAccessibilityPriorityLevel.high.rawValue,
                ]
            )
        }
    }
    @Published private(set) var isSessionActive = false
    @Published private(set) var previewState: PreviewState = .idle
    @Published private(set) var isRecoveryInProgress = false

    private let repository: HomewardRepository
    private let nowProvider: () -> Date
    private let elapsedClock: ElapsedClock
    private let configurationSaver:
        (HomewardConfiguration) async throws -> HomewardConfiguration
    private let notesSaver: (NotesDocument) async throws -> NotesDocument
    private let notesResetter: () async throws -> Void
    private let dateByAdding:
        (Calendar.Component, Int, Date) -> Date?
    private let resolver = ScheduleResolver()
    private let planner = EnforcementPlanner()
    private let countdownAnnouncementPolicy = CountdownAnnouncementPolicy()
    private let workspaceMonitor = WorkspaceMonitor()
    private let runningController: RunningApplicationController
    private let appCatalog: ApplicationCatalog
    private let catalogDiscoverer: () async throws -> [CatalogApplication]
    private let loginItemService: LoginItemService
    private let installationLocationService: InstallationLocationService
    private let notificationService: HomewardNotificationService
    private var transitionTask: Task<Void, Never>?
    private var notesLoadTask: Task<Void, Never>?
    private var systemStatusTask: Task<Void, Never>?
    private var launchMetadataTasks: [Int32: Task<Void, Never>] = [:]
    private var enforcementTasks: [ProcessSessionID: Task<Void, Never>] = [:]
    private var announcedCountdownMilestones: [ProcessSessionID: Set<Int>] = [:]
    private var gentleExemptProcesses: [ProcessSessionID: Int32] = [:]
    private var runtimeForcePauseIntervalIDs: Set<String> = []
    private var blockedLaunchTargets: [ProcessSessionID: EnforcementTarget] = [:]
    private var lastBlockedFeedbackBySelection: [UUID: Date] = [:]
    private var scheduledCloseHadTarget = false
    private let presentationCoordinator = PresentationCoordinator()
    private var presentedNoteIntervalIDs: Set<String> = []
    private var previewSelectionID: UUID?
    private var previewProcessSessionID: ProcessSessionID?
    private var previewTimeoutTask: Task<Void, Never>?
    private let configurationMutationGate = AsyncMutationGate()
    private var onboardingConfirmationRevision = 0
    private let notesMutationGate = AsyncMutationGate()
    private var catalogRefreshInProgress = false
    private var catalogRefreshRequested = false
    private var catalogRefreshShouldReconcile = false
    private var catalogRefreshWaiters: [CheckedContinuation<Void, Never>] = []
    private var started = false
    private var runtimeActivated = false
    private var isShuttingDown = false
    private var configurationRevision = 0
    private var bootstrapRetryHandler: (() -> Void)?
    private var routeHandler: ((HomewardRoute) -> Void)?
    private var sensitivePresentationDismissalHandler: (() -> Void)?

    init(
        repository: HomewardRepository,
        nowProvider: @escaping () -> Date = Date.init,
        elapsedClock: ElapsedClock = .continuous,
        configurationSaver: (
            (HomewardConfiguration) async throws -> HomewardConfiguration
        )? = nil,
        dateByAdding: @escaping (
            Calendar.Component,
            Int,
            Date
        ) -> Date? = {
            Calendar.autoupdatingCurrent.date(
                byAdding: $0,
                value: $1,
                to: $2
            )
        },
        applicationCatalog: ApplicationCatalog? = nil,
        catalogDiscoverer: (() async throws -> [CatalogApplication])? = nil,
        runningController: RunningApplicationController =
            RunningApplicationController(),
        loginItemService: LoginItemService? = nil,
        installationLocationService: InstallationLocationService? = nil,
        notificationService: HomewardNotificationService? = nil,
        notesSaver: ((NotesDocument) async throws -> NotesDocument)? = nil,
        notesResetter: (() async throws -> Void)? = nil
    ) throws {
        let initialConfiguration = try HomewardConfiguration.initial()
        let resolvedCatalog = applicationCatalog ?? ApplicationCatalog()
        self.repository = repository
        self.nowProvider = nowProvider
        self.elapsedClock = elapsedClock
        self.configurationSaver = configurationSaver ?? { configuration in
            try await repository.saveConfiguration(configuration)
        }
        self.dateByAdding = dateByAdding
        appCatalog = resolvedCatalog
        self.catalogDiscoverer = catalogDiscoverer ?? {
            try await resolvedCatalog.discover()
        }
        self.runningController = runningController
        self.loginItemService = loginItemService ?? LoginItemService()
        self.installationLocationService =
            installationLocationService ?? InstallationLocationService()
        self.notificationService =
            notificationService ?? HomewardNotificationService()
        self.notesSaver = notesSaver ?? { notes in
            try await repository.saveNotes(notes)
        }
        self.notesResetter = notesResetter ?? {
            try await repository.resetNotes()
        }
        configuration = initialConfiguration
        notes = try NotesDocument()
        resolvedSchedule = ScheduleResolver().resolve(
            schedule: initialConfiguration.schedule,
            overrides: initialConfiguration.overrides,
            at: nowProvider(),
            calendar: .autoupdatingCurrent,
            warnings: initialConfiguration.warningPreferences
        )
        super.init()
        workspaceMonitor.delegate = self
    }

    static func makeDefault(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> AppModel {
        let isAutomatedTest = HomewardRuntime.isAutomatedTest(
            environment: environment
        )
        var repositoryEnvironment = environment
        if isAutomatedTest,
           repositoryEnvironment["HOMEWARD_STORAGE_DIRECTORY"] == nil {
            repositoryEnvironment["HOMEWARD_STORAGE_DIRECTORY"] =
                FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "HomewardTestHost-\(ProcessInfo.processInfo.processIdentifier)",
                    isDirectory: true
                )
                .path
        }
        let repository = HomewardRepository(
            environment: repositoryEnvironment
        )
        let runningController = RunningApplicationController(
            controlPolicy: .forRuntime(environment: environment)
        )
        guard isAutomatedTest else {
            return try AppModel(
                repository: repository,
                runningController: runningController
            )
        }
        let uiTestFixture = environment[
            HomewardRuntime.uiTestEnvironmentKey
        ] == "1"
            ? HomewardUITestScenarioFixture(environment: environment)
            : nil
        let model = try AppModel(
            repository: repository,
            catalogDiscoverer: {
                try await uiTestFixture?.discoverApplications() ?? []
            },
            runningController: runningController,
            loginItemService: .isolatedForUITesting(),
            installationLocationService:
                uiTestFixture?.installationLocationService
                ?? InstallationLocationService(
                    statusProvider: { .applications }
                ),
            notificationService: .isolatedForUITesting()
        )
        if uiTestFixture?.beginsInDelayedStartup == true {
            model.markStartupDelayed()
        }
        return model
    }

    var isOnboardingComplete: Bool {
        configuration.completedOnboarding
    }

    var isCatalogLoading: Bool {
        catalogHealth == .loading
    }

    var isPolicyMutationEnabled: Bool {
        health == .ready && !isShuttingDown
    }

    var policyRevision: Int {
        configurationRevision
    }

    var canRevealNoteContent: Bool {
        isSessionActive
            && resolvedSchedule.isAvailable
            && resolvedSchedule.phase != .temporarilyExtended
            && notesHealth == .available
    }

    var availableNotesCount: Int {
        guard notesHealth == .available else {
            return 0
        }
        let intervalID = currentNoteIntervalID
        return notes.notes.count {
            $0.lastPresentedIntervalID != intervalID
        }
    }

    var attentionCount: Int {
        var count = configuration.selectedApplications.count {
            !$0.isResolvable
        }
        if configuration.selectedApplications.isEmpty,
           configuration.completedOnboarding {
            count += 1
        }
        if notificationStatus != .authorized {
            count += 1
        }
        if loginItemStatus != .enabled
            || !installationLocationStatus.supportsStartAtLogin {
            count += 1
        }
        if notesHealth == .unavailable {
            count += 1
        }
        return count
    }

    var presentationSnapshot: HomewardPresentationSnapshot {
        HomewardPresentationSnapshot.resolve(
            health: health,
            onboardingComplete: configuration.completedOnboarding,
            schedule: resolvedSchedule,
            closingCount: closingRows.count,
            forceEscalationPaused: forceEscalationPaused,
            savedThoughtCount: availableNotesCount,
            attentionCount: attentionCount
        )
    }

    var todayActions: [TodayActionPresentation.Action] {
        TodayActionPresentation.actions(
            canExtendToday: canExtendToday,
            isAvailable: resolvedSchedule.isAvailable,
            hasAvailabilityOverride: hasAvailabilityOverride
        )
    }

    var hasPrioritySaveOrErrorPresentation: Bool {
        configurationMutationGate.isInProgress
            || notesMutationGate.isInProgress
            || lastError != nil
    }

    var primaryAttentionDestination: AttentionDestination? {
        if configuration.selectedApplications.isEmpty
            || configuration.selectedApplications.contains(where: {
                !$0.isResolvable
            }) {
            return .workApps
        }
        if notesHealth == .unavailable {
            return .savedThoughts
        }
        if notificationStatus != .authorized
            || loginItemStatus != .enabled
            || !installationLocationStatus.supportsStartAtLogin {
            return .settings
        }
        return nil
    }

    func installBootstrapRetryHandler(_ handler: @escaping () -> Void) {
        bootstrapRetryHandler = handler
    }

    func installRouteHandler(_ handler: @escaping (HomewardRoute) -> Void) {
        routeHandler = handler
    }

    func requestRoute(_ route: HomewardRoute) {
        routeHandler?(route)
    }

    func installSensitivePresentationDismissalHandler(
        _ handler: @escaping () -> Void
    ) {
        sensitivePresentationDismissalHandler = handler
    }

    func markStartupDelayed() {
        guard health == .starting else {
            return
        }
        health = .startupDelayed
    }

    func retryStartup() {
        guard health == .startupDelayed
                || health == .applicationResolutionUnavailable else {
            return
        }
        health = .starting
        lastError = nil
        started = false
        bootstrapRetryHandler?()
    }

    var canExtendToday: Bool {
        !resolvedSchedule.isAvailable || resolvedSchedule.nextTransition != nil
    }

    var hasAvailabilityOverride: Bool {
        let now = nowProvider()
        return configuration.overrides.contains {
            $0.kind != .forceEscalationPaused && $0.isActive(at: now)
        }
    }

    private var requiresImmediateCloseForAppChange: Bool {
        configuration.completedOnboarding
            && !resolveSchedule(at: nowProvider()).isAvailable
    }

    var canUseGentleShortcutExtension: Bool {
        let intervalID = blockedIntervalID(at: nowProvider())
        return configuration.closeMode == .gentle
            && configuration.gentleShortcutExtensionEnabled
            && !resolvedSchedule.isAvailable
            && !configuration.consumedGentleExtensionIntervalIDs.contains(
                intervalID
            )
    }

    var visibleNotes: [TomorrowNote] {
        guard canRevealNoteContent else {
            return []
        }
        let intervalID = currentNoteIntervalID
        return notes.notes.filter {
            $0.lastPresentedIntervalID != intervalID
        }
    }

    var currentNoteIntervalID: String {
        resolvedSchedule.activeBaseInterval?.id
            ?? Self.manualAvailabilityIntervalID
    }

    var forceEscalationPaused: Bool {
        let now = nowProvider()
        let intervalID = blockedIntervalID(at: now)
        return runtimeForcePauseIntervalIDs.contains(intervalID)
            || configuration.overrides.contains {
                $0.kind == .forceEscalationPaused
                    && $0.isActive(at: now)
                    && $0.relatedIntervalID == intervalID
            }
    }

    func start() async {
        guard !started, !runtimeActivated, !isShuttingDown else {
            return
        }
        started = true

        do {
            if let stored = try await repository.loadConfiguration() {
                configuration = stored
            }
            configurationRevision &+= 1
        } catch {
            HomewardLog.persistence.error("Configuration load failed")
            cancelAllEnforcement()
            presentationCoordinator.setRecoveryActive(true)
            await notificationService.removeAllOwned()
            health = .configurationUnavailable
            lastError = "App closing is paused because settings could not be verified."
            return
        }

        guard !Task.isCancelled, !isShuttingDown else {
            return
        }
        await activateRuntime(clearingError: false)
    }

    @discardableResult
    func refreshCatalog(
        reconcileAfterSave: Bool = true
    ) async -> Bool {
        catalogRefreshRequested = true
        catalogRefreshShouldReconcile =
            catalogRefreshShouldReconcile || reconcileAfterSave
        guard !catalogRefreshInProgress else {
            await withCheckedContinuation { continuation in
                catalogRefreshWaiters.append(continuation)
            }
            return catalogHealth == .available
        }

        catalogRefreshInProgress = true
        catalogHealth = .loading
        defer {
            catalogRefreshInProgress = false
            let waiters = catalogRefreshWaiters
            catalogRefreshWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }

        while catalogRefreshRequested {
            catalogRefreshRequested = false
            let shouldReconcile = catalogRefreshShouldReconcile
            catalogRefreshShouldReconcile = false
            let discovered: [CatalogApplication]
            do {
                discovered = try await catalogDiscoverer()
            } catch {
                guard !catalogRefreshRequested else {
                    continue
                }
                HomewardLog.lifecycle.error("Application discovery failed")
                catalogHealth = .unavailable
                lastError =
                    "Applications could not be found. Existing verified app selections were kept."
                return false
            }
            guard !catalogRefreshRequested else {
                continue
            }
            catalog = discovered
            guard await reconcileCatalogSelections(
                reconcileAfterSave: shouldReconcile
            ) else {
                catalogHealth = .unavailable
                return false
            }
            catalogHealth = .available
        }
        return catalogHealth == .available
    }

    private func reconcileCatalogSelections(
        reconcileAfterSave: Bool
    ) async -> Bool {
        await waitForConfigurationSave()
        var updated = configuration
        var changed = false
        for index in updated.selectedApplications.indices {
            let selection = updated.selectedApplications[index]
            let savedURL = URL(fileURLWithPath: selection.bundlePath)
            let savedPathMatch = appCatalog.descriptor(for: savedURL).flatMap {
                descriptor -> CatalogApplication? in
                if let bundleIdentifier = selection.bundleIdentifier {
                    return descriptor.selection.bundleIdentifier == bundleIdentifier
                        ? descriptor
                        : nil
                }
                return descriptor.selection.stableSelectionKey == selection.stableSelectionKey
                    ? descriptor
                    : nil
            }
            let exactCatalogMatch = catalog.first {
                $0.selection.bundlePath == savedURL.standardizedFileURL.path
            }
            let match: CatalogApplication?
            if let bundleIdentifier = selection.bundleIdentifier {
                let candidates = catalog.filter {
                    $0.selection.bundleIdentifier == bundleIdentifier
                }
                if let exact = exactCatalogMatch.flatMap({
                    $0.selection.bundleIdentifier == bundleIdentifier
                        ? $0
                        : nil
                }) {
                    match = exact
                } else if let savedPathMatch {
                    match = savedPathMatch
                } else if candidates.count == 1 {
                    match = candidates[0]
                } else {
                    match = nil
                }
            } else {
                match = exactCatalogMatch ?? savedPathMatch
            }
            let isResolvable = match != nil
            if updated.selectedApplications[index].isResolvable != isResolvable {
                updated.selectedApplications[index].isResolvable = isResolvable
                changed = true
            }
            if let match,
               updated.selectedApplications[index].bundlePath
                != match.selection.bundlePath {
                updated.selectedApplications[index].bundlePath = match.selection.bundlePath
                updated.selectedApplications[index].displayName = match.selection.displayName
                updated.selectedApplications[index].developerName = match.selection.developerName
                changed = true
            }
        }
        if changed {
            return await commit(
                updated,
                reconcileAfterSave: reconcileAfterSave,
                requiresReady: false
            )
        }
        return true
    }

    func refreshSystemStatuses() async {
        notificationStatus = await notificationService.authorizationStatus()
        if notificationStatus != .authorized {
            await notificationService.removeAllOwned()
        }
        loginItemStatus = loginItemService.status
        installationLocationStatus = installationLocationService.status
    }

    @discardableResult
    func requestNotificationPermission() async -> Bool {
        guard isPolicyMutationEnabled else {
            lastError = "Homeward is still starting. No settings were changed."
            return false
        }
        do {
            _ = try await notificationService.requestAuthorization()
            notificationStatus = await notificationService.authorizationStatus()
            if notificationStatus == .authorized {
                await scheduleWarningsIfPossible()
                return true
            }
            await notificationService.removeAllOwned()
            return false
        } catch {
            HomewardLog.lifecycle.error("Notification authorization failed")
            notificationStatus = await notificationService.authorizationStatus()
            if notificationStatus != .authorized {
                await notificationService.removeAllOwned()
            }
            lastError = "Notifications could not be enabled. App closing still works."
            return false
        }
    }

    @discardableResult
    func enableStartAtLogin() -> Bool {
        guard isPolicyMutationEnabled else {
            lastError = "Homeward is still starting. No settings were changed."
            return false
        }
        installationLocationStatus = installationLocationService.status
        switch installationLocationStatus {
        case .applications:
            break
        case .outsideApplications:
            lastError =
                "Move Homeward to Applications before enabling Start at Login."
            return false
        case .unavailable:
            lastError =
                "Homeward could not verify its installation location. Start at Login was not changed."
            return false
        }
        do {
            try loginItemService.enable()
            loginItemStatus = loginItemService.status
            return loginItemStatus == .enabled
        } catch {
            HomewardLog.lifecycle.error("Login-item enable failed")
            loginItemStatus = loginItemService.status
            lastError = "Start at Login could not be enabled."
            return false
        }
    }

    @discardableResult
    func disableStartAtLogin() -> Bool {
        guard isPolicyMutationEnabled else {
            lastError = "Homeward is still starting. No settings were changed."
            return false
        }
        do {
            try loginItemService.disable()
            loginItemStatus = loginItemService.status
            return loginItemStatus == .notRegistered
                || loginItemStatus == .notFound
        } catch {
            HomewardLog.lifecycle.error("Login-item disable failed")
            loginItemStatus = loginItemService.status
            lastError = "Start at Login could not be disabled."
            return false
        }
    }

    func openLoginItemSettings() {
        loginItemService.openSystemSettings()
    }

    func showInstallationInFinder() {
        installationLocationService.showInFinder()
    }

    func openSystemSettings() {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.systempreferences"
        ), NSWorkspace.shared.open(url) else {
            lastError = "System Settings could not be opened."
            return
        }
    }

    @discardableResult
    func completeOnboarding() async -> Bool {
        await waitForConfigurationSave()
        guard !configuration.completedOnboarding else {
            return true
        }
        guard configuration.onboardingScheduleConfirmed,
              configuration.selectedApplications.contains(where: {
                  $0.isResolvable && !$0.isProtected
              }) else {
            lastError =
                "Confirm the schedule and choose at least one available work app."
            return false
        }
        var updated = configuration
        updated.completedOnboarding = true
        if await commit(updated) {
            UserDefaults.standard.set(
                0,
                forKey: HomewardPreferenceKeys.onboardingStep
            )
            return true
        }
        return false
    }

    func markOnboardingScheduleDirty() {
        guard isPolicyMutationEnabled,
              !configuration.completedOnboarding else {
            return
        }
        onboardingConfirmationRevision &+= 1
        configuration.onboardingScheduleConfirmed = false
    }

    func restoreOnboardingScheduleConfirmation() {
        guard isPolicyMutationEnabled,
              !configuration.completedOnboarding else {
            return
        }
        onboardingConfirmationRevision &+= 1
        configuration.onboardingScheduleConfirmed = true
    }

    func startPreview(selectionID: UUID) {
        endPreview()
        guard isPolicyMutationEnabled else {
            lastError = "Homeward is still starting. Preview has not started."
            return
        }
        guard let selection = configuration.selectedApplications.first(
            where: { $0.id == selectionID }
        ) else {
            lastError = "Choose a selected application for the preview."
            return
        }
        let snapshots = runningController.snapshots(workspaceMonitor.runningApplications)
        guard let target = planner.targets(
            selections: [selection],
            runningApplications: snapshots
        ).first else {
            lastError = "Open \(selection.displayName), then try the preview again."
            previewState = .needsAttention(selection.displayName)
            return
        }
        previewSelectionID = selectionID
        previewProcessSessionID = target.id
        let accepted = runningController.requestNormalTermination(for: target.id)
        previewState = accepted
            ? .waitingForFirstExit(selection.displayName)
            : .needsAttention(selection.displayName)
        schedulePreviewTimeout(applicationName: selection.displayName)
    }

    func endPreview() {
        previewTimeoutTask?.cancel()
        previewTimeoutTask = nil
        previewSelectionID = nil
        previewProcessSessionID = nil
        previewState = .idle
    }

    func showPreviewApplication() {
        guard let previewProcessSessionID else {
            lastError = "The preview application is no longer running."
            return
        }
        guard runningController.activate(
            sessionID: previewProcessSessionID
        ) else {
            lastError = "The preview application is no longer available."
            return
        }
    }

    @discardableResult
    func setCloseMode(_ mode: CloseMode) async -> Bool {
        await waitForConfigurationSave()
        guard configuration.closeMode != mode else {
            return true
        }
        var updated = configuration
        updated.closeMode = mode
        if await commit(updated, reconcileAfterSave: false) {
            cancelAllEnforcement()
            await reconcile(runningApplications: workspaceMonitor.runningApplications)
            return true
        } else {
            await reconcile(runningApplications: workspaceMonitor.runningApplications)
            return false
        }
    }

    @discardableResult
    func setWarning(_ option: WarningLeadTime, enabled: Bool) async -> Bool {
        await waitForConfigurationSave()
        var updated = configuration
        switch option {
        case .fifteenMinute:
            updated.warningPreferences.fifteenMinuteWarningEnabled = enabled
        case .fiveMinute:
            updated.warningPreferences.fiveMinuteWarningEnabled = enabled
        }
        return await commit(updated)
    }

    @discardableResult
    func setGentleShortcutExtensionEnabled(_ enabled: Bool) async -> Bool {
        await waitForConfigurationSave()
        var updated = configuration
        updated.gentleShortcutExtensionEnabled = enabled
        return await commit(updated)
    }

    @discardableResult
    func setSchedule(
        _ schedule: WeeklySchedule,
        expectedRevision: Int? = nil,
        confirmsImmediateClose: Bool = false
    ) async -> Bool {
        await waitForConfigurationSave()
        guard expectedRevision == nil
                || expectedRevision == configurationRevision else {
            lastError =
                "These schedule changes are based on older settings. Review the current schedule and try again."
            return false
        }
        guard confirmsImmediateClose
                || !scheduleChangeRequiresImmediateClose(schedule) else {
            lastError =
                "This change now makes work unavailable. Confirm the closing consequence before saving."
            return false
        }
        var updated = configuration
        updated.schedule = schedule
        if !updated.completedOnboarding {
            updated.onboardingScheduleConfirmed = true
        }
        return await commit(
            updated,
            expectedRevision: expectedRevision
        )
    }

    func scheduleChangeRequiresImmediateClose(
        _ schedule: WeeklySchedule
    ) -> Bool {
        guard configuration.completedOnboarding,
              resolvedSchedule.isAvailable else {
            return false
        }
        return !resolveSchedule(
            schedule: schedule,
            at: nowProvider()
        ).isAvailable
    }

    @discardableResult
    func addApplication(
        _ application: SelectedApplication,
        expectedRevision: Int? = nil,
        confirmsImmediateClose: Bool = false
    ) async -> Bool {
        await waitForConfigurationSave()
        guard expectedRevision == nil
                || expectedRevision == configurationRevision else {
            lastError =
                "The work-app list changed. Review the current list and try again."
            return false
        }
        guard confirmsImmediateClose || !requiresImmediateCloseForAppChange else {
            lastError =
                "Work is now closed. Confirm the closing consequence before adding this app."
            return false
        }
        guard !application.isProtected else {
            lastError = "That system application cannot be managed by Homeward."
            return false
        }
        guard !configuration.selectedApplications.contains(where: {
            $0.stableSelectionKey == application.stableSelectionKey
        }) else {
            lastError = "\(application.displayName) is already selected."
            return false
        }
        var updated = configuration
        updated.selectedApplications.append(application)
        return await commit(
            updated,
            expectedRevision: expectedRevision
        )
    }

    @discardableResult
    func removeApplication(
        id: UUID,
        expectedRevision: Int? = nil
    ) async -> Bool {
        await waitForConfigurationSave()
        guard expectedRevision == nil
                || expectedRevision == configurationRevision else {
            lastError =
                "The work-app list changed. Review the current list and try again."
            return false
        }
        var updated = configuration
        updated.selectedApplications.removeAll(where: { $0.id == id })
        if await commit(
            updated,
            expectedRevision: expectedRevision
        ) == false {
            await reconcile(
                runningApplications: workspaceMonitor.runningApplications
            )
            return false
        }
        return true
    }

    @discardableResult
    func addApplication(
        at url: URL,
        expectedRevision: Int? = nil,
        confirmsImmediateClose: Bool = false
    ) async -> Bool {
        guard let descriptor = appCatalog.descriptor(for: url) else {
            lastError = "The selected item is not a supported application."
            return false
        }
        return await addApplication(
            descriptor.selection,
            expectedRevision: expectedRevision,
            confirmsImmediateClose: confirmsImmediateClose
        )
    }

    @discardableResult
    func replaceApplication(
        id: UUID,
        with url: URL,
        expectedRevision: Int? = nil,
        confirmsImmediateClose: Bool = false
    ) async -> Bool {
        await waitForConfigurationSave()
        guard expectedRevision == nil
                || expectedRevision == configurationRevision else {
            lastError =
                "The work-app list changed. Review the current list and try again."
            return false
        }
        guard confirmsImmediateClose || !requiresImmediateCloseForAppChange else {
            lastError =
                "Work is now closed. Confirm the closing consequence before repairing this app."
            return false
        }
        guard let descriptor = appCatalog.descriptor(for: url),
              let index = configuration.selectedApplications.firstIndex(
                  where: { $0.id == id }
              ) else {
            lastError = "The selected item cannot replace this work app."
            return false
        }
        let replacement = SelectedApplication(
            id: id,
            bundleIdentifier: descriptor.selection.bundleIdentifier,
            bundlePath: descriptor.selection.bundlePath,
            displayName: descriptor.selection.displayName,
            developerName: descriptor.selection.developerName,
            isResolvable: true
        )
        var updated = configuration
        updated.selectedApplications[index] = replacement
        return await commit(
            updated,
            expectedRevision: expectedRevision
        )
    }

    @discardableResult
    func createExtension(minutes: Int) async -> Bool {
        await waitForConfigurationSave()
        guard HomewardPolicy.extensionDurationsMinutes.contains(minutes) else {
            lastError = "Choose a supported extension duration."
            return false
        }
        let now = nowProvider()
        let extensionBase: Date
        if resolvedSchedule.isAvailable,
           let transition = resolvedSchedule.nextTransition {
            extensionBase = max(now, transition.date)
        } else {
            extensionBase = now
        }
        guard let expiresAt = dateByAdding(
            .minute,
            minutes,
            extensionBase
        ) else {
            lastError = "The extension could not be created."
            return false
        }
        do {
            let scheduleOverride = try ScheduleOverride(
                kind: .fixedExtension,
                effect: .allow,
                effectiveAt: now,
                expiresAt: expiresAt
            )
            var updated = configuration
            updated.replaceUnexpiredAvailabilityOverrides(
                with: [scheduleOverride],
                at: now
            )
            return await commit(updated)
        } catch {
            lastError = "The extension could not be created."
            return false
        }
    }

    @discardableResult
    func useGentleShortcutExtension() async -> Bool {
        await waitForConfigurationSave()
        guard configuration.closeMode == .gentle,
              configuration.gentleShortcutExtensionEnabled else {
            return false
        }
        let intervalID = currentOrUpcomingBlockedIntervalID()
        guard !configuration.consumedGentleExtensionIntervalIDs.contains(intervalID) else {
            lastError = "The one-time Gentle extension has already been used for this blocked period."
            return false
        }
        let now = nowProvider()
        let extensionBase = resolvedSchedule.isAvailable
            ? max(now, resolvedSchedule.nextTransition?.date ?? now)
            : now
        guard let expiry = dateByAdding(
            .minute,
            HomewardPolicy.gentleShortcutExtensionMinutes,
            extensionBase
        ) else {
            lastError = "The Gentle extension could not be created."
            return false
        }
        do {
            let extensionOverride = try ScheduleOverride(
                kind: .fixedExtension,
                effect: .allow,
                effectiveAt: now,
                expiresAt: expiry,
                relatedIntervalID: intervalID
            )
            var updated = configuration
            try updated.markGentleExtensionConsumed(in: intervalID)
            updated.replaceUnexpiredAvailabilityOverrides(
                with: [extensionOverride],
                at: now
            )
            return await commit(updated)
        } catch {
            lastError = "The Gentle extension could not be created."
            return false
        }
    }

    @discardableResult
    func endWorkNow() async -> Bool {
        await waitForConfigurationSave()
        let now = nowProvider()
        let calendar = Calendar.autoupdatingCurrent
        let expiry = availabilityOverrideExpiry(after: now, calendar: calendar)
        do {
            let scheduleOverride = try ScheduleOverride(
                kind: .endWorkNow,
                effect: .block,
                effectiveAt: now,
                expiresAt: expiry
            )
            var updated = configuration
            updated.replaceActiveAvailabilityOverrides(
                with: [scheduleOverride],
                at: now
            )
            return await commit(updated)
        } catch {
            lastError = "Work could not be ended early."
            return false
        }
    }

    func requestPolicyConfirmation(
        _ intent: PolicyConfirmationIntent,
        routeToToday: Bool = false
    ) {
        todayExplanation = nil
        pendingPolicyConfirmation = intent
        if routeToToday {
            routeHandler?(.today)
        }
    }

    func cancelPolicyConfirmation() {
        pendingPolicyConfirmation = nil
    }

    @discardableResult
    func confirmPolicyAction() async -> Bool {
        guard let intent = pendingPolicyConfirmation else {
            return false
        }
        pendingPolicyConfirmation = nil
        switch intent {
        case .endWorkNow:
            return await endWorkNow()
        case .gentleShortcutExtension:
            return await useGentleShortcutExtension()
        case .resumeFirmClosing:
            await resumeFirmClosing()
            return !forceEscalationPaused
        }
    }

    @discardableResult
    func makeWorkAvailableNow() async -> Bool {
        await waitForConfigurationSave()
        let now = nowProvider()
        let calendar = Calendar.autoupdatingCurrent
        let expiry = availabilityOverrideExpiry(after: now, calendar: calendar)
        return await applyAvailabilityOverride(
            kind: .makeAvailable,
            effect: .allow,
            effectiveAt: now,
            expiresAt: expiry
        )
    }

    @discardableResult
    func chooseCutoff(_ cutoff: Date) async -> Bool {
        await waitForConfigurationSave()
        let now = nowProvider()
        let calendar = Calendar.autoupdatingCurrent
        let nextLocalMidnight = resolver.nextLocalDayBoundary(
            after: now,
            calendar: calendar
        )
        guard cutoff > now else {
            lastError = "Choose a cutoff later than the current time."
            return false
        }
        guard cutoff <= nextLocalMidnight else {
            lastError = "Choose a cutoff before the end of the current local day."
            return false
        }
        let blockedUntil = availabilityOverrideExpiry(
            after: cutoff,
            calendar: calendar
        )
        do {
            let allow = try ScheduleOverride(
                kind: .customCutoff,
                effect: .allow,
                effectiveAt: now,
                expiresAt: cutoff
            )
            let block = try ScheduleOverride(
                kind: .customCutoff,
                effect: .block,
                effectiveAt: cutoff,
                expiresAt: blockedUntil
            )
            var updated = configuration
            updated.replaceUnexpiredAvailabilityOverrides(
                with: [allow, block],
                at: now
            )
            return await commit(updated)
        } catch {
            lastError = "The custom cutoff could not be saved."
            return false
        }
    }

    @discardableResult
    func takeTodayOff() async -> Bool {
        await waitForConfigurationSave()
        let now = nowProvider()
        let calendar = Calendar.autoupdatingCurrent
        let tomorrow = resolver.nextLocalDayBoundary(
            after: now,
            calendar: calendar
        )
        let intervals = resolver.intervals(
            for: configuration.schedule,
            around: now,
            calendar: calendar
        )
        let expiry = intervals.first(where: { $0.start >= tomorrow })?.start
            ?? tomorrow
        return await applyAvailabilityOverride(
            kind: .takeDayOff,
            effect: .block,
            effectiveAt: now,
            expiresAt: expiry
        )
    }

    @discardableResult
    func returnToWeeklySchedule() async -> Bool {
        await waitForConfigurationSave()
        var updated = configuration
        updated.clearAvailabilityOverrides()
        return await commit(updated)
    }

    func stopForceQuit() async {
        let requestedAt = nowProvider()
        let requestedIntervalID = blockedIntervalID(at: requestedAt)
        runtimeForcePauseIntervalIDs.insert(requestedIntervalID)
        cancelEnforcementTasks()
        announcedCountdownMilestones.removeAll()
        closingRows = closingRows.map { row in
            var updated = row
            if updated.status == .countingDown {
                updated.status = .forcePaused
                updated.secondsRemaining = nil
            }
            return updated
        }

        await waitForConfigurationSave()
        let now = nowProvider()
        guard blockedIntervalID(at: now) == requestedIntervalID else {
            return
        }
        let expiry = pausedForceOverrideExpiry(at: now)
        do {
            let pause = try ScheduleOverride(
                kind: .forceEscalationPaused,
                effect: .unchanged,
                effectiveAt: now,
                expiresAt: expiry,
                relatedIntervalID: requestedIntervalID
            )
            var updated = configuration
            updated.setForceEscalationPause(pause)
            if await commit(updated, reconcileAfterSave: false) == false {
                lastError = "Force quit is paused while Homeward remains open, but the pause could not be saved."
            }
        } catch {
            lastError = "Force quit is paused while Homeward remains open, but the pause could not be saved."
        }
    }

    func resumeFirmClosing() async {
        await waitForConfigurationSave()
        var updated = configuration
        updated.clearForceEscalationPause()
        if await commit(updated, reconcileAfterSave: false) {
            runtimeForcePauseIntervalIDs.remove(
                blockedIntervalID(at: nowProvider())
            )
            cancelAllEnforcement()
            await reconcile(runningApplications: workspaceMonitor.runningApplications)
        }
    }

    func bringForward(sessionID: ProcessSessionID) {
        guard runningController.activate(sessionID: sessionID) else {
            lastError = "The application is no longer available."
            removeClosingRow(sessionID: sessionID)
            return
        }
    }

    func leaveOpen(sessionID: ProcessSessionID) {
        enforcementTasks[sessionID]?.cancel()
        enforcementTasks.removeValue(forKey: sessionID)
        if let processIdentifier = closingRows.first(
            where: { $0.id == sessionID }
        )?.processIdentifier {
            gentleExemptProcesses[sessionID] = processIdentifier
        }
        scheduledCloseHadTarget = false
        removeClosingRow(sessionID: sessionID)
    }

    func hideClosingPanel() {
        presentationCoordinator.closeClosing()
    }

    func showClosingDetails() {
        presentationCoordinator.showClosing(model: self, activating: true)
    }

    func showNotesReview() {
        guard canRevealNoteContent,
              !visibleNotes.isEmpty else {
            return
        }
        presentationCoordinator.showNotes(model: self)
    }

    func showNoteCapture() {
        guard isSessionActive else {
            lastError =
                "Saved thoughts stay hidden while your session is inactive."
            return
        }
        guard notesHealth == .available else {
            lastError = "Saved thoughts are unavailable. App closing still works."
            return
        }
        lastError = nil
        presentationCoordinator.showNoteCapture(model: self)
    }

    func showCustomCutoff() {
        presentationCoordinator.showCustomCutoff(model: self)
    }

    func showTodayChangePanel() {
        presentationCoordinator.showTodayChange(model: self)
    }

    func saveNote(_ text: String) async -> Bool {
        await waitForNotesSave()
        guard notesHealth == .available else {
            lastError = "Saved thoughts are unavailable. App closing still works."
            return false
        }
        precondition(notesMutationGate.beginIfAvailable())
        defer { finishNotesSave() }
        do {
            let note = try TomorrowNote(text: text)
            var updated = notes
            try updated.append(note)
            notes = try await notesSaver(updated)
            notesHealth = .available
            return true
        } catch {
            lastError = "The thought was not saved. Your draft is still here."
            return false
        }
    }

    @discardableResult
    func keepNote(id: UUID, intervalID: String) async -> Bool {
        await waitForNotesSave()
        do {
            var updated = notes
            try updated.markPresented(id: id, in: intervalID)
            return await commitNotes(updated)
        } catch {
            lastError = "The thought could not be kept for later."
            return false
        }
    }

    @discardableResult
    func undoKeepNote(_ previousValue: TomorrowNote) async -> Bool {
        await waitForNotesSave()
        do {
            var updated = notes
            try updated.restorePresentation(from: previousValue)
            return await commitNotes(updated)
        } catch {
            lastError = "The thought could not be restored to this review."
            return false
        }
    }

    func removeNote(id: UUID) async {
        _ = await completeNote(id: id)
    }

    func completeNote(id: UUID) async -> TomorrowNote? {
        await waitForNotesSave()
        var updated = notes
        guard let removed = updated.remove(id: id),
              await commitNotes(updated) else {
            return nil
        }
        return removed
    }

    func restoreNote(_ note: TomorrowNote) async -> Bool {
        await waitForNotesSave()
        var updated = notes
        do {
            try updated.append(note)
        } catch {
            lastError = "The thought could not be restored."
            return false
        }
        return await commitNotes(updated)
    }

    @discardableResult
    func resetSetup() async -> Bool {
        await waitForConfigurationSave()
        do {
            let initial = try HomewardConfiguration.initial()
            guard await commit(
                initial,
                reconcileAfterSave: false
            ) else {
                return false
            }
            cancelAllEnforcement()
            UserDefaults.standard.set(
                0,
                forKey: HomewardPreferenceKeys.onboardingStep
            )
            resolvedSchedule = resolveSchedule(at: nowProvider())
            await notificationService.removeAllOwned()
            return true
        } catch {
            HomewardLog.persistence.error("Setup reset failed")
            lastError = "Setup could not be reset. The existing app-closing policy remains active."
            return false
        }
    }

    @discardableResult
    func retryConfigurationLoad() async -> Bool {
        await performConfigurationRecovery(
            failureMessage:
                "App closing is paused because settings could not be verified."
        ) {
            configuration = try await repository.loadConfiguration()
                ?? HomewardConfiguration.initial()
            return .activate(resetOnboarding: false)
        }
    }

    @discardableResult
    func restorePreviousConfiguration() async -> Bool {
        await performConfigurationRecovery(
            failureMessage:
                "Previous settings could not be restored. App closing remains paused."
        ) {
            guard let candidate = try await repository.configurationRecoveryCandidate() else {
                return .reject(message: "No previous settings are available.")
            }
            var recovered = candidate
            recovered.advancePolicyGeneration(
                after: configuration.policyGeneration
            )
            configuration = try await repository
                .replaceConfigurationDuringRecovery(recovered)
            return .activate(resetOnboarding: false)
        }
    }

    @discardableResult
    func replaceWithFreshSetup() async -> Bool {
        await performConfigurationRecovery(
            failureMessage:
                "A fresh setup could not be saved. App closing remains paused."
        ) {
            var initial = try HomewardConfiguration.initial()
            initial.advancePolicyGeneration(
                after: configuration.policyGeneration
            )
            configuration = try await repository
                .replaceConfigurationDuringRecovery(initial)
            return .activate(resetOnboarding: true)
        }
    }

    @discardableResult
    func resetSavedThoughts() async -> Bool {
        await waitForNotesSave()
        precondition(notesMutationGate.beginIfAvailable())
        defer { finishNotesSave() }
        do {
            try await notesResetter()
            notes = try NotesDocument()
            notesHealth = .available
            notesRecoveryCandidateAvailable = false
            return true
        } catch {
            lastError = "Saved thoughts could not be reset."
            return false
        }
    }

    @discardableResult
    func retryNotesLoad() async -> Bool {
        await waitForNotesSave()
        do {
            notes = try await repository.loadNotes()
            notesHealth = .available
            notesRecoveryCandidateAvailable = false
            return true
        } catch {
            notesHealth = .unavailable
            notesRecoveryCandidateAvailable =
                (try? await repository.notesRecoveryCandidate()) != nil
            lastError = "Saved thoughts are unavailable. App closing still works."
            return false
        }
    }

    @discardableResult
    func restorePreviousNotes() async -> Bool {
        await waitForNotesSave()
        precondition(notesMutationGate.beginIfAvailable())
        defer { finishNotesSave() }
        do {
            guard let candidate = try await repository
                .notesRecoveryCandidate() else {
                lastError = "No previous saved thoughts are available."
                return false
            }
            notes = try await repository.replaceNotesDuringRecovery(candidate)
            notesHealth = .available
            notesRecoveryCandidateAvailable = false
            return true
        } catch {
            notesHealth = .unavailable
            lastError = "Previous saved thoughts could not be restored."
            return false
        }
    }

    func prepareForTermination() async {
        guard !isShuttingDown else {
            return
        }
        isShuttingDown = true
        runtimeForcePauseIntervalIDs.insert(
            blockedIntervalID(at: nowProvider())
        )
        transitionTask?.cancel()
        notesLoadTask?.cancel()
        systemStatusTask?.cancel()
        previewTimeoutTask?.cancel()
        for task in launchMetadataTasks.values {
            task.cancel()
        }
        launchMetadataTasks.removeAll()
        cancelEnforcementTasks()
        presentationCoordinator.dismissSensitivePresentations()
        workspaceMonitor.stop()
        notificationService.stop()
        await notificationService.removeAllOwned()
        await waitForPendingSavesBeforeTermination()
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    @discardableResult
    func turnOff() async -> Bool {
        guard isPolicyMutationEnabled else {
            lastError = "Homeward is still starting. Start at Login was not changed."
            return false
        }
        do {
            try loginItemService.disable()
            loginItemStatus = loginItemService.status
            quit()
            return true
        } catch {
            loginItemStatus = loginItemService.status
            lastError = "Homeward could not disable Start at Login and remains on."
            return false
        }
    }

    func clearError() {
        lastError = nil
    }

    func clearTodayExplanation() {
        todayExplanation = nil
    }

    private func performConfigurationRecovery(
        failureMessage: String,
        operation: () async throws -> ConfigurationRecoveryOutcome
    ) async -> Bool {
        guard !isRecoveryInProgress else {
            return false
        }
        isRecoveryInProgress = true
        defer { isRecoveryInProgress = false }

        cancelAllEnforcement()
        presentationCoordinator.setRecoveryActive(true)
        await notificationService.removeAllOwned()
        await configurationMutationGate.beginAfterWaiting()

        let outcome: ConfigurationRecoveryOutcome
        do {
            outcome = try await operation()
        } catch {
            finishConfigurationSave()
            health = .configurationUnavailable
            lastError = failureMessage
            return false
        }
        finishConfigurationSave()

        switch outcome {
        case let .activate(resetOnboarding):
            configurationRevision &+= 1
            if resetOnboarding {
                UserDefaults.standard.set(
                    0,
                    forKey: HomewardPreferenceKeys.onboardingStep
                )
            }
            await activateRuntime(clearingError: true)
            return true
        case let .reject(message):
            lastError = message
            return false
        }
    }

    @discardableResult
    private func commit(
        _ updated: HomewardConfiguration,
        reconcileAfterSave: Bool = true,
        requiresReady: Bool = true,
        expectedRevision: Int? = nil
    ) async -> Bool {
        guard !requiresReady || isPolicyMutationEnabled else {
            lastError = "Homeward is still starting. No settings were changed."
            return false
        }
        guard expectedRevision == nil
                || expectedRevision == configurationRevision else {
            lastError =
                "These changes are based on older settings. Review the current settings and try again."
            return false
        }
        guard configurationMutationGate.beginIfAvailable() else {
            lastError = "Another settings change is still being saved. Try again."
            return false
        }
        defer { finishConfigurationSave() }
        let confirmationRevision = onboardingConfirmationRevision
        do {
            var persisted = updated
            persisted.removeExpiredOverrides(at: nowProvider())
            persisted.advancePolicyGeneration(
                after: configuration.policyGeneration
            )
            var saved = try await configurationSaver(persisted)
            if onboardingConfirmationRevision != confirmationRevision,
               !saved.completedOnboarding {
                saved.onboardingScheduleConfirmed =
                    configuration.onboardingScheduleConfirmed
            }
            configuration = saved
            configurationRevision &+= 1
            await notificationService.removeAllOwned()
            if reconcileAfterSave {
                await reconcile(runningApplications: workspaceMonitor.runningApplications)
            }
            return true
        } catch {
            HomewardLog.persistence.error("Configuration save failed")
            lastError = "Changes could not be saved. No new app-closing policy was applied."
            return false
        }
    }

    private func waitForConfigurationSave() async {
        await configurationMutationGate.waitUntilAvailable()
    }

    private func finishConfigurationSave() {
        configurationMutationGate.finish()
    }

    private func commitNotes(_ updated: NotesDocument) async -> Bool {
        guard notesHealth == .available else {
            lastError = "Saved thoughts are unavailable. App closing still works."
            return false
        }
        guard notesMutationGate.beginIfAvailable() else {
            lastError = "Another saved-thought change is still in progress."
            return false
        }
        defer { finishNotesSave() }
        do {
            notes = try await notesSaver(updated)
            return true
        } catch {
            HomewardLog.persistence.error("Notes save failed")
            lastError = "Saved thoughts could not be changed."
            return false
        }
    }

    private func waitForNotesSave() async {
        await notesMutationGate.waitUntilAvailable()
    }

    private func finishNotesSave() {
        notesMutationGate.finish()
    }

    private func waitForPendingSavesBeforeTermination() async {
        let deadline = elapsedClock.now().advanced(
            by: Self.terminationSaveWait
        )
        while configurationMutationGate.isInProgress
                || notesMutationGate.isInProgress {
            guard elapsedClock.now() < deadline else {
                return
            }
            do {
                try await elapsedClock.sleep(Self.terminationSavePoll)
            } catch {
                return
            }
        }
    }

    private func schedulePreviewTimeout(applicationName: String) {
        previewTimeoutTask?.cancel()
        previewTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(
                for: .seconds(HomewardPolicy.previewStepTimeout)
            )
            guard !Task.isCancelled, let self else {
                return
            }
            self.previewState = .needsAttention(applicationName)
        }
    }

    private func handlePreviewLaunch(
        _ snapshot: RunningApplicationSnapshot
    ) -> Bool {
        guard case .waitingForRelaunch = previewState,
              let selectionID = previewSelectionID,
              let selection = configuration.selectedApplications.first(
                  where: { $0.id == selectionID }
              ),
              planner.matches(selection: selection, process: snapshot),
              let target = planner.targets(
                  selections: [selection],
                  runningApplications: [snapshot]
              ).first
        else {
            return false
        }

        previewProcessSessionID = target.id
        let accepted = runningController.requestNormalTermination(for: target.id)
        previewState = accepted
            ? .waitingForSecondExit(selection.displayName)
            : .needsAttention(selection.displayName)
        schedulePreviewTimeout(applicationName: selection.displayName)
        return true
    }

    private func handlePreviewTermination(
        sessionID: ProcessSessionID?
    ) -> Bool {
        guard Self.terminationMatches(
            expectedSessionID: previewProcessSessionID,
            terminatedSessionID: sessionID
        ) else {
            return false
        }
        previewTimeoutTask?.cancel()
        previewProcessSessionID = nil
        switch previewState {
        case let .waitingForFirstExit(applicationName):
            previewState = .waitingForRelaunch(applicationName)
            schedulePreviewTimeout(applicationName: applicationName)
        case let .waitingForSecondExit(applicationName):
            previewState = .complete(applicationName)
            previewTimeoutTask = nil
        default:
            return false
        }
        return true
    }

    static func terminationMatches(
        expectedSessionID: ProcessSessionID?,
        terminatedSessionID: ProcessSessionID?
    ) -> Bool {
        guard let expectedSessionID, let terminatedSessionID else {
            return false
        }
        return terminatedSessionID == expectedSessionID
    }

    private func activateRuntime(clearingError: Bool) async {
        if clearingError {
            lastError = nil
        }
        guard await refreshCatalog(reconcileAfterSave: false),
              !Task.isCancelled,
              !isShuttingDown else {
            if !Task.isCancelled, !isShuttingDown {
                health = .applicationResolutionUnavailable
            }
            return
        }
        notificationService.start(handler: self)
        workspaceMonitor.start()
        presentationCoordinator.setRecoveryActive(false)
        let initialApplications = workspaceMonitor.runningApplications
        isSessionActive = workspaceMonitor.sessionIsLikelyActive
        await reconcile(runningApplications: initialApplications)
        guard !Task.isCancelled, !isShuttingDown else {
            return
        }
        runtimeActivated = true
        health = .ready
        startNotesLoad()
        systemStatusTask?.cancel()
        systemStatusTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await self.refreshSystemStatuses()
            await self.scheduleWarningsIfPossible()
        }
    }

    private func startNotesLoad() {
        notesLoadTask?.cancel()
        notesHealth = .loading
        notesLoadTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                let loaded = try await self.repository.loadNotes()
                guard !Task.isCancelled, !self.isShuttingDown else {
                    return
                }
                self.notes = loaded
                self.notesHealth = .available
                self.notesRecoveryCandidateAvailable = false
                self.presentNotesIfNeeded()
            } catch {
                guard !Task.isCancelled, !self.isShuttingDown else {
                    return
                }
                HomewardLog.persistence.error("Notes load failed")
                let recoveryCandidateAvailable =
                    (try? await self.repository.notesRecoveryCandidate())
                    != nil
                guard !Task.isCancelled, !self.isShuttingDown else {
                    return
                }
                self.notesRecoveryCandidateAvailable =
                    recoveryCandidateAvailable
                self.notesHealth = .unavailable
                self.lastError =
                    "Saved thoughts are unavailable. App closing still works."
            }
        }
    }

    private func applyAvailabilityOverride(
        kind: OverrideKind,
        effect: AvailabilityEffect,
        effectiveAt: Date,
        expiresAt: Date
    ) async -> Bool {
        await waitForConfigurationSave()
        do {
            let scheduleOverride = try ScheduleOverride(
                kind: kind,
                effect: effect,
                effectiveAt: effectiveAt,
                expiresAt: expiresAt
            )
            var updated = configuration
            updated.replaceActiveAvailabilityOverrides(
                with: [scheduleOverride],
                at: effectiveAt
            )
            return await commit(updated)
        } catch {
            lastError = "Today’s schedule could not be changed."
            return false
        }
    }

    private func nextBaseWindowStart(
        afterCurrentIntervalAt now: Date,
        calendar: Calendar
    ) -> Date? {
        resolver.nextWindowStart(
            for: configuration.schedule,
            afterCurrentIntervalAt: now,
            calendar: calendar
        )
    }

    private func availabilityOverrideExpiry(
        after date: Date,
        calendar: Calendar
    ) -> Date {
        nextBaseWindowStart(
            afterCurrentIntervalAt: date,
            calendar: calendar
        )
            ?? resolver.nextLocalDayBoundary(after: date, calendar: calendar)
    }

    private func resolveSchedule(
        schedule: WeeklySchedule? = nil,
        at date: Date
    ) -> ResolvedSchedule {
        resolver.resolve(
            schedule: schedule ?? configuration.schedule,
            overrides: configuration.overrides,
            at: date,
            calendar: .autoupdatingCurrent,
            warnings: configuration.warningPreferences
        )
    }

    private func reconcile(runningApplications: [NSRunningApplication]) async {
        guard !isShuttingDown else {
            return
        }
        transitionTask?.cancel()
        let now = nowProvider()
        resolvedSchedule = resolveSchedule(at: now)
        await pruneTransientState(at: now)
        guard !isShuttingDown else {
            return
        }

        let currentBlockedIntervalID = blockedIntervalID(at: now)
        if resolvedSchedule.isAvailable {
            runtimeForcePauseIntervalIDs.removeAll()
        } else {
            runtimeForcePauseIntervalIDs = runtimeForcePauseIntervalIDs.filter {
                $0 == currentBlockedIntervalID
            }
        }

        if resolvedSchedule.isAvailable || !configuration.completedOnboarding {
            cancelAllEnforcement()
            if configuration.completedOnboarding {
                presentNotesIfNeeded()
            }
        } else {
            enforce(
                snapshots: runningController.snapshots(runningApplications),
                now: now
            )
        }
        await scheduleWarningsIfPossible()
        scheduleNextTransition()
    }

    private func pruneTransientState(at now: Date) async {
        let selectedIDs = Set(configuration.selectedApplications.map(\.id))
        lastBlockedFeedbackBySelection = lastBlockedFeedbackBySelection.filter {
            selectedIDs.contains($0.key)
                && now.timeIntervalSince($0.value)
                    < HomewardPolicy.blockedFeedbackCooldown
        }

        if let currentIntervalID = resolvedSchedule.activeBaseInterval?.id {
            presentedNoteIntervalIDs = presentedNoteIntervalIDs.filter {
                $0 == currentIntervalID
            }
        } else {
            presentedNoteIntervalIDs.removeAll()
        }

        guard configurationMutationGate.beginIfAvailable() else {
            return
        }
        defer { finishConfigurationSave() }
        var updated = configuration
        var changed = updated.removeExpiredOverrides(at: now)
        if resolvedSchedule.isAvailable,
           resolvedSchedule.phase != .temporarilyExtended,
           !updated.consumedGentleExtensionIntervalIDs.isEmpty {
            updated.clearGentleExtensionConsumption()
            changed = true
        }
        guard changed else {
            return
        }
        do {
            updated.advancePolicyGeneration(
                after: configuration.policyGeneration
            )
            configuration = try await configurationSaver(updated)
            configurationRevision &+= 1
            await notificationService.removeAllOwned()
        } catch {
            HomewardLog.persistence.error("Transient state cleanup failed")
            lastError = "Expired temporary state could not be cleaned up."
        }
    }

    private func scheduleWarningsIfPossible() async {
        guard !isShuttingDown,
              configuration.completedOnboarding,
              notificationStatus == .authorized else {
            await notificationService.removeWarnings()
            return
        }
        guard resolvedSchedule.isAvailable,
              resolvedSchedule.nextTransition?.cause == .workWindowEnds,
              let cutoff = resolvedSchedule.nextTransition?.date
        else {
            await notificationService.removeWarnings()
            return
        }
        do {
            try await notificationService.replaceWarnings(
                cutoff: cutoff,
                policyGeneration: configuration.policyGeneration,
                preferences: configuration.warningPreferences,
                includeExtension: configuration.closeMode == .gentle
                    && configuration.gentleShortcutExtensionEnabled
                    && !configuration.consumedGentleExtensionIntervalIDs.contains(
                        currentOrUpcomingBlockedIntervalID()
                    )
            )
        } catch {
            HomewardLog.lifecycle.error("Warning scheduling failed")
            notificationStatus =
                await notificationService.authorizationStatus()
            if notificationStatus != .authorized {
                await notificationService.removeAllOwned()
            }
            lastError = "Wind-down notifications could not be scheduled. App closing still works."
        }
    }

    private func scheduleNextTransition() {
        let now = nowProvider()
        guard let refreshDate = resolver.nextRefreshDate(
            for: resolvedSchedule,
            after: now,
            warnings: configuration.warningPreferences
        ) else {
            return
        }
        let delay = refreshDate.timeIntervalSince(now)
        transitionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(0, delay)))
            guard !Task.isCancelled, let self else {
                return
            }
            await self.reconcile(runningApplications: self.workspaceMonitor.runningApplications)
        }
    }

    private func enforce(
        snapshots: [RunningApplicationSnapshot],
        now: Date
    ) {
        let intervalID = blockedIntervalID(at: now)
        let targets = planner.targets(
            selections: configuration.selectedApplications,
            runningApplications: snapshots
        ).filter { gentleExemptProcesses[$0.id] == nil }
        pruneStaleEnforcement(
            currentTargets: targets,
            blockedIntervalID: intervalID
        )
        for target in targets where closingRows.contains(where: { $0.id == target.id }) == false {
            beginEnforcement(
                target: target,
                now: now,
                blockedIntervalID: intervalID
            )
        }
    }

    private func beginEnforcement(
        target: EnforcementTarget,
        now: Date,
        blockedIntervalID intervalID: String
    ) {
        let enforcementIdentity = EnforcementIdentity(
            target: target,
            schedule: configuration.schedule,
            blockedIntervalID: intervalID
        )
        if blockedLaunchTargets[target.id] == nil {
            scheduledCloseHadTarget = true
        }
        let normalRequestAccepted = runningController.requestNormalTermination(
            for: target.id
        )
        switch configuration.closeMode {
        case .gentle:
            let row = ClosingRow(
                sessionID: target.id,
                enforcementIdentity: enforcementIdentity,
                applicationName: target.process.displayName,
                processIdentifier: target.process.processIdentifier,
                status: normalRequestAccepted ? .requestingNormalQuit : .needsAttention,
                secondsRemaining: nil
            )
            closingRows.append(row)
            if !normalRequestAccepted {
                showClosingPanel()
                return
            }
            enforcementTasks[target.id] = Task { @MainActor [weak self] in
                try? await Task.sleep(
                    for: .seconds(HomewardPolicy.gentleAttentionDelay)
                )
                guard !Task.isCancelled, let self else {
                    return
                }
                if self.runningController.isTerminated(sessionID: target.id) {
                    self.removeClosingRow(sessionID: target.id)
                } else {
                    self.updateClosingRow(sessionID: target.id) {
                        $0.status = .needsAttention
                    }
                    self.showClosingPanel()
                }
            }
        case .firm:
            let paused = forceEscalationPaused
            let deadline = elapsedClock.now().advanced(
                by: .seconds(HomewardPolicy.firmGracePeriod)
            )
            closingRows.append(ClosingRow(
                sessionID: target.id,
                enforcementIdentity: enforcementIdentity,
                applicationName: target.process.displayName,
                processIdentifier: target.process.processIdentifier,
                status: paused ? .forcePaused : .countingDown,
                secondsRemaining: paused ? nil : Int(HomewardPolicy.firmGracePeriod)
            ))
            showClosingPanel(activating: !paused)
            guard !paused else {
                return
            }
            enforcementTasks[target.id] = Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                while !Task.isCancelled {
                    let remaining = max(
                        0,
                        Int(ceil(self.elapsedClock.seconds(until: deadline)))
                    )
                    self.updateClosingRow(sessionID: target.id) {
                        $0.secondsRemaining = remaining
                    }
                    self.announceCountdownIfNeeded(
                        sessionID: target.id,
                        applicationName: target.process.displayName,
                        secondsRemaining: remaining
                    )
                    if remaining == 0 {
                        break
                    }
                    try? await self.elapsedClock.sleep(
                        .seconds(HomewardPolicy.countdownTick)
                    )
                }
                guard !Task.isCancelled else {
                    return
                }
                await self.attemptForceTermination(
                    target: target,
                    blockedIntervalID: intervalID
                )
            }
        }
    }

    private func pruneStaleEnforcement(
        currentTargets: [EnforcementTarget],
        blockedIntervalID: String
    ) {
        let staleSessionIDs = closingRows.compactMap { row in
            row.enforcementIdentity.isCurrent(
                schedule: configuration.schedule,
                blockedIntervalID: blockedIntervalID,
                targets: currentTargets
            ) ? nil : row.id
        }
        guard !staleSessionIDs.isEmpty else {
            return
        }
        for sessionID in staleSessionIDs {
            enforcementTasks[sessionID]?.cancel()
            enforcementTasks.removeValue(forKey: sessionID)
            announcedCountdownMilestones.removeValue(forKey: sessionID)
            blockedLaunchTargets.removeValue(forKey: sessionID)
        }
        let staleSet = Set(staleSessionIDs)
        closingRows.removeAll { staleSet.contains($0.id) }
        if closingRows.isEmpty {
            scheduledCloseHadTarget = false
        }
        refreshClosingPanel()
    }

    private func attemptForceTermination(
        target: EnforcementTarget,
        blockedIntervalID originalBlockedIntervalID: String
    ) async {
        let now = nowProvider()
        resolvedSchedule = resolveSchedule(at: now)
        let session = EnforcementSession(
            mode: .firm,
            startedAt: now.addingTimeInterval(
                -HomewardPolicy.firmGracePeriod
            ),
            targets: [target],
            forceEscalationPaused: forceEscalationPaused
        )
        let eligible = planner.forceEligibleTargetIDs(
            session: session,
            at: now,
            schedule: resolvedSchedule,
            currentSelections: configuration.selectedApplications,
            currentlyRunning: runningController.snapshots(
                workspaceMonitor.runningApplications
            )
        )
        guard blockedIntervalID(at: now) == originalBlockedIntervalID,
              eligible.contains(target.id) else {
            return
        }
        guard isSessionActive,
              presentationCoordinator.isClosingPanelVisible else {
            suspendForceEscalation()
            return
        }

        let accepted = runningController.requestForceTermination(for: target.id)
        try? await Task.sleep(
            for: .seconds(HomewardPolicy.forceTerminationVerificationDelay)
        )
        guard !Task.isCancelled else {
            return
        }
        if accepted && runningController.isTerminated(sessionID: target.id) {
            removeClosingRow(sessionID: target.id)
        } else {
            updateClosingRow(sessionID: target.id) {
                $0.status = .forceFailed
                $0.secondsRemaining = nil
            }
            showClosingPanel()
        }
    }

    private func cancelAllEnforcement() {
        cancelEnforcementTasks()
        announcedCountdownMilestones.removeAll()
        closingRows.removeAll()
        blockedLaunchTargets.removeAll()
        gentleExemptProcesses.removeAll()
        scheduledCloseHadTarget = false
        presentationCoordinator.closeClosing()
    }

    private func suspendForceEscalation() {
        cancelEnforcementTasks()
        announcedCountdownMilestones.removeAll()
        closingRows = closingRows.map { row in
            var updated = row
            if updated.status == .countingDown {
                updated.status = .forcePaused
                updated.secondsRemaining = nil
            }
            return updated
        }
        refreshClosingPanel()
    }

    private func restartFirmClosingAfterSessionActivation() async {
        if configuration.closeMode == .firm,
           !forceEscalationPaused,
           !resolvedSchedule.isAvailable {
            cancelAllEnforcement()
        }
        await reconcile(runningApplications: workspaceMonitor.runningApplications)
    }

    private func cancelEnforcementTasks() {
        for task in enforcementTasks.values {
            task.cancel()
        }
        enforcementTasks.removeAll()
    }

    private func updateClosingRow(
        sessionID: ProcessSessionID,
        update: (inout ClosingRow) -> Void
    ) {
        guard let index = closingRows.firstIndex(where: { $0.id == sessionID }) else {
            return
        }
        update(&closingRows[index])
        refreshClosingPanel()
    }

    private func removeClosingRow(sessionID: ProcessSessionID) {
        let blockedTarget = blockedLaunchTargets.removeValue(forKey: sessionID)
        let didTerminate = runningController.isTerminated(sessionID: sessionID)
        enforcementTasks[sessionID]?.cancel()
        enforcementTasks.removeValue(forKey: sessionID)
        announcedCountdownMilestones.removeValue(forKey: sessionID)
        closingRows.removeAll(where: { $0.id == sessionID })
        runningController.remove(sessionID: sessionID)
        refreshClosingPanel()
        if let blockedTarget, didTerminate {
            showBlockedLaunchFeedback(for: blockedTarget)
        } else if closingRows.isEmpty, scheduledCloseHadTarget {
            scheduledCloseHadTarget = false
            if didTerminate {
                postCompletionStatus()
            }
        }
    }

    private func handleProcessTermination(
        sessionID: ProcessSessionID?
    ) {
        if handlePreviewTermination(sessionID: sessionID),
           let sessionID {
            runningController.remove(sessionID: sessionID)
            return
        }

        guard let sessionID else {
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                await self.reconcile(
                    runningApplications: self.workspaceMonitor
                        .runningApplications
                )
            }
            return
        }

        gentleExemptProcesses.removeValue(forKey: sessionID)
        removeClosingRow(sessionID: sessionID)
    }

    private func showClosingPanel(activating: Bool = false) {
        presentationCoordinator.showClosing(
            model: self,
            activating: activating
        )
    }

    private func showBlockedLaunchFeedback(for target: EnforcementTarget) {
        guard !closingRows.contains(where: {
            $0.status == .countingDown
        }) else {
            return
        }
        let now = nowProvider()
        let lastFeedback = lastBlockedFeedbackBySelection[target.selectionID]
        lastBlockedFeedbackBySelection[target.selectionID] = now
        let availability = resolvedSchedule.nextAvailability.map {
            "Available \($0.formatted(date: .abbreviated, time: .shortened))."
        } ?? "No work window is scheduled."

        let shouldShowPanel = lastFeedback.map {
            now.timeIntervalSince($0) >= HomewardPolicy.blockedFeedbackCooldown
        } ?? true
        if shouldShowPanel {
            presentationCoordinator.showBlockedLaunch(
                model: self,
                availabilityText: availability
            )
        } else if notificationStatus == .authorized {
            Task {
                do {
                    try await notificationService.post(
                        .blockedLaunch(
                            nextAvailability: resolvedSchedule.nextAvailability
                        )
                    )
                } catch {
                    HomewardLog.lifecycle.error(
                        "Blocked-launch status notification failed"
                    )
                }
            }
        }
    }

    private func postCompletionStatus() {
        guard notificationStatus == .authorized else {
            return
        }
        Task {
            do {
                try await notificationService.post(
                    .closingComplete(
                        nextAvailability: resolvedSchedule.nextAvailability
                    )
                )
            } catch {
                HomewardLog.lifecycle.error(
                    "Completion status notification failed"
                )
            }
        }
    }

    private func refreshClosingPanel() {
        if closingRows.isEmpty {
            presentationCoordinator.closeClosing()
        }
    }

    private func announceCountdownIfNeeded(
        sessionID: ProcessSessionID,
        applicationName: String,
        secondsRemaining: Int
    ) {
        let announced = announcedCountdownMilestones[sessionID, default: []]
        guard countdownAnnouncementPolicy.shouldAnnounce(
            secondsRemaining: secondsRemaining,
            announced: announced
        ), let application = NSApp else {
            return
        }
        announcedCountdownMilestones[sessionID, default: []].insert(secondsRemaining)
        NSAccessibility.post(
            element: application,
            notification: .announcementRequested,
            userInfo: [
                .announcement: "\(applicationName) will be force quit in \(secondsRemaining) seconds.",
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }

    private func blockedIntervalID(at date: Date) -> String {
        resolver.blockedIntervalID(
            for: configuration.schedule,
            overrides: configuration.overrides,
            at: date,
            calendar: .autoupdatingCurrent
        )
    }

    private func currentOrUpcomingBlockedIntervalID() -> String {
        blockedIntervalID(at: nowProvider())
    }

    private func pausedForceOverrideExpiry(at date: Date) -> Date {
        resolver.forcePauseExpiry(
            for: configuration.schedule,
            overrides: configuration.overrides,
            at: date,
            calendar: .autoupdatingCurrent
        )
    }

    private func presentNotesIfNeeded() {
        guard isSessionActive,
              notesHealth == .available,
              resolvedSchedule.phase != .temporarilyExtended,
              let intervalID = resolvedSchedule.activeBaseInterval?.id,
              notes.notes.contains(where: {
                  $0.lastPresentedIntervalID != intervalID
              }),
              !presentedNoteIntervalIDs.contains(intervalID)
        else {
            return
        }
        presentedNoteIntervalIDs.insert(intervalID)
        presentationCoordinator.showNotesReady(
            model: self,
            count: availableNotesCount
        )
    }

    private func handleLaunchSnapshot(_ snapshot: RunningApplicationSnapshot) {
        guard !isShuttingDown else {
            return
        }
        if handlePreviewLaunch(snapshot) {
            return
        }
        guard configuration.completedOnboarding else {
            return
        }
        let now = nowProvider()
        resolvedSchedule = resolveSchedule(at: now)
        transitionTask?.cancel()
        scheduleNextTransition()
        if resolvedSchedule.isAvailable {
            presentNotesIfNeeded()
        } else {
            for target in planner.targets(
                selections: configuration.selectedApplications,
                runningApplications: [snapshot]
            ) {
                blockedLaunchTargets[target.id] = target
            }
            enforce(snapshots: [snapshot], now: now)
        }
    }

    private func retryLaunchMetadata(
        for application: NSRunningApplication
    ) {
        let processIdentifier = application.processIdentifier
        launchMetadataTasks[processIdentifier]?.cancel()
        launchMetadataTasks[processIdentifier] = Task {
            [weak self, weak application] in
            guard let self else {
                return
            }
            for _ in 0..<Self.launchMetadataRetryLimit {
                do {
                    try await self.elapsedClock.sleep(
                        .seconds(HomewardPolicy.launchMetadataRetryDelay)
                    )
                } catch {
                    return
                }
                guard !Task.isCancelled,
                      let application,
                      !application.isTerminated else {
                    return
                }
                let snapshot = self.runningController.snapshot(application)
                if snapshot.processSessionID != nil {
                    self.launchMetadataTasks.removeValue(
                        forKey: processIdentifier
                    )
                    self.handleLaunchSnapshot(snapshot)
                    return
                }
            }
            self.launchMetadataTasks.removeValue(forKey: processIdentifier)
            await self.reconcile(
                runningApplications: self.workspaceMonitor.runningApplications
            )
        }
    }
}

extension AppModel: WorkspaceMonitorDelegate {
    func workspaceMonitor(
        _ monitor: WorkspaceMonitor,
        didLaunch application: NSRunningApplication
    ) {
        let snapshot = runningController.snapshot(application)
        guard snapshot.processSessionID != nil else {
            retryLaunchMetadata(for: application)
            return
        }
        handleLaunchSnapshot(snapshot)
    }

    func workspaceMonitor(
        _ monitor: WorkspaceMonitor,
        didTerminate application: NSRunningApplication
    ) {
        let snapshot = runningController.snapshot(application)
        launchMetadataTasks[application.processIdentifier]?.cancel()
        launchMetadataTasks.removeValue(
            forKey: application.processIdentifier
        )
        handleProcessTermination(sessionID: snapshot.processSessionID)
    }

    func workspaceMonitorRequiresReconciliation(_ monitor: WorkspaceMonitor) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await self.reconcile(runningApplications: monitor.runningApplications)
        }
    }

    func workspaceMonitorWillSuspend(_ monitor: WorkspaceMonitor) {
        isSessionActive = false
        suspendForceEscalation()
        presentationCoordinator.dismissSensitivePresentations()
        sensitivePresentationDismissalHandler?()
        Task {
            await notificationService.removeAllOwned()
        }
    }

    func workspaceMonitor(
        _ monitor: WorkspaceMonitor,
        sessionActiveDidChange isActive: Bool
    ) {
        isSessionActive = isActive
        if isActive {
            Task {
                await refreshSystemStatuses()
                await restartFirmClosingAfterSessionActivation()
            }
        } else {
            suspendForceEscalation()
            presentationCoordinator.dismissSensitivePresentations()
            sensitivePresentationDismissalHandler?()
            Task {
                await notificationService.removeAllOwned()
            }
        }
    }
}

extension AppModel: HomewardNotificationHandling {
    func handleNotificationAction(
        _ identifier: String,
        context: WarningActionContext?
    ) {
        if identifier == UNNotificationDefaultActionIdentifier {
            routeHandler?(.today)
            return
        }
        if identifier == UNNotificationDismissActionIdentifier {
            return
        }
        guard identifier == HomewardNotificationService.startClosingAction
                || identifier == HomewardNotificationService.extendAction else {
            routeStaleNotificationAction()
            return
        }
        Task { @MainActor [weak self] in
            await self?.applyNotificationAction(
                identifier,
                context: context
            )
        }
    }

    func applyNotificationAction(
        _ identifier: String,
        context: WarningActionContext?
    ) async {
        guard !isShuttingDown else {
            return
        }
        await waitForConfigurationSave()
        guard configuration.completedOnboarding, !isShuttingDown else {
            routeStaleNotificationAction()
            return
        }
        let now = nowProvider()
        let currentSchedule = resolveSchedule(at: now)
        guard context?.isCurrent(
            for: currentSchedule,
            policyGeneration: configuration.policyGeneration,
            at: now
        ) == true else {
            routeStaleNotificationAction()
            return
        }
        switch identifier {
        case HomewardNotificationService.startClosingAction:
            requestPolicyConfirmation(.endWorkNow, routeToToday: true)
        case HomewardNotificationService.extendAction:
            guard configuration.closeMode == .gentle,
                  configuration.gentleShortcutExtensionEnabled else {
                routeStaleNotificationAction()
                return
            }
            requestPolicyConfirmation(
                .gentleShortcutExtension,
                routeToToday: true
            )
        default:
            break
        }
    }

    private func routeStaleNotificationAction() {
        pendingPolicyConfirmation = nil
        todayExplanation =
            "This notification is no longer current. No changes were made."
        routeHandler?(.today)
    }
}
