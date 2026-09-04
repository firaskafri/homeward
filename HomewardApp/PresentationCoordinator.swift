import Foundation

@MainActor
final class PresentationCoordinator {
    private var closingPanel: ClosingPanelController?
    private var blockedLaunchPanel: BlockedLaunchPanelController?
    private var noteCapturePanel: NoteCapturePanelController?
    private var notesPanel: NotesPanelController?
    private var customCutoffPanel: CustomCutoffPanelController?
    private var todayChangePanel: TodayChangePanelController?

    var isClosingPanelVisible: Bool {
        closingPanel?.isVisible == true
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
        blockedLaunchPanel = BlockedLaunchPanelController(
            model: model,
            applicationName: applicationName,
            availabilityText: availabilityText
        )
        blockedLaunchPanel?.show()
    }

    func showNoteCapture(model: AppModel) {
        noteCapturePanel = NoteCapturePanelController(model: model)
        noteCapturePanel?.show()
    }

    func showNotes(model: AppModel) {
        if notesPanel == nil {
            notesPanel = NotesPanelController(model: model)
        }
        notesPanel?.show()
    }

    func showCustomCutoff(model: AppModel) {
        customCutoffPanel = CustomCutoffPanelController(model: model)
        customCutoffPanel?.show()
    }

    func showTodayChange(model: AppModel) {
        todayChangePanel = TodayChangePanelController(model: model)
        todayChangePanel?.show()
    }
}
