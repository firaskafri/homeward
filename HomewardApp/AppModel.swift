import AppKit
import Combine
import Foundation
import HomewardCore

@MainActor
final class AppModel: NSObject, ObservableObject {
    private static let manualAvailabilityIntervalID = "manual-availability"

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
        case ready
        case configurationUnavailable
    }

    enum WarningOption {
        case fifteenMinute
        case fiveMinute
    }

    @Published private(set) var configuration: HomewardConfiguration
    @Published private(set) var notes: NotesDocument
    @Published private(set) var resolvedSchedule: ResolvedSchedule
    @Published private(set) var catalog: [CatalogApplication] = []
    @Published private(set) var isCatalogLoading = false
    @Published private(set) var closingRows: [ClosingRow] = []
    @Published private(set) var health: Health = .starting
    @Published private(set) var notificationStatus:
        HomewardNotificationService.AuthorizationStatus = .notDetermined
    @Published private(set) var loginItemStatus:
        LoginItemService.Status = .notRegistered
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

    private let repository: HomewardRepository
    private let nowProvider: () -> Date
    private let configurationSaver:
        (HomewardConfiguration) async throws -> HomewardConfiguration
    private let dateByAdding:
        (Calendar.Component, Int, Date) -> Date?
    private let resolver = ScheduleResolver()
    private let planner = EnforcementPlanner()
    private let countdownAnnouncementPolicy = CountdownAnnouncementPolicy()
    private let workspaceMonitor = WorkspaceMonitor()
    private let runningController = RunningApplicationController()
    private let appCatalog: ApplicationCatalog
    private let catalogDiscoverer: () async -> [CatalogApplication]
    private let loginItemService: LoginItemService
    private let notificationService: HomewardNotificationService
    private var transitionTask: Task<Void, Never>?
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
    private var previewProcessIdentifier: Int32?
    private var previewTimeoutTask: Task<Void, Never>?
    private var configurationSaveInProgress = false
    private var configurationSaveWaiters: [CheckedContinuation<Void, Never>] = []
    private var onboardingConfirmationRevision = 0
    private var notesSaveInProgress = false
    private var notesSaveWaiters: [CheckedContinuation<Void, Never>] = []
    private var catalogRefreshInProgress = false
    private var catalogRefreshRequested = false
    private var catalogRefreshWaiters: [CheckedContinuation<Void, Never>] = []
    private var started = false

    init(
        repository: HomewardRepository,
        nowProvider: @escaping () -> Date = Date.init,
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
        catalogDiscoverer: (() async -> [CatalogApplication])? = nil,
        loginItemService: LoginItemService? = nil,
        notificationService: HomewardNotificationService? = nil
    ) throws {
        let initialConfiguration = try HomewardConfiguration.initial()
        let resolvedCatalog = applicationCatalog ?? ApplicationCatalog()
        self.repository = repository
        self.nowProvider = nowProvider
        self.configurationSaver = configurationSaver ?? { configuration in
            try await repository.saveConfiguration(configuration)
        }
        self.dateByAdding = dateByAdding
        appCatalog = resolvedCatalog
        self.catalogDiscoverer = catalogDiscoverer ?? {
            await resolvedCatalog.discover()
        }
        self.loginItemService = loginItemService ?? LoginItemService()
        self.notificationService =
            notificationService ?? HomewardNotificationService()
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

    static func makeDefault() throws -> AppModel {
        return try AppModel(repository: HomewardRepository())
    }

    var isOnboardingComplete: Bool {
        configuration.completedOnboarding
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
        guard !started else {
            return
        }
        started = true

        do {
            if let stored = try await repository.loadConfiguration() {
                configuration = stored
            }
        } catch {
            HomewardLog.persistence.error("Configuration load failed")
            health = .configurationUnavailable
            lastError = "App closing is paused because settings could not be verified."
            return
        }

        do {
            notes = try await repository.loadNotes()
        } catch {
            HomewardLog.persistence.error("Notes load failed")
            lastError = "Saved thoughts are unavailable. App closing still works."
        }

        notificationService.start(handler: self)
        workspaceMonitor.start()
        isSessionActive = workspaceMonitor.sessionIsLikelyActive
        health = .ready
        await reconcile(runningApplications: workspaceMonitor.runningApplications)
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await self.refreshSystemStatuses()
            await self.scheduleWarningsIfPossible()
        }
        Task { @MainActor [weak self] in
            await self?.refreshCatalog()
        }
    }

    func refreshCatalog() async {
        catalogRefreshRequested = true
        guard !catalogRefreshInProgress else {
            await withCheckedContinuation { continuation in
                catalogRefreshWaiters.append(continuation)
            }
            return
        }

        catalogRefreshInProgress = true
        isCatalogLoading = true
        defer {
            catalogRefreshInProgress = false
            isCatalogLoading = false
            let waiters = catalogRefreshWaiters
            catalogRefreshWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }

        while catalogRefreshRequested {
            catalogRefreshRequested = false
            let discovered = await catalogDiscoverer()
            guard !catalogRefreshRequested else {
                continue
            }
            catalog = discovered
            await reconcileCatalogSelections()
        }
    }

    private func reconcileCatalogSelections() async {
        await waitForConfigurationSave()
        var updated = configuration
        var changed = false
        for index in updated.selectedApplications.indices {
            let selection = updated.selectedApplications[index]
            let catalogMatch = catalog.first { candidate in
                if let bundleIdentifier = selection.bundleIdentifier {
                    return candidate.selection.bundleIdentifier == bundleIdentifier
                }
                return candidate.selection.stableSelectionKey == selection.stableSelectionKey
            }
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
            let match = catalogMatch ?? savedPathMatch
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
            await commit(updated)
        }
    }

    func refreshSystemStatuses() async {
        notificationStatus = await notificationService.authorizationStatus()
        if notificationStatus != .authorized {
            await notificationService.removeWarnings()
        }
        loginItemStatus = loginItemService.status
    }

    @discardableResult
    func requestNotificationPermission() async -> Bool {
        do {
            _ = try await notificationService.requestAuthorization()
            notificationStatus = await notificationService.authorizationStatus()
            if notificationStatus == .authorized {
                await scheduleWarningsIfPossible()
                return true
            }
            await notificationService.removeWarnings()
            return false
        } catch {
            HomewardLog.lifecycle.error("Notification authorization failed")
            notificationStatus = await notificationService.authorizationStatus()
            if notificationStatus != .authorized {
                await notificationService.removeWarnings()
            }
            lastError = "Notifications could not be enabled. App closing still works."
            return false
        }
    }

    @discardableResult
    func enableStartAtLogin() -> Bool {
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
              !configuration.selectedApplications.isEmpty else {
            lastError = "Confirm the schedule and choose at least one work app."
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
        guard !configuration.completedOnboarding else {
            return
        }
        onboardingConfirmationRevision &+= 1
        configuration.onboardingScheduleConfirmed = false
    }

    func restoreOnboardingScheduleConfirmation() {
        guard !configuration.completedOnboarding else {
            return
        }
        onboardingConfirmationRevision &+= 1
        configuration.onboardingScheduleConfirmed = true
    }

    func startPreview(selectionID: UUID) {
        endPreview()
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
        previewProcessIdentifier = target.process.processIdentifier
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
        previewProcessIdentifier = nil
        previewState = .idle
    }

    func showPreviewApplication() {
        guard let previewProcessSessionID else {
            lastError = "The preview application is no longer running."
            return
        }
        _ = runningController.activate(sessionID: previewProcessSessionID)
    }

    @discardableResult
    func setCloseMode(_ mode: CloseMode) async -> Bool {
        await waitForConfigurationSave()
        guard configuration.closeMode != mode else {
            return true
        }
        var updated = configuration
        updated.closeMode = mode
        if mode == .gentle {
            cancelAllEnforcement()
        }
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
    func setWarning(_ option: WarningOption, enabled: Bool) async -> Bool {
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
    func setSchedule(_ schedule: WeeklySchedule) async -> Bool {
        await waitForConfigurationSave()
        var updated = configuration
        updated.schedule = schedule
        if !updated.completedOnboarding {
            updated.onboardingScheduleConfirmed = true
        }
        return await commit(updated)
    }

    @discardableResult
    func addApplication(_ application: SelectedApplication) async -> Bool {
        await waitForConfigurationSave()
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
        return await commit(updated)
    }

    @discardableResult
    func removeApplication(id: UUID) async -> Bool {
        await waitForConfigurationSave()
        cancelEnforcement(forSelectionID: id)
        var updated = configuration
        updated.selectedApplications.removeAll(where: { $0.id == id })
        if await commit(updated) == false {
            await reconcile(
                runningApplications: workspaceMonitor.runningApplications
            )
            return false
        }
        return true
    }

    @discardableResult
    func addApplication(at url: URL) async -> Bool {
        guard let descriptor = appCatalog.descriptor(for: url) else {
            lastError = "The selected item is not a supported application."
            return false
        }
        return await addApplication(descriptor.selection)
    }

    @discardableResult
    func replaceApplication(id: UUID, with url: URL) async -> Bool {
        await waitForConfigurationSave()
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
        return await commit(updated)
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
        let expiry = nextBaseWindowStart(afterCurrentIntervalAt: now)
            ?? resolver.nextLocalDayBoundary(
                after: now,
                calendar: calendar
            )
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

    @discardableResult
    func makeWorkAvailableNow() async -> Bool {
        await waitForConfigurationSave()
        let now = nowProvider()
        let calendar = Calendar.autoupdatingCurrent
        let expiry = nextBaseWindowStart(afterCurrentIntervalAt: now)
            ?? resolver.nextLocalDayBoundary(
                after: now,
                calendar: calendar
            )
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
            return await endWorkNow()
        }
        guard cutoff <= nextLocalMidnight else {
            lastError = "Choose a cutoff before the end of the current local day."
            return false
        }
        let blockedUntil = nextBaseWindowStart(afterCurrentIntervalAt: cutoff)
            ?? resolver.nextLocalDayBoundary(
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
        for task in enforcementTasks.values {
            task.cancel()
        }
        enforcementTasks.removeAll()
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
        removeClosingRow(sessionID: sessionID)
    }

    func hideClosingPanel() {
        presentationCoordinator.closeClosing()
    }

    func showClosingDetails() {
        presentationCoordinator.showClosing(model: self, activating: true)
    }

    func showNotesReview() {
        guard resolvedSchedule.isAvailable,
              resolvedSchedule.phase != .temporarilyExtended,
              !visibleNotes.isEmpty else {
            return
        }
        presentationCoordinator.showNotes(model: self)
    }

    func showNoteCapture() {
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
        notesSaveInProgress = true
        defer { finishNotesSave() }
        do {
            let note = try TomorrowNote(text: text)
            var updated = notes
            try updated.append(note)
            notes = try await repository.saveNotes(updated)
            return true
        } catch {
            lastError = "The thought was not saved."
            return false
        }
    }

    func keepNote(id: UUID, intervalID: String) async {
        await waitForNotesSave()
        do {
            var updated = notes
            try updated.markPresented(id: id, in: intervalID)
            _ = await commitNotes(updated)
        } catch {
            lastError = "The thought could not be kept for later."
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
            resolvedSchedule = resolver.resolve(
                schedule: initial.schedule,
                overrides: [],
                at: nowProvider(),
                calendar: .autoupdatingCurrent,
                warnings: initial.warningPreferences
            )
            await notificationService.removeWarnings()
            return true
        } catch {
            HomewardLog.persistence.error("Setup reset failed")
            lastError = "Setup could not be reset. The existing app-closing policy remains active."
            return false
        }
    }

    @discardableResult
    func retryConfigurationLoad() async -> Bool {
        await waitForConfigurationSave()
        configurationSaveInProgress = true
        defer { finishConfigurationSave() }
        do {
            configuration = try await repository.loadConfiguration()
                ?? HomewardConfiguration.initial()
            await completeRecoveredBootstrap()
            return true
        } catch {
            health = .configurationUnavailable
            lastError = "App closing is paused because settings could not be verified."
            return false
        }
    }

    @discardableResult
    func restorePreviousConfiguration() async -> Bool {
        await waitForConfigurationSave()
        configurationSaveInProgress = true
        defer { finishConfigurationSave() }
        do {
            guard let candidate = try await repository.configurationRecoveryCandidate() else {
                lastError = "No previous settings are available."
                return false
            }
            configuration = try await repository
                .replaceConfigurationDuringRecovery(candidate)
            await completeRecoveredBootstrap()
            return true
        } catch {
            lastError = "Previous settings could not be restored. App closing remains paused."
            return false
        }
    }

    @discardableResult
    func replaceWithFreshSetup() async -> Bool {
        await waitForConfigurationSave()
        configurationSaveInProgress = true
        defer { finishConfigurationSave() }
        do {
            let initial = try HomewardConfiguration.initial()
            configuration = try await repository
                .replaceConfigurationDuringRecovery(initial)
            UserDefaults.standard.set(
                0,
                forKey: HomewardPreferenceKeys.onboardingStep
            )
            await completeRecoveredBootstrap()
            return true
        } catch {
            lastError = "A fresh setup could not be saved. App closing remains paused."
            return false
        }
    }

    @discardableResult
    func resetSavedThoughts() async -> Bool {
        await waitForNotesSave()
        notesSaveInProgress = true
        defer { finishNotesSave() }
        do {
            try await repository.resetNotes()
            notes = try NotesDocument()
            return true
        } catch {
            lastError = "Saved thoughts could not be reset."
            return false
        }
    }

    func quit() async {
        transitionTask?.cancel()
        for task in enforcementTasks.values {
            task.cancel()
        }
        workspaceMonitor.stop()
        notificationService.stop()
        await notificationService.removeWarnings()
        NSApplication.shared.terminate(nil)
    }

    @discardableResult
    func turnOff() async -> Bool {
        do {
            try loginItemService.disable()
            loginItemStatus = loginItemService.status
            await quit()
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

    @discardableResult
    private func commit(
        _ updated: HomewardConfiguration,
        reconcileAfterSave: Bool = true
    ) async -> Bool {
        guard !configurationSaveInProgress else {
            lastError = "Another settings change is still being saved. Try again."
            return false
        }
        configurationSaveInProgress = true
        defer { finishConfigurationSave() }
        let confirmationRevision = onboardingConfirmationRevision
        do {
            var persisted = updated
            persisted.removeExpiredOverrides(at: nowProvider())
            var saved = try await configurationSaver(persisted)
            if onboardingConfirmationRevision != confirmationRevision,
               !saved.completedOnboarding {
                saved.onboardingScheduleConfirmed =
                    configuration.onboardingScheduleConfirmed
            }
            configuration = saved
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
        while configurationSaveInProgress {
            await withCheckedContinuation { continuation in
                configurationSaveWaiters.append(continuation)
            }
        }
    }

    private func finishConfigurationSave() {
        configurationSaveInProgress = false
        let waiters = configurationSaveWaiters
        configurationSaveWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func commitNotes(_ updated: NotesDocument) async -> Bool {
        guard !notesSaveInProgress else {
            lastError = "Another saved-thought change is still in progress."
            return false
        }
        notesSaveInProgress = true
        defer { finishNotesSave() }
        do {
            notes = try await repository.saveNotes(updated)
            return true
        } catch {
            HomewardLog.persistence.error("Notes save failed")
            lastError = "Saved thoughts could not be changed."
            return false
        }
    }

    private func waitForNotesSave() async {
        while notesSaveInProgress {
            await withCheckedContinuation { continuation in
                notesSaveWaiters.append(continuation)
            }
        }
    }

    private func finishNotesSave() {
        notesSaveInProgress = false
        let waiters = notesSaveWaiters
        notesSaveWaiters.removeAll()
        waiters.forEach { $0.resume() }
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
        previewProcessIdentifier = target.process.processIdentifier
        let accepted = runningController.requestNormalTermination(for: target.id)
        previewState = accepted
            ? .waitingForSecondExit(selection.displayName)
            : .needsAttention(selection.displayName)
        schedulePreviewTimeout(applicationName: selection.displayName)
        return true
    }

    private func handlePreviewTermination(
        processIdentifier: Int32,
        sessionID: ProcessSessionID?
    ) -> Bool {
        guard sessionID == previewProcessSessionID
                || processIdentifier == previewProcessIdentifier else {
            return false
        }
        previewTimeoutTask?.cancel()
        previewProcessSessionID = nil
        previewProcessIdentifier = nil
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

    private func completeRecoveredBootstrap() async {
        lastError = nil
        do {
            notes = try await repository.loadNotes()
        } catch {
            lastError = "Saved thoughts are unavailable. App closing still works."
        }
        notificationService.start(handler: self)
        workspaceMonitor.start()
        isSessionActive = workspaceMonitor.sessionIsLikelyActive
        health = .ready
        await reconcile(runningApplications: workspaceMonitor.runningApplications)
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await self.refreshSystemStatuses()
            await self.scheduleWarningsIfPossible()
        }
        Task { @MainActor [weak self] in
            await self?.refreshCatalog()
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

    private func nextBaseWindowStart(afterCurrentIntervalAt now: Date) -> Date? {
        resolver.nextWindowStart(
            for: configuration.schedule,
            afterCurrentIntervalAt: now,
            calendar: .autoupdatingCurrent
        )
    }

    private func reconcile(runningApplications: [NSRunningApplication]) async {
        transitionTask?.cancel()
        let now = nowProvider()
        resolvedSchedule = resolver.resolve(
            schedule: configuration.schedule,
            overrides: configuration.overrides,
            at: now,
            calendar: .autoupdatingCurrent,
            warnings: configuration.warningPreferences
        )
        await pruneTransientState(at: now)

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
                let snapshots = runningController.snapshots(runningApplications)
                if let selectedRunning = snapshots.first(where: { snapshot in
                    configuration.selectedApplications.contains {
                        planner.matches(selection: $0, process: snapshot)
                    }
                }) {
                    presentNotesIfNeeded(for: selectedRunning)
                }
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

        guard !configurationSaveInProgress else {
            return
        }
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
            configurationSaveInProgress = true
            defer { finishConfigurationSave() }
            configuration = try await configurationSaver(updated)
        } catch {
            HomewardLog.persistence.error("Transient state cleanup failed")
            lastError = "Expired temporary state could not be cleaned up."
        }
    }

    private func scheduleWarningsIfPossible() async {
        guard notificationStatus == .authorized else {
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
                applicationNames: configuration.selectedApplications.map(
                    \.displayName
                ),
                preferences: configuration.warningPreferences,
                includeExtension: configuration.closeMode == .gentle
                    && configuration.gentleShortcutExtensionEnabled
                    && !configuration.consumedGentleExtensionIntervalIDs.contains(
                        currentOrUpcomingBlockedIntervalID()
                    )
            )
        } catch {
            HomewardLog.lifecycle.error("Warning scheduling failed")
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
            let deadline = now.addingTimeInterval(EnforcementSession.firmGracePeriod)
            closingRows.append(ClosingRow(
                sessionID: target.id,
                enforcementIdentity: enforcementIdentity,
                applicationName: target.process.displayName,
                processIdentifier: target.process.processIdentifier,
                status: paused ? .forcePaused : .countingDown,
                secondsRemaining: paused ? nil : Int(EnforcementSession.firmGracePeriod)
            ))
            showClosingPanel()
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
                        Int(ceil(deadline.timeIntervalSince(self.nowProvider())))
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
                    try? await Task.sleep(
                        for: .seconds(HomewardPolicy.countdownTick)
                    )
                }
                guard !Task.isCancelled else {
                    return
                }
                await self.attemptForceTermination(
                    target: target,
                    deadline: deadline,
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
        deadline: Date,
        blockedIntervalID originalBlockedIntervalID: String
    ) async {
        let now = nowProvider()
        resolvedSchedule = resolver.resolve(
            schedule: configuration.schedule,
            overrides: configuration.overrides,
            at: now,
            calendar: .autoupdatingCurrent,
            warnings: configuration.warningPreferences
        )
        let session = EnforcementSession(
            mode: .firm,
            startedAt: deadline.addingTimeInterval(-EnforcementSession.firmGracePeriod),
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
        for task in enforcementTasks.values {
            task.cancel()
        }
        enforcementTasks.removeAll()
        announcedCountdownMilestones.removeAll()
        closingRows.removeAll()
        blockedLaunchTargets.removeAll()
        gentleExemptProcesses.removeAll()
        scheduledCloseHadTarget = false
        presentationCoordinator.closeClosing()
    }

    private func suspendForceEscalation() {
        for task in enforcementTasks.values {
            task.cancel()
        }
        enforcementTasks.removeAll()
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
            for task in enforcementTasks.values {
                task.cancel()
            }
            enforcementTasks.removeAll()
            closingRows.removeAll(where: {
                $0.status == .forcePaused || $0.status == .countingDown
            })
            refreshClosingPanel()
        }
        await reconcile(runningApplications: workspaceMonitor.runningApplications)
    }

    private func cancelEnforcement(forSelectionID id: UUID) {
        let matching = closingRows.filter { row in
            guard let target = targetForClosingRow(row) else {
                return false
            }
            return target.selectionID == id
        }
        for row in matching {
            enforcementTasks[row.id]?.cancel()
            enforcementTasks.removeValue(forKey: row.id)
            removeClosingRow(sessionID: row.id)
        }
    }

    private func targetForClosingRow(_ row: ClosingRow) -> EnforcementTarget? {
        let snapshots = runningController.snapshots(workspaceMonitor.runningApplications)
        return planner.targets(
            selections: configuration.selectedApplications,
            runningApplications: snapshots
        ).first(where: { $0.id == row.id })
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
            postCompletionStatus()
        }
    }

    private func showClosingPanel() {
        presentationCoordinator.showClosing(model: self)
    }

    private func showBlockedLaunchFeedback(for target: EnforcementTarget) {
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
                applicationName: target.process.displayName,
                availabilityText: availability
            )
        } else if notificationStatus == .authorized {
            Task {
                do {
                    try await notificationService.postStatus(
                        title: "\(target.process.displayName) is off for now",
                        body: availability
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
        let availability = resolvedSchedule.nextAvailability.map {
            "Selected apps are unavailable until \($0.formatted(date: .abbreviated, time: .shortened))."
        } ?? "No work window is scheduled."
        Task {
            do {
                try await notificationService.postStatus(
                    title: "Work is closed",
                    body: availability
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

    private func presentNotesIfNeeded(for process: RunningApplicationSnapshot) {
        guard resolvedSchedule.phase != .temporarilyExtended,
              configuration.selectedApplications.contains(where: {
                  planner.matches(selection: $0, process: process)
              }),
              let intervalID = resolvedSchedule.activeBaseInterval?.id,
              notes.notes.contains(where: {
                  $0.lastPresentedIntervalID != intervalID
              }),
              !presentedNoteIntervalIDs.contains(intervalID)
        else {
            return
        }
        presentedNoteIntervalIDs.insert(intervalID)
        showNotesReview()
    }

    private func handleLaunchSnapshot(_ snapshot: RunningApplicationSnapshot) {
        if handlePreviewLaunch(snapshot) {
            return
        }
        guard configuration.completedOnboarding else {
            return
        }
        let now = nowProvider()
        resolvedSchedule = resolver.resolve(
            schedule: configuration.schedule,
            overrides: configuration.overrides,
            at: now,
            calendar: .autoupdatingCurrent,
            warnings: configuration.warningPreferences
        )
        transitionTask?.cancel()
        scheduleNextTransition()
        if resolvedSchedule.isAvailable {
            presentNotesIfNeeded(for: snapshot)
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
}

extension AppModel: WorkspaceMonitorDelegate {
    func workspaceMonitor(
        _ monitor: WorkspaceMonitor,
        didLaunch application: NSRunningApplication
    ) {
        let snapshot = runningController.snapshot(application)
        guard snapshot.processSessionID != nil else {
            Task { @MainActor [weak self, weak application] in
                try? await Task.sleep(
                    for: .seconds(HomewardPolicy.launchMetadataRetryDelay)
                )
                guard !Task.isCancelled,
                      let self,
                      let application,
                      !application.isTerminated else {
                    return
                }
                self.handleLaunchSnapshot(
                    self.runningController.snapshot(application)
                )
            }
            return
        }
        handleLaunchSnapshot(snapshot)
    }

    func workspaceMonitor(
        _ monitor: WorkspaceMonitor,
        didTerminate application: NSRunningApplication
    ) {
        let snapshot = runningController.snapshot(application)
        if handlePreviewTermination(snapshot) {
            if let sessionID = snapshot.processSessionID {
                runningController.remove(sessionID: sessionID)
            }
            return
        }
        if let sessionID = snapshot.processSessionID {
            gentleExemptSessionIDs.remove(sessionID)
            removeClosingRow(sessionID: sessionID)
        } else {
            runningController.remove(
                processIdentifier: application.processIdentifier
            )
            closingRows.removeAll(where: {
                $0.processIdentifier == application.processIdentifier
            })
            refreshClosingPanel()
        }
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
        }
    }
}

extension AppModel: HomewardNotificationHandling {
    func handleNotificationAction(
        _ identifier: String,
        context: WarningActionContext?
    ) {
        guard identifier == HomewardNotificationService.startClosingAction
                || identifier == HomewardNotificationService.extendAction else {
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
        await waitForConfigurationSave()
        let now = nowProvider()
        let currentSchedule = resolver.resolve(
            schedule: configuration.schedule,
            overrides: configuration.overrides,
            at: now,
            calendar: .autoupdatingCurrent,
            warnings: configuration.warningPreferences
        )
        guard context?.isCurrent(for: currentSchedule, at: now) == true else {
            return
        }
        switch identifier {
        case HomewardNotificationService.startClosingAction:
            await endWorkNow()
        case HomewardNotificationService.extendAction:
            guard configuration.closeMode == .gentle,
                  configuration.gentleShortcutExtensionEnabled else {
                return
            }
            await useGentleShortcutExtension()
        default:
            break
        }
    }
}
