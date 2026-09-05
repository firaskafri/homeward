import Foundation
import Testing
@testable import Homeward
import HomewardCore

// 1 - Name: Schedule editor presentation test file.
// 2 - Description: Verifies compact day summaries, grouped weekly lines, destination naming, and actionable validation copy.
// 3 - Assumptions: Presentation formatting receives valid domain values and a fixed English locale for deterministic text.
// 4 - Expectations: Every schedule mode is complete at a glance and invalid rules identify the affected weekdays.

/// 1 - Name: Schedule editor presentation suite.
/// 2 - Description: Covers the summary-first labels and validation messages shown by the native disclosure editor.
/// 3 - Assumptions: Domain validation remains owned by WeeklySchedule while this layer formats its typed errors.
/// 4 - Expectations: Collapsed rows and save errors communicate complete rules without changing domain enums.
@Suite("Schedule editor presentation")
@MainActor
struct ScheduleEditorPresentationTests {
    private let locale = Locale(identifier: "en_US")

    /// 1 - Name: Complete collapsed rule summaries.
    /// 2 - Description: Formats scheduled, overnight, available-all-day, and blocked domain rules.
    /// 3 - Assumptions: Times are valid and Monday's overnight destination is Tuesday.
    /// 4 - Expectations: Each summary is self-contained and blockedAllDay is presented as Closed all day.
    @Test
    func ruleSummariesDescribeCompleteAvailability() throws {
        let start = try LocalTime(hour: 9, minute: 0)
        let end = try LocalTime(hour: 17, minute: 0)
        let overnightEnd = try LocalTime(hour: 5, minute: 0)

        let scheduled = ScheduleEditorPresentation.ruleSummary(
            .scheduled(start: start, end: end, endsNextDay: false),
            for: .monday,
            locale: locale
        )
        let overnight = ScheduleEditorPresentation.ruleSummary(
            .scheduled(
                start: end,
                end: overnightEnd,
                endsNextDay: true
            ),
            for: .monday,
            locale: locale
        )

        #expect(scheduled.contains("9:00"))
        #expect(scheduled.contains("5:00"))
        #expect(!scheduled.contains("Tuesday"))
        #expect(overnight.contains("Tuesday"))
        #expect(
            ScheduleEditorPresentation.ruleSummary(
                .availableAllDay,
                for: .monday,
                locale: locale
            ) == "Available all day"
        )
        #expect(
            ScheduleEditorPresentation.ruleSummary(
                .blockedAllDay,
                for: .monday,
                locale: locale
            ) == "Closed all day"
        )
    }

    /// 1 - Name: Scan-friendly weekly summary lines.
    /// 2 - Description: Groups consecutive equal rules while retaining one string per visual line.
    /// 3 - Assumptions: The default schedule has weekdays scheduled and the weekend closed.
    /// 4 - Expectations: The result contains two separate lines with explicit range and availability text.
    @Test
    func weeklySummaryGroupsIntoSeparateLines() throws {
        let schedule = try WeeklySchedule.defaultWorkWeek()

        let lines = ScheduleEditorPresentation.weeklySummaryLines(
            rules: schedule.rules,
            locale: locale
        )

        #expect(lines.count == 2)
        #expect(lines[0].hasPrefix("Mon–Fri · "))
        #expect(lines[0].contains("9:00"))
        #expect(lines[0].contains("5:00"))
        #expect(lines[1] == "Sat–Sun · Closed all day")
    }

    /// 1 - Name: Weekday-specific validation guidance.
    /// 2 - Description: Formats boundary and overnight errors with their source and destination weekdays.
    /// 3 - Assumptions: WeeklySchedule supplies the typed weekday values associated with each invalid rule.
    /// 4 - Expectations: Messages identify where to edit and overnight conflicts use the visible Closed all day term.
    @Test
    func validationMessagesIdentifyAffectedDays() {
        let sameDay = ScheduleEditorPresentation.validation(
            for: ValidationError.sameDayWindowEndsBeforeStart(.monday),
            locale: locale
        )
        let conflict = ScheduleEditorPresentation.validation(
            for: ValidationError.overnightConflictsWithBlockedDay(
                source: .monday,
                destination: .tuesday
            ),
            locale: locale
        )

        #expect(sameDay.weekday == .monday)
        #expect(sameDay.message.contains("Monday"))
        #expect(sameDay.message.contains("Ends Tuesday"))
        #expect(conflict.weekday == .monday)
        #expect(
            conflict.message
                == "Monday ends Tuesday, but Tuesday is Closed all day."
        )
    }

    /// 1 - Name: Sunday overnight destination.
    /// 2 - Description: Resolves the cyclic weekday used by the final disclosure's checkbox.
    /// 3 - Assumptions: Weekday raw values follow Foundation's Sunday-first calendar ordering.
    /// 4 - Expectations: Sunday wraps to Monday without special UI state.
    @Test
    func sundayOvernightDestinationWrapsToMonday() {
        #expect(
            ScheduleEditorPresentation.nextWeekday(after: .sunday)
                == .monday
        )
    }
}
