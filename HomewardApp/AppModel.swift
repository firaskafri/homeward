import AppKit
import Combine
import Foundation
import HomewardCore
import OSLog

@MainActor
final class AppModel: NSObject, ObservableObject {
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
            case leftOpen
        }

        let id: String
        let applicationName: String
        let processIdentifier: Int32
        let blockedIntervalID: String
        var status: Status
        var deadline: Date?
        var secondsRemaining: Int?
    }

    enum Health: Equatable {
        case starting
        case ready
        case configurationUnavailable(String)
        case monitoringUnavailable(String)
    }

    @Published var configuration: HomewardConfiguration
    @Published var notes: NotesDocument
    @Published var resolvedSchedule: ResolvedSchedule
    @Published var catalog: [CatalogApplication] = []
    @Published var isCatalogLoading = false
    @Published var closingRows: [ClosingRow] = []
    @Published var health: Health = .starting
    @Published var notificationStatus: HomewardNotificationService.AuthorizationStatus = .notDetermined
    @Published var loginItemStatus: LoginItemService.Status = .notRegistered
    @Published var lastError: String? {
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
    @Published var isSessionActive = false
    @Published var previewState: PreviewState = .idle

    private let repository: HomewardRepository
    private let resolver = ScheduleResolver()
    private let planner = EnforcementPlanner()
    private let countdownAnnouncementPolicy = CountdownAnnouncementPolicy()
    private let workspaceMonitor = WorkspaceMonitor()
    private let runningController = RunningApplicationController()
    private let appCatalog = ApplicationCatalog()
    private let loginItemService = LoginItemService()
    private let notificationService = HomewardNotificationService()
    private let logger = Logger(
        subsystem: "com.firaskafri.homeward",
        category: "lifecycle"
    )

    private var transitionTask: Task<Void, Never>?
    private var enforcementTasks: [String: Task<Void, Never>] = [:]
    private var announcedCountdownMilestones: [String: Set<Int>] = [:]
    private var gentleExemptSessionIDs: Set<String> = []
    private var runtimeForcePauseIntervalIDs: Set<String> = []
    private var blockedLaunchTargets: [String: EnforcementTarget] = [:]
    private var lastBlockedFeedbackBySelection: [UUID: Date] = [:]
    private var scheduledCloseHadTarget = false
    private var closingPanelController: ClosingPanelController?
    private var blockedLaunchPanelController: BlockedLaunchPanelController?
    private var noteCapturePanelController: NoteCapturePanelController?
    private var notesPanelController: NotesPanelController?
    private var customCutoffPanelController: CustomCutoffPanelController?
    private var todayChangePanelController: TodayChangePanelController?
    private var presentedNoteIntervalIDs: Set<String> = []
    private var previewSelectionID: UUID?
    private var previewProcessSessionID: String?
    private var previewTimeoutTask: Task<Void, Never>?
    private var configurationSaveInProgress = false
    private var notesSaveInProgress = false
    private var started = false

    init(repository: HomewardRepository) throws {
        let initialConfiguration = try HomewardConfiguration.initial()
        self.repository = repository
        configuration = initialConfiguration
        notes = try NotesDocument()
        resolvedSchedule = ScheduleResolver().resolve(
            schedule: initialConfiguration.schedule,
            overrides: initialConfiguration.overrides,
            at: Date(),
            calendar: .autoupdatingCurrent,
            warnings: initialConfiguration.warningPreferences
        )
        super.init()
        workspaceMonitor.delegate = self
        notificationService.setHandler(self)
    }

    static func makeDefault() throws -> AppModel {
        if let storagePath = ProcessInfo.processInfo.environment[
            "HOMEWARD_STORAGE_DIRECTORY"
        ], !storagePath.isEmpty {
            return try AppModel(
                repository: HomewardRepository(
                    directoryURL: URL(fileURLWithPath: storagePath, isDirectory: true)
                )
            )
        }
        return try AppModel(repository: HomewardRepository())
    }

    var isOnboardingComplete: Bool {
        configuration.completedOnboarding
    }

    var forceEscalationPaused: Bool {
        let intervalID = blockedIntervalID(at: Date())
        return runtimeForcePauseIntervalIDs.contains(intervalID)
            || configuration.overrides.contains {
                $0.kind == .forceEscalationPaused
                    && $0.isActive(at: Date())
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
            health = .configurationUnavailable(error.localizedDescription)
            lastError = "App closing is paused because settings could not be verified."
            return
        }

        do {
            notes = try await repository.loadNotes()
        } catch {
            lastError = "Saved thoughts are unavailable. App closing still works."
        }

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
        isCatalogLoading = true
        catalog = appCatalog.discover()
        isCatalogLoading = false
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
            let isAvailable = match != nil
            if updated.selectedApplications[index].isAvailable != isAvailable {
                updated.selectedApplications[index].isAvailable = isAvailable
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
        loginItemStatus = loginItemService.status
    }

    func requestNotificationPermission() async {
        do {
            _ = try await notificationService.requestAuthorization()
            notificationStatus = await notificationService.authorizationStatus()
            await scheduleWarningsIfPossible()
        } catch {
            lastError = "Notifications could not be enabled. App closing still works."
        }
    }

    func enableStartAtLogin() {
        do {
            try loginItemService.enable()
            loginItemStatus = loginItemService.status
        } catch {
            lastError = "Start at Login could not be enabled."
        }
    }

    func disableStartAtLogin() {
        do {
            try loginItemService.disable()
            loginItemStatus = loginItemService.status
        } catch {
            lastError = "Start at Login could not be disabled."
        }
    }

    func openLoginItemSettings() {
        loginItemService.openSystemSettings()
    }

    func openNotificationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func completeOnboarding() async {
        guard configuration.onboardingScheduleConfirmed,
              !configuration.selectedApplications.isEmpty else {
            lastError = "Confirm the schedule and choose at least one work app."
            return
        }
        var updated = configuration
        updated.completedOnboarding = true
        if await commit(updated) {
            UserDefaults.standard.set(0, forKey: "onboardingStep")
        }
    }

    func markOnboardingScheduleDirty() {
        guard !configuration.completedOnboarding else {
            return
        }
        configuration.onboardingScheduleConfirmed = false
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
        _ = runningController.activate(sessionID: previewProcessSessionID)
    }

    func setCloseMode(_ mode: CloseMode) async {
        guard configuration.closeMode != mode else {
            return
        }
        var updated = configuration
        updated.closeMode = mode
        if mode == .gentle {
            cancelAllEnforcement()
        }
        if await commit(updated, reconcileAfterSave: false) {
            cancelAllEnforcement()
            await reconcile(runningApplications: workspaceMonitor.runningApplications)
        }
    }

    func setWarningPreferences(_ preferences: WarningPreferences) async {
        var updated = configuration
        updated.warningPreferences = preferences
        await commit(updated)
    }

    func setSchedule(_ schedule: WeeklySchedule) async {
        var updated = configuration
        updated.schedule = schedule
        if !updated.completedOnboarding {
            updated.onboardingScheduleConfirmed = true
        }
        await commit(updated)
    }

    func addApplication(_ application: SelectedApplication) async {
        guard !ApplicationCatalog.protectedBundleIdentifiers.contains(
            application.bundleIdentifier ?? ""
        ) else {
            lastError = "That system application cannot be managed by Homeward."
            return
        }
        guard !configuration.selectedApplications.contains(where: {
            $0.stableSelectionKey == application.stableSelectionKey
        }) else {
            lastError = "\(application.displayName) is already selected."
            return
        }
        var updated = configuration
        updated.selectedApplications.append(application)
        await commit(updated)
    }

    func removeApplication(id: UUID) async {
        cancelEnforcement(forSelectionID: id)
        var updated = configuration
        updated.selectedApplications.removeAll(where: { $0.id == id })
        await commit(updated)
    }

    func addApplication(at url: URL) async {
        guard !appCatalog.isProtected(url) else {
            lastError = "That system application cannot be managed by Homeward."
            return
        }
        guard let descriptor = appCatalog.descriptor(for: url) else {
            lastError = "The selected item is not a supported application."
            return
        }
        await addApplication(descriptor.selection)
    }

    func replaceApplication(id: UUID, with url: URL) async {
        guard !appCatalog.isProtected(url),
              let descriptor = appCatalog.descriptor(for: url),
              let index = configuration.selectedApplications.firstIndex(
                  where: { $0.id == id }
              ) else {
            lastError = "The selected item cannot replace this work app."
            return
        }
        let replacement = SelectedApplication(
            id: id,
            bundleIdentifier: descriptor.selection.bundleIdentifier,
            bundlePath: descriptor.selection.bundlePath,
            displayName: descriptor.selection.displayName,
            developerName: descriptor.selection.developerName,
            isAvailable: true
        )
        var updated = configuration
        updated.selectedApplications[index] = replacement
        await commit(updated)
    }

    func createExtension(minutes: Int) async {
        let now = Date()
        let extensionBase: Date
        if resolvedSchedule.isAvailable,
           let transition = resolvedSchedule.nextTransition {
            extensionBase = max(now, transition.date)
        } else {
            extensionBase = now
        }
        guard let expiresAt = Calendar.autoupdatingCurrent.date(
            byAdding: .minute,
            value: minutes,
            to: extensionBase
        ) else {
            return
        }
        do {
            let scheduleOverride = try ScheduleOverride(
                kind: .fixedExtension,
                effect: .allow,
                effectiveAt: now,
                expiresAt: expiresAt
            )
            var updated = configuration
            updated.overrides.removeAll(where: {
                $0.isActive(at: now) && $0.kind != .forceEscalationPaused
            })
            updated.overrides.append(scheduleOverride)
            await commit(updated)
        } catch {
            lastError = "The extension could not be created."
        }
    }

    func useGentleShortcutExtension() async {
        guard configuration.closeMode == .gentle,
              configuration.warningPreferences.gentleExtensionEnabled else {
            return
        }
        let intervalID = currentOrUpcomingBlockedIntervalID()
        guard !configuration.consumedGentleExtensionIntervalIDs.contains(intervalID) else {
            lastError = "The one-time Gentle extension has already been used for this blocked period."
            return
        }
        let now = Date()
        let extensionBase = resolvedSchedule.isAvailable
            ? max(now, resolvedSchedule.nextTransition?.date ?? now)
            : now
        guard let expiry = Calendar.autoupdatingCurrent.date(
            byAdding: .minute,
            value: 10,
            to: extensionBase
        ) else {
            return
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
            updated.consumedGentleExtensionIntervalIDs.insert(intervalID)
            updated.overrides.removeAll(where: {
                $0.isActive(at: now) && $0.kind != .forceEscalationPaused
            })
            updated.overrides.append(extensionOverride)
            await commit(updated)
        } catch {
            lastError = "The Gentle extension could not be created."
        }
    }

    func endWorkNow() async {
        let now = Date()
        let expiry = nextBaseWindowStart(afterCurrentIntervalAt: now) ?? Date.distantFuture
        do {
            let scheduleOverride = try ScheduleOverride(
                kind: .endWorkNow,
                effect: .block,
                effectiveAt: now,
                expiresAt: expiry
            )
            var updated = configuration
            updated.overrides.removeAll(where: {
                $0.isActive(at: now) && $0.kind != .forceEscalationPaused
            })
            updated.overrides.append(scheduleOverride)
            await commit(updated)
        } catch {
            lastError = "Work could not be ended early."
        }
    }

    func makeWorkAvailableNow() async {
        let now = Date()
        let expiry = nextBaseWindowStart(afterCurrentIntervalAt: now)
            ?? Calendar.autoupdatingCurrent.date(byAdding: .hour, value: 24, to: now)
            ?? Date.distantFuture
        await applyAvailabilityOverride(
            kind: .makeAvailable,
            effect: .allow,
            effectiveAt: now,
            expiresAt: expiry
        )
    }

    func chooseCutoff(_ cutoff: Date) async {
        let now = Date()
        let calendar = Calendar.autoupdatingCurrent
        let nextLocalMidnight = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: now)
        ) ?? now.addingTimeInterval(24 * 60 * 60)
        guard cutoff > now else {
            await endWorkNow()
            return
        }
        guard cutoff <= nextLocalMidnight else {
            lastError = "Choose a cutoff before the end of the current local day."
            return
        }
        let blockedUntil = nextBaseWindowStart(afterCurrentIntervalAt: cutoff)
            ?? Date.distantFuture
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
            updated.overrides.removeAll(where: {
                $0.kind != .forceEscalationPaused && $0.expiresAt > now
            })
            updated.overrides.append(contentsOf: [allow, block])
            await commit(updated)
        } catch {
            lastError = "The custom cutoff could not be saved."
        }
    }

    func takeTodayOff() async {
        let now = Date()
        let calendar = Calendar.autoupdatingCurrent
        let tomorrow = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: now)
        ) ?? now.addingTimeInterval(24 * 60 * 60)
        let intervals = resolver.intervals(
            for: configuration.schedule,
            around: now,
            calendar: calendar
        )
        let expiry = intervals.first(where: { $0.start >= tomorrow })?.start
            ?? tomorrow
        await applyAvailabilityOverride(
            kind: .takeDayOff,
            effect: .block,
            effectiveAt: now,
            expiresAt: expiry
        )
    }

    func returnToWeeklySchedule() async {
        var updated = configuration
        updated.overrides.removeAll(where: {
            $0.kind != .forceEscalationPaused
        })
        await commit(updated)
    }

    func stopForceQuit() async {
        runtimeForcePauseIntervalIDs.insert(blockedIntervalID(at: Date()))
        for task in enforcementTasks.values {
            task.cancel()
        }
        enforcementTasks.removeAll()
        announcedCountdownMilestones.removeAll()
        closingRows = closingRows.map { row in
            var updated = row
            if updated.status == .countingDown {
                updated.status = .forcePaused
                updated.deadline = nil
                updated.secondsRemaining = nil
            }
            return updated
        }

        let now = Date()
        let expiry = pausedForceOverrideExpiry(at: now)
        do {
            let pause = try ScheduleOverride(
                kind: .forceEscalationPaused,
                effect: .unchanged,
                effectiveAt: now,
                expiresAt: expiry,
                relatedIntervalID: blockedIntervalID(at: now)
            )
            var updated = configuration
            updated.overrides.removeAll(where: { $0.kind == .forceEscalationPaused })
            updated.overrides.append(pause)
            await commit(updated, reconcileAfterSave: false)
        } catch {
            lastError = "Force quit is paused while Homeward remains open, but the pause could not be saved."
        }
    }

    func resumeFirmClosing() async {
        var updated = configuration
        updated.overrides.removeAll(where: { $0.kind == .forceEscalationPaused })
        if await commit(updated, reconcileAfterSave: false) {
            runtimeForcePauseIntervalIDs.remove(blockedIntervalID(at: Date()))
            cancelAllEnforcement()
            await reconcile(runningApplications: workspaceMonitor.runningApplications)
        }
    }

    func bringForward(sessionID: String) {
        guard runningController.activate(sessionID: sessionID) else {
            lastError = "The application is no longer available."
            removeClosingRow(sessionID: sessionID)
            return
        }
    }

    func leaveOpen(sessionID: String) {
        enforcementTasks[sessionID]?.cancel()
        enforcementTasks.removeValue(forKey: sessionID)
        gentleExemptSessionIDs.insert(sessionID)
        removeClosingRow(sessionID: sessionID)
    }

    func hideClosingPanel() {
        if closingRows.contains(where: { $0.status == .countingDown }) {
            Task { await stopForceQuit() }
        }
        closingPanelController?.close()
    }

    func showClosingDetails() {
        if closingPanelController == nil {
            closingPanelController = ClosingPanelController(model: self)
        }
        closingPanelController?.show(activating: true)
    }

    func showNotesReview() {
        guard resolvedSchedule.isAvailable,
              resolvedSchedule.phase != .temporarilyExtended,
              !notes.notes.isEmpty else {
            return
        }
        if notesPanelController == nil {
            notesPanelController = NotesPanelController(model: self)
        }
        notesPanelController?.show()
    }

    func showNoteCapture() {
        lastError = nil
        noteCapturePanelController = NoteCapturePanelController(model: self)
        noteCapturePanelController?.show()
    }

    func showCustomCutoff() {
        customCutoffPanelController = CustomCutoffPanelController(model: self)
        customCutoffPanelController?.show()
    }

    func showTodayChangePanel() {
        todayChangePanelController = TodayChangePanelController(model: self)
        todayChangePanelController?.show()
    }

    func saveNote(_ text: String) async -> Bool {
        guard !notesSaveInProgress else {
            lastError = "Another saved-thought change is still in progress."
            return false
        }
        notesSaveInProgress = true
        defer { notesSaveInProgress = false }
        do {
            let note = try TomorrowNote(text: text)
            var updated = notes
            updated.append(note)
            try await repository.saveNotes(updated)
            notes = updated
            return true
        } catch {
            lastError = "The thought was not saved."
            return false
        }
    }

    func keepNote(id: UUID, intervalID: String) async {
        var updated = notes
        updated.keep(id: id, presentedIn: intervalID)
        await commitNotes(updated)
    }

    func removeNote(id: UUID) async {
        var updated = notes
        updated.remove(id: id)
        await commitNotes(updated)
    }

    func restoreNote(_ note: TomorrowNote) async {
        var updated = notes
        guard !updated.notes.contains(where: { $0.id == note.id }) else {
            return
        }
        updated.append(note)
        await commitNotes(updated)
    }

    func resetSetup() async {
        cancelAllEnforcement()
        do {
            let initial = try HomewardConfiguration.initial()
            try await repository.saveConfiguration(initial)
            configuration = initial
            UserDefaults.standard.set(0, forKey: "onboardingStep")
            resolvedSchedule = resolver.resolve(
                schedule: initial.schedule,
                overrides: [],
                at: Date(),
                calendar: .autoupdatingCurrent,
                warnings: initial.warningPreferences
            )
        } catch {
            lastError = "Setup could not be reset. App closing remains paused."
        }
    }

    func retryConfigurationLoad() async {
        do {
            configuration = try await repository.loadConfiguration()
                ?? HomewardConfiguration.initial()
            await completeRecoveredBootstrap()
        } catch {
            health = .configurationUnavailable(error.localizedDescription)
            lastError = "App closing is paused because settings could not be verified."
        }
    }

    func restorePreviousConfiguration() async {
        do {
            guard let candidate = try await repository.configurationRecoveryCandidate() else {
                lastError = "No previous settings are available."
                return
            }
            try await repository.replaceConfigurationDuringRecovery(candidate)
            configuration = candidate
            await completeRecoveredBootstrap()
        } catch {
            lastError = "Previous settings could not be restored. App closing remains paused."
        }
    }

    func replaceWithFreshSetup() async {
        do {
            let initial = try HomewardConfiguration.initial()
            try await repository.replaceConfigurationDuringRecovery(initial)
            configuration = initial
            UserDefaults.standard.set(0, forKey: "onboardingStep")
            await completeRecoveredBootstrap()
        } catch {
            lastError = "A fresh setup could not be saved. App closing remains paused."
        }
    }

    func resetSavedThoughts() async {
        do {
            try await repository.resetNotes()
            notes = try NotesDocument()
        } catch {
            lastError = "Saved thoughts could not be reset."
        }
    }

    func quit() {
        transitionTask?.cancel()
        for task in enforcementTasks.values {
            task.cancel()
        }
        Task { await notificationService.removeWarnings() }
        workspaceMonitor.stop()
        NSApplication.shared.terminate(nil)
    }

    func turnOff() async {
        do {
            try loginItemService.disable()
            quit()
        } catch {
            lastError = "Homeward could not disable Start at Login and remains on."
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
        defer { configurationSaveInProgress = false }
        do {
            var validated = updated
            try validated.validate()
            try await repository.saveConfiguration(validated)
            configuration = validated
            if reconcileAfterSave {
                await reconcile(runningApplications: workspaceMonitor.runningApplications)
            }
            return true
        } catch {
            lastError = "Changes could not be saved. No new app-closing policy was applied."
            return false
        }
    }

    private func commitNotes(_ updated: NotesDocument) async {
        guard !notesSaveInProgress else {
            lastError = "Another saved-thought change is still in progress."
            return
        }
        notesSaveInProgress = true
        defer { notesSaveInProgress = false }
        do {
            try await repository.saveNotes(updated)
            notes = updated
        } catch {
            lastError = "Saved thoughts could not be changed."
        }
    }

    private func schedulePreviewTimeout(applicationName: String) {
        previewTimeoutTask?.cancel()
        previewTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(60))
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
        _ snapshot: RunningApplicationSnapshot
    ) -> Bool {
        guard snapshot.processSessionID == previewProcessSessionID else {
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

    private func completeRecoveredBootstrap() async {
        lastError = nil
        do {
            notes = try await repository.loadNotes()
        } catch {
            lastError = "Saved thoughts are unavailable. App closing still works."
        }
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
    ) async {
        do {
            let scheduleOverride = try ScheduleOverride(
                kind: kind,
                effect: effect,
                effectiveAt: effectiveAt,
                expiresAt: expiresAt
            )
            var updated = configuration
            updated.overrides.removeAll(where: {
                $0.isActive(at: effectiveAt) && $0.kind != .forceEscalationPaused
            })
            updated.overrides.append(scheduleOverride)
            await commit(updated)
        } catch {
            lastError = "Today’s schedule could not be changed."
        }
    }

    private func nextBaseWindowStart(afterCurrentIntervalAt now: Date) -> Date? {
        let intervals = resolver.intervals(
            for: configuration.schedule,
            around: now,
            calendar: .autoupdatingCurrent
        )
        if let current = intervals.first(where: { $0.contains(now) }) {
            return intervals.first(where: { $0.start >= current.end })?.start
        }
        return intervals.first(where: { $0.start > now })?.start
    }

    private func reconcile(runningApplications: [NSRunningApplication]) async {
        transitionTask?.cancel()
        let now = Date()
        resolvedSchedule = resolver.resolve(
            schedule: configuration.schedule,
            overrides: configuration.overrides,
            at: now,
            calendar: .autoupdatingCurrent,
            warnings: configuration.warningPreferences
        )

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

    private func scheduleWarningsIfPossible() async {
        guard notificationStatus == .authorized else {
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
                applicationNames: configuration.selectedApplications.map(\.displayName),
                preferences: configuration.warningPreferences,
                includeExtension: configuration.closeMode == .gentle
                    && configuration.warningPreferences.gentleExtensionEnabled
                    && !configuration.consumedGentleExtensionIntervalIDs.contains(
                        currentOrUpcomingBlockedIntervalID()
                    )
            )
        } catch {
            lastError = "Wind-down notifications could not be scheduled. App closing still works."
        }
    }

    private func scheduleNextTransition() {
        guard let transition = resolvedSchedule.nextTransition,
              transition.date > Date()
        else {
            return
        }
        let delay = transition.date.timeIntervalSinceNow
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
        let targets = planner.targets(
            selections: configuration.selectedApplications,
            runningApplications: snapshots
        ).filter { !gentleExemptSessionIDs.contains($0.id) }
        for target in targets where closingRows.contains(where: { $0.id == target.id }) == false {
            beginEnforcement(target: target, now: now)
        }
    }

    private func beginEnforcement(target: EnforcementTarget, now: Date) {
        let intervalID = blockedIntervalID(at: now)
        if blockedLaunchTargets[target.id] == nil {
            scheduledCloseHadTarget = true
        }
        let normalRequestAccepted = runningController.requestNormalTermination(
            for: target.id
        )
        switch configuration.closeMode {
        case .gentle:
            let row = ClosingRow(
                id: target.id,
                applicationName: target.process.displayName,
                processIdentifier: target.process.processIdentifier,
                blockedIntervalID: intervalID,
                status: normalRequestAccepted ? .requestingNormalQuit : .needsAttention,
                deadline: nil,
                secondsRemaining: nil
            )
            closingRows.append(row)
            if !normalRequestAccepted {
                showClosingPanel()
                return
            }
            enforcementTasks[target.id] = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(5))
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
                id: target.id,
                applicationName: target.process.displayName,
                processIdentifier: target.process.processIdentifier,
                blockedIntervalID: intervalID,
                status: paused ? .forcePaused : .countingDown,
                deadline: paused ? nil : deadline,
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
                    let remaining = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
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
                    try? await Task.sleep(for: .seconds(1))
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

    private func attemptForceTermination(
        target: EnforcementTarget,
        deadline: Date,
        blockedIntervalID originalBlockedIntervalID: String
    ) async {
        let now = Date()
        resolvedSchedule = resolver.resolve(
            schedule: configuration.schedule,
            overrides: configuration.overrides,
            at: now,
            calendar: .autoupdatingCurrent,
            warnings: configuration.warningPreferences
        )
        let session = EnforcementSession(
            blockedIntervalID: originalBlockedIntervalID,
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
        guard isSessionActive, closingPanelController?.isVisible == true else {
            suspendForceEscalation()
            return
        }

        let accepted = runningController.requestForceTermination(for: target.id)
        try? await Task.sleep(for: .seconds(2))
        if accepted && runningController.isTerminated(sessionID: target.id) {
            removeClosingRow(sessionID: target.id)
        } else {
            updateClosingRow(sessionID: target.id) {
                $0.status = .forceFailed
                $0.deadline = nil
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
        gentleExemptSessionIDs.removeAll()
        scheduledCloseHadTarget = false
        closingPanelController?.close()
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
                updated.deadline = nil
                updated.secondsRemaining = nil
            }
            return updated
        }
        refreshClosingPanel()
    }

    private func restartFirmClosingAfterSessionActivation() async {
        guard configuration.closeMode == .firm,
              !forceEscalationPaused,
              !resolvedSchedule.isAvailable else {
            return
        }
        for task in enforcementTasks.values {
            task.cancel()
        }
        enforcementTasks.removeAll()
        closingRows.removeAll(where: {
            $0.status == .forcePaused || $0.status == .countingDown
        })
        refreshClosingPanel()
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
        sessionID: String,
        update: (inout ClosingRow) -> Void
    ) {
        guard let index = closingRows.firstIndex(where: { $0.id == sessionID }) else {
            return
        }
        update(&closingRows[index])
        refreshClosingPanel()
    }

    private func removeClosingRow(sessionID: String) {
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
        if closingPanelController == nil {
            closingPanelController = ClosingPanelController(model: self)
        }
        closingPanelController?.show()
    }

    private func showBlockedLaunchFeedback(for target: EnforcementTarget) {
        let now = Date()
        let lastFeedback = lastBlockedFeedbackBySelection[target.selectionID]
        lastBlockedFeedbackBySelection[target.selectionID] = now
        let availability = resolvedSchedule.nextAvailability.map {
            "Available \($0.formatted(date: .abbreviated, time: .shortened))."
        } ?? "No work window is scheduled."

        let shouldShowPanel = lastFeedback.map {
            now.timeIntervalSince($0) >= 10 * 60
        } ?? true
        if shouldShowPanel {
            blockedLaunchPanelController = BlockedLaunchPanelController(
                model: self,
                applicationName: target.process.displayName,
                availabilityText: availability
            )
            blockedLaunchPanelController?.show()
        } else if notificationStatus == .authorized {
            Task {
                try? await notificationService.postStatus(
                    title: "\(target.process.displayName) is off for now",
                    body: availability
                )
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
            try? await notificationService.postStatus(
                title: "Work is closed",
                body: availability
            )
        }
    }

    private func refreshClosingPanel() {
        if closingRows.isEmpty {
            closingPanelController?.close()
        } else {
            closingPanelController?.refresh()
        }
    }

    private func announceCountdownIfNeeded(
        sessionID: String,
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
        let intervals = resolver.intervals(
            for: configuration.schedule,
            around: date,
            calendar: .autoupdatingCurrent
        )
        let current = intervals.first(where: { $0.contains(date) })
        let blockedStart = current?.end
            ?? intervals.last(where: { $0.end <= date })?.end
            ?? Date.distantPast
        let nextStart = intervals.first(where: {
            if let current {
                return $0.start >= current.end
            }
            return $0.start > date
        })?.start ?? Date.distantFuture
        return "blocked-\(blockedStart.timeIntervalSinceReferenceDate)-\(nextStart.timeIntervalSinceReferenceDate)"
    }

    private func currentOrUpcomingBlockedIntervalID() -> String {
        blockedIntervalID(at: Date())
    }

    private func pausedForceOverrideExpiry(at date: Date) -> Date {
        let intervals = resolver.intervals(
            for: configuration.schedule,
            around: date,
            calendar: .autoupdatingCurrent
        )
        if let current = intervals.first(where: { $0.contains(date) }) {
            return intervals.first(where: { $0.start >= current.end })?.start
                ?? Date.distantFuture
        }
        return intervals.first(where: { $0.start > date })?.start
            ?? Date.distantFuture
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
        let now = Date()
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
                try? await Task.sleep(for: .milliseconds(250))
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
    func handleNotificationAction(_ identifier: String) {
        switch identifier {
        case HomewardNotificationService.startClosingAction:
            Task { await endWorkNow() }
        case HomewardNotificationService.extendAction:
            guard configuration.closeMode == .gentle,
                  configuration.warningPreferences.gentleExtensionEnabled else {
                return
            }
            Task { await useGentleShortcutExtension() }
        default:
            break
        }
    }
}
