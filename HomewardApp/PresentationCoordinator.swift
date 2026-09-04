@MainActor
final class PresentationCoordinator {
    private struct BlockedLaunchIdentity: Equatable {
        let applicationName: String
        let availabilityText: String
    }

    private var closingPanel: ClosingPanelController?
    private var blockedLaunchPanel: BlockedLaunchPanelController?
    private var blockedLaunchIdentity: BlockedLaunchIdentity?
    private var noteCapturePanel: NoteCapturePanelController?
    private var notesPanel: NotesPanelController?
    private var customCutoffPanel: CustomCutoffPanelController?
    private var todayChangePanel: TodayChangePanelController?

    var isClosingPanelVisible: Bool {
        closingPanel?.isVisibleAndUnoccluded == true
    }

    private var isClosingPanelPresented: Bool {
        closingPanel?.window?.isVisible == true
    }

    func showClosing(model: AppModel, activating: Bool = false) {
        if closingPanel == nil {
            closingPanel = ClosingPanelController(model: model)
        }
        closingPanel?.show(activating: activating)
    }

    func closeClosing() {
        closingPanel?.close()
    }

    func showBlockedLaunch(
        model: AppModel,
        applicationName: String,
        availabilityText: String
    ) {
        guard !isClosingPanelPresented else {
            return
        }
        let identity = BlockedLaunchIdentity(
            applicationName: applicationName,
            availabilityText: availabilityText
        )
        if blockedLaunchPanel?.window?.isVisible == true,
           blockedLaunchIdentity == identity {
            blockedLaunchPanel?.show()
            return
        }

        blockedLaunchPanel?.close()
        blockedLaunchPanel = BlockedLaunchPanelController(
            model: model,
            applicationName: applicationName,
            availabilityText: availabilityText
        )
        blockedLaunchIdentity = identity
        blockedLaunchPanel?.show()
    }

    func showNoteCapture(model: AppModel) {
        guard !isClosingPanelPresented else {
            return
        }
        if noteCapturePanel?.window?.isVisible == true {
            noteCapturePanel?.show()
            return
        }
        noteCapturePanel = NoteCapturePanelController(model: model)
        noteCapturePanel?.show()
    }

    func showNotes(model: AppModel) {
        guard !isClosingPanelPresented else {
            return
        }
        if notesPanel == nil {
            notesPanel = NotesPanelController(model: model)
        }
        notesPanel?.show()
    }

    func showCustomCutoff(model: AppModel) {
        if customCutoffPanel?.window?.isVisible == true {
            customCutoffPanel?.show()
            return
        }
        customCutoffPanel = CustomCutoffPanelController(model: model)
        customCutoffPanel?.show()
    }

    func showTodayChange(model: AppModel) {
        if todayChangePanel?.window?.isVisible == true {
            todayChangePanel?.show()
            return
        }
        todayChangePanel = TodayChangePanelController(model: model)
        todayChangePanel?.show()
    }
}
