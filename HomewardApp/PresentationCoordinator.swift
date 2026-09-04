@MainActor
final class PresentationCoordinator {
    enum Priority: Int, Comparable {
        case thoughtAvailability
        case blockedLaunch
        case saveOrError
        case firmSafety
        case recovery

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    static func permits(
        _ requested: Priority,
        over current: Priority?
    ) -> Bool {
        guard let current else {
            return true
        }
        return current <= requested
    }

    private struct BlockedLaunchIdentity: Equatable {
        let availabilityText: String
    }

    private var closingPanel: ClosingPanelController?
    private var blockedLaunchPanel: BlockedLaunchPanelController?
    private var blockedLaunchIdentity: BlockedLaunchIdentity?
    private var notesReadyPanel: NotesReadyPanelController?
    private var noteCapturePanel: NoteCapturePanelController?
    private var notesPanel: NotesPanelController?
    private var customCutoffPanel: CustomCutoffPanelController?
    private var todayChangePanel: TodayChangePanelController?
    private var recoveryIsActive = false
    private(set) var activePriority: Priority?

    var isClosingPanelVisible: Bool {
        closingPanel?.isVisibleAndUnoccluded == true
    }

    private var isClosingPanelPresented: Bool {
        closingPanel?.window?.isVisible == true
    }

    private var isInvokedPanelPresented: Bool {
        noteCapturePanel?.window?.isVisible == true
            || notesPanel?.window?.isVisible == true
    }

    func showClosing(model: AppModel, activating: Bool = false) {
        closePassiveAndSensitivePanels()
        if activating {
            activePriority = .firmSafety
        }
        if closingPanel == nil {
            closingPanel = ClosingPanelController(model: model)
        }
        closingPanel?.show(activating: activating)
    }

    func closeClosing() {
        closingPanel?.close()
        closingPanel = nil
        if activePriority == .firmSafety {
            activePriority = nil
        }
    }

    func showBlockedLaunch(
        model: AppModel,
        availabilityText: String
    ) {
        guard allows(.blockedLaunch),
              !isClosingPanelPresented,
              !model.hasPrioritySaveOrErrorPresentation,
              !isInvokedPanelPresented else {
            return
        }
        let identity = BlockedLaunchIdentity(
            availabilityText: availabilityText
        )
        if blockedLaunchPanel?.window?.isVisible == true,
           blockedLaunchIdentity == identity {
            blockedLaunchPanel?.show()
            return
        }

        notesReadyPanel?.close()
        notesReadyPanel = nil
        blockedLaunchPanel?.close()
        blockedLaunchPanel = BlockedLaunchPanelController(
            model: model,
            availabilityText: availabilityText
        )
        blockedLaunchIdentity = identity
        activePriority = .blockedLaunch
        blockedLaunchPanel?.show()
    }

    func showNoteCapture(model: AppModel) {
        guard allows(.saveOrError), !isClosingPanelPresented else {
            return
        }
        blockedLaunchPanel?.close()
        blockedLaunchPanel = nil
        notesReadyPanel?.close()
        notesReadyPanel = nil
        if noteCapturePanel?.window?.isVisible == true {
            noteCapturePanel?.show()
            return
        }
        noteCapturePanel = NoteCapturePanelController(model: model)
        noteCapturePanel?.show()
    }

    func showNotes(model: AppModel) {
        guard allows(.saveOrError), !isClosingPanelPresented else {
            return
        }
        blockedLaunchPanel?.close()
        blockedLaunchPanel = nil
        notesReadyPanel?.close()
        notesReadyPanel = nil
        if notesPanel == nil {
            notesPanel = NotesPanelController(model: model)
        }
        notesPanel?.show()
    }

    func showNotesReady(model: AppModel, count: Int) {
        guard allows(.thoughtAvailability),
              !isClosingPanelPresented,
              !model.hasPrioritySaveOrErrorPresentation,
              count > 0 else {
            return
        }
        notesReadyPanel?.close()
        notesReadyPanel = NotesReadyPanelController(model: model, count: count)
        activePriority = .thoughtAvailability
        notesReadyPanel?.show()
    }

    func dismissSensitivePresentations(restoringFocus: Bool = false) {
        if restoringFocus {
            noteCapturePanel?.close()
            notesPanel?.close()
        } else {
            noteCapturePanel?.closeWithoutRestoringFocus()
            notesPanel?.closeWithoutRestoringFocus()
        }
        notesReadyPanel?.close()
        noteCapturePanel = nil
        notesPanel = nil
        notesReadyPanel = nil
    }

    func setRecoveryActive(_ isActive: Bool) {
        recoveryIsActive = isActive
        guard isActive else {
            if activePriority == .recovery {
                activePriority = nil
            }
            return
        }
        activePriority = .recovery
        closingPanel?.close()
        closingPanel = nil
        blockedLaunchPanel?.close()
        blockedLaunchPanel = nil
        blockedLaunchIdentity = nil
        dismissSensitivePresentations()
        customCutoffPanel?.close()
        customCutoffPanel = nil
        todayChangePanel?.close()
        todayChangePanel = nil
    }

    func showCustomCutoff(model: AppModel) {
        guard !recoveryIsActive, !isClosingPanelPresented else {
            return
        }
        if customCutoffPanel?.window?.isVisible == true {
            customCutoffPanel?.show()
            return
        }
        customCutoffPanel = CustomCutoffPanelController(model: model)
        customCutoffPanel?.show()
    }

    func showTodayChange(model: AppModel) {
        guard !recoveryIsActive else {
            return
        }
        if todayChangePanel?.window?.isVisible == true {
            todayChangePanel?.show()
            return
        }
        todayChangePanel = TodayChangePanelController(model: model)
        todayChangePanel?.show()
    }

    private func closePassiveAndSensitivePanels() {
        blockedLaunchPanel?.close()
        blockedLaunchPanel = nil
        blockedLaunchIdentity = nil
        dismissSensitivePresentations(restoringFocus: true)
    }

    private func allows(_ requested: Priority) -> Bool {
        guard !recoveryIsActive else {
            return false
        }
        if activePriority == .blockedLaunch,
           blockedLaunchPanel?.window?.isVisible != true {
            activePriority = nil
        }
        if activePriority == .thoughtAvailability,
           notesReadyPanel?.window?.isVisible != true {
            activePriority = nil
        }
        return Self.permits(requested, over: activePriority)
    }
}
