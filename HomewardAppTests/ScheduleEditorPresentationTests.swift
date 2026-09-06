import Foundation
import Testing
@testable import Homeward
import HomewardCore

// 1 - Name: Schedule editor presentation test file.
// 2 - Description: Verifies shared closing consequences, full and compact day summaries, weekly counts, localized time labels, destination naming, and actionable validation copy.
// 3 - Assumptions: Presentation formatting receives valid domain values and a fixed English locale for deterministic text.
// 4 - Expectations: Schedule controls remain concise and locale-aware, closing consequences stay consistent, and invalid rules identify the affected weekdays.

/// 1 - Name: Schedule editor presentation suite.
/// 2 - Description: Covers shared consequence copy, labels, aggregate counts, localized time values, and validation messages shown by the focused schedule editor.
/// 3 - Assumptions: Domain validation remains owned by WeeklySchedule while this layer formats its typed errors.
/// 4 - Expectations: Day tiles, focused controls, closing confirmations, and save errors communicate complete rules without changing domain enums.
@Suite("Schedule editor presentation")
@MainActor
struct ScheduleEditorPresentationTests {
    /// 1 - Name: Immediate-closing consequence copy.
    /// 2 - Description: Formats shared consequence text for Gentle and Firm policy changes.
    /// 3 - Assumptions: Callers provide the state-specific context sentence and the persisted close mode.
    /// 4 - Expectations: Every caller receives identical save timing language with the correct mode name.
    @Test
    func immediateClosingMessagesShareCanonicalCopy() {
        #expect(
            SchedulePresentation.immediateClosingMessage(
                context: "The current time is closed.",
                closeMode: .gentle
            )
                == "The current time is closed. Homeward will begin "
                + "Gentle Close after the change is saved."
        )
        #expect(
            SchedulePresentation.immediateClosingMessage(
                context: "The current time is closed.",
                closeMode: .firm
            )
                == "The current time is closed. Homeward will begin "
                + "Firm Close after the change is saved."
        )
    }

    private let locale = Locale(identifier: "en_US")

    /// 1 - Name: Complete rule summaries.
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

    /// 1 - Name: Compact day summaries.
    /// 2 - Description: Formats every rule for the constrained weekday tiles.
    /// 3 - Assumptions: The supplied British English locale uses a 24-hour time cycle.
    /// 4 - Expectations: Scheduled ranges remain exact, overnight ranges use +1, and all-day modes use short labels.
    @Test
    func compactRuleSummariesFitWeekdayTiles() throws {
        let start = try LocalTime(hour: 9, minute: 0)
        let end = try LocalTime(hour: 17, minute: 0)
        let locale = Locale(identifier: "en_GB")

        #expect(
            ScheduleEditorPresentation.compactRuleSummary(
                .scheduled(start: start, end: end, endsNextDay: false),
                locale: locale
            ) == "9:00–17:00"
        )
        #expect(
            ScheduleEditorPresentation.compactRuleSummary(
                .scheduled(start: start, end: end, endsNextDay: true),
                locale: locale
            ) == "9:00–17:00 +1"
        )
        #expect(
            ScheduleEditorPresentation.compactRuleSummary(
                .availableAllDay,
                locale: locale
            ) == "All day"
        )
        #expect(
            ScheduleEditorPresentation.compactRuleSummary(
                .blockedAllDay,
                locale: locale
            ) == "Closed"
        )
    }

    /// 1 - Name: Scan-friendly weekly summary.
    /// 2 - Description: Counts scheduled, all-day, and closed rules for the week card.
    /// 3 - Assumptions: The default schedule has weekdays scheduled and the weekend closed.
    /// 4 - Expectations: The result reports five scheduled days and two closed days without duplicating tile details.
    @Test
    func weekSummaryCountsAvailabilityModes() throws {
        let schedule = try WeeklySchedule.defaultWorkWeek()

        #expect(
            ScheduleEditorPresentation.weekSummary(rules: schedule.rules)
                == "5 days scheduled  •  2 days closed"
        )
    }

    /// 1 - Name: Singular and all-day weekly counts.
    /// 2 - Description: Formats a mixed week without exposing implementation-specific rule names.
    /// 3 - Assumptions: Missing rules are treated as closed consistently with the editor.
    /// 4 - Expectations: Singular day grammar and the all-day count remain concise and accurate.
    @Test
    func weekSummaryHandlesSingularAndAllDayRules() throws {
        let scheduled = try WeeklySchedule.defaultWorkdayRule()
        let summary = ScheduleEditorPresentation.weekSummary(
            rules: [
                .monday: scheduled,
                .tuesday: .availableAllDay,
            ]
        )

        #expect(
            summary
                == "1 day scheduled  •  1 day open all day  •  5 days closed"
        )
    }

    /// 1 - Name: Locale-aware time labels.
    /// 2 - Description: Formats complete times and hour menu options using caller-supplied locale conventions.
    /// 3 - Assumptions: en_US uses a 12-hour cycle while en_GB uses a 24-hour cycle.
    /// 4 - Expectations: The same domain time renders in the format expected by each locale.
    @Test
    func timeLabelsRespectLocaleHourCycles() throws {
        let time = try LocalTime(hour: 17, minute: 0)

        #expect(
            ScheduleEditorPresentation.formattedTime(
                time,
                locale: Locale(identifier: "en_GB")
            ) == "17:00"
        )
        #expect(
            ScheduleEditorPresentation.formattedHourLabels(
                locale: Locale(identifier: "en_US")
            )[17].contains("PM")
        )
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
    /// 2 - Description: Resolves the cyclic weekday used by the final day editor's overnight switch.
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
