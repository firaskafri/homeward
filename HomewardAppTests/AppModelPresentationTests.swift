import AppKit
import Foundation
import Testing
@testable import Homeward
import HomewardCore

// 1 - Name: Homeward presentation test file.
// 2 - Description: Verifies panel priority, invoked-panel precedence, presentation state, and private thought visibility.
// 3 - Assumptions: Presentation tests use isolated model state and never automate an installed application.
// 4 - Expectations: Safety and recovery surfaces outrank passive feedback while sensitive content stays concealed.

/// 1 - Name: Homeward presentation suite.
/// 2 - Description: Covers window level, snapshot precedence, invoked/passive admission, and session-based thought redaction.
/// 3 - Assumptions: Presentation decisions are deterministic from model state and injected schedule time.
/// 4 - Expectations: Firm safety remains visible and saved-thought content appears only in an active base window.
@Suite("Homeward presentation")
@MainActor
struct AppModelPresentationTests {
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

    /// 1 - Name: Presentation precedence and counts.
    /// 2 - Description: Resolves recovery and Firm-pause snapshots with simultaneous passive attention.
    /// 3 - Assumptions: Recovery and Firm safety outrank schedule, thoughts, and readiness counts.
    /// 4 - Expectations: Semantic states and titles follow normative precedence without exposing thought content.
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
        #expect(recovery.state == .configurationRecovery)
        #expect(firmPause.title == "Force quit is paused")
        #expect(firmPause.state == .operational)
        #expect(firmPause.savedThoughtCount == 3)
        #expect(!firmPause.accessibilityValue.contains("thought text"))
    }

    /// 1 - Name: Today-only action availability.
    /// 2 - Description: Resolves shared Today actions for open and closed schedule states.
    /// 3 - Assumptions: Extension, availability, and override inputs are already derived from current model state.
    /// 4 - Expectations: Every surface receives the same ordered actions and shared confirmation copy.
    @Test
    func todayActionPresentationIsSharedAndOrdered() {
        let closedActions = TodayActionPresentation.actions(
            canExtendToday: true,
            isAvailable: false,
            hasAvailabilityOverride: true
        )
        let openActions = TodayActionPresentation.actions(
            canExtendToday: false,
            isAvailable: true,
            hasAvailabilityOverride: false
        )

        #expect(closedActions == [
            .extend(minutes: 10),
            .extend(minutes: 15),
            .extend(minutes: 30),
            .chooseCutoff,
            .makeAvailable,
            .takeDayOff,
            .returnToWeeklySchedule,
        ])
        #expect(openActions == [.chooseCutoff, .takeDayOff])
        #expect(
            TodayActionPresentation.takeDayOffConfirmationMessage
                .contains("configured closing flow now")
        )
        #expect(
            AppModel.PolicyConfirmationIntent.resumeFirmClosing
                .message(closeMode: .firm).contains(
                HomewardPolicy.firmGracePeriodDescription
            ) == true
        )
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

    /// 1 - Name: Invoked notes panels suppress passive readiness.
    /// 2 - Description: Resolves the shared save/error priority for explicit notes capture and review presentation.
    /// 3 - Assumptions: Invoked notes panels have the same priority as an active save or displayed error.
    /// 4 - Expectations: Thought-ready presentation is rejected for either condition and admitted only when both are absent.
    @Test
    func invokedNotesPanelsSuppressPassiveReadiness() {
        let saving = PresentationCoordinator.saveErrorOrInvokedPriority(
            hasSaveOrError: true,
            hasInvokedNotesPanel: false
        )
        let invoked = PresentationCoordinator.saveErrorOrInvokedPriority(
            hasSaveOrError: false,
            hasInvokedNotesPanel: true
        )
        let idle = PresentationCoordinator.saveErrorOrInvokedPriority(
            hasSaveOrError: false,
            hasInvokedNotesPanel: false
        )

        #expect(!PresentationCoordinator.permits(
            .thoughtAvailability,
            over: saving
        ))
        #expect(!PresentationCoordinator.permits(
            .thoughtAvailability,
            over: invoked
        ))
        #expect(PresentationCoordinator.permits(
            .thoughtAvailability,
            over: idle
        ))
    }
}
