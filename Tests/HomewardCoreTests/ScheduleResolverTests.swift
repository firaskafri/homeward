import Foundation
import Testing
@testable import HomewardCore

// 1 - Name: Schedule resolver test file.
// 2 - Description: Verifies weekly schedule resolution, warnings, overrides, overnight windows, and DST boundaries.
// 3 - Assumptions: Tests use fixed calendars and time zones so host locale and clock cannot affect results.
// 4 - Expectations: Availability, phases, transitions, and validation remain deterministic at every tested boundary.

/// 1 - Name: Schedule resolver suite.
/// 2 - Description: Exercises pure schedule behavior without timers, persistence, or macOS framework state.
/// 3 - Assumptions: Work intervals are half-open and the schedule follows the supplied calendar time zone.
/// 4 - Expectations: The resolver derives current state and next transition solely from explicit inputs.
@Suite("Schedule resolver")
struct ScheduleResolverTests {

    /// 1 - Name: Default work-week boundaries.
    /// 2 - Description: Verifies the Monday-through-Friday 9:00–17:00 suggestion and blocked weekend.
    /// 3 - Assumptions: UTC has no DST transition on the tested dates.
    /// 4 - Expectations: Monday at 10:00 is available until 17:00 and Sunday is blocked.
    @Test
    func defaultWorkWeekBoundaries() throws {
        let schedule = try WeeklySchedule.defaultWorkWeek()
        let resolver = ScheduleResolver()
        let calendar = utcCalendar()
        let monday = date(2026, 9, 7, 10, 0, calendar: calendar)
        let sunday = date(2026, 9, 6, 10, 0, calendar: calendar)

        let mondayResult = resolver.resolve(
            schedule: schedule,
            overrides: [],
            at: monday,
            calendar: calendar,
            warnings: WarningPreferences()
        )
        let sundayResult = resolver.resolve(
            schedule: schedule,
            overrides: [],
            at: sunday,
            calendar: calendar,
            warnings: WarningPreferences()
        )

        #expect(mondayResult.phase == .workAvailable)
        #expect(mondayResult.isAvailable)
        #expect(mondayResult.nextTransition?.date == date(2026, 9, 7, 17, 0, calendar: calendar))
        #expect(sundayResult.phase == .workClosed)
        #expect(!sundayResult.isAvailable)
        #expect(sundayResult.nextAvailability == date(2026, 9, 7, 9, 0, calendar: calendar))
    }

    /// 1 - Name: Half-open cutoff boundary.
    /// 2 - Description: Checks the exact instant at which a scheduled work window becomes blocked.
    /// 3 - Assumptions: The cutoff is excluded from the available interval.
    /// 4 - Expectations: One second before cutoff is available and cutoff itself is blocked.
    @Test
    func cutoffBoundaryIsHalfOpen() throws {
        let schedule = try WeeklySchedule.defaultWorkWeek()
        let resolver = ScheduleResolver()
        let calendar = utcCalendar()

        let before = resolver.resolve(
            schedule: schedule,
            overrides: [],
            at: date(2026, 9, 7, 16, 59, 59, calendar: calendar),
            calendar: calendar,
            warnings: WarningPreferences()
        )
        let atCutoff = resolver.resolve(
            schedule: schedule,
            overrides: [],
            at: date(2026, 9, 7, 17, 0, calendar: calendar),
            calendar: calendar,
            warnings: WarningPreferences()
        )

        #expect(before.isAvailable)
        #expect(!atCutoff.isAvailable)
    }

    /// 1 - Name: Wind-down phase.
    /// 2 - Description: Verifies that the enabled fifteen-minute warning changes the visible phase.
    /// 3 - Assumptions: The underlying work window remains available during wind-down.
    /// 4 - Expectations: The phase is winding down at 16:50 while availability remains true.
    @Test
    func windDownPhase() throws {
        let calendar = utcCalendar()
        let result = ScheduleResolver().resolve(
            schedule: try WeeklySchedule.defaultWorkWeek(),
            overrides: [],
            at: date(2026, 9, 7, 16, 50, calendar: calendar),
            calendar: calendar,
            warnings: WarningPreferences()
        )

        #expect(result.phase == .windingDown)
        #expect(result.isAvailable)
    }

    /// 1 - Name: Explicit overnight window.
    /// 2 - Description: Resolves a Monday window that starts at 22:00 and ends Tuesday at 02:00.
    /// 3 - Assumptions: Tuesday is not blocked all day, satisfying cross-day validation.
    /// 4 - Expectations: Tuesday at 01:00 remains available and transitions at 02:00.
    @Test
    func overnightWindow() throws {
        let start = try LocalTime(hour: 22, minute: 0)
        let end = try LocalTime(hour: 2, minute: 0)
        var rules = blockedRules()
        rules[.monday] = .scheduled(start: start, end: end, endsNextDay: true)
        rules[.tuesday] = .scheduled(
            start: try LocalTime(hour: 9, minute: 0),
            end: try LocalTime(hour: 17, minute: 0),
            endsNextDay: false
        )
        let schedule = try WeeklySchedule(rules: rules)
        let calendar = utcCalendar()
        let result = ScheduleResolver().resolve(
            schedule: schedule,
            overrides: [],
            at: date(2026, 9, 8, 1, 0, calendar: calendar),
            calendar: calendar,
            warnings: WarningPreferences()
        )

        #expect(result.isAvailable)
        #expect(result.nextTransition?.date == date(2026, 9, 8, 2, 0, calendar: calendar))
    }

    /// 1 - Name: Availability override.
    /// 2 - Description: Applies a temporary extension during an otherwise blocked period.
    /// 3 - Assumptions: The newest active override controls availability until its explicit expiry.
    /// 4 - Expectations: The state is temporarily extended and the next transition is override expiry.
    @Test
    func availabilityOverride() throws {
        let calendar = utcCalendar()
        let now = date(2026, 9, 7, 18, 0, calendar: calendar)
        let expiry = date(2026, 9, 7, 18, 10, calendar: calendar)
        let override = try ScheduleOverride(
            kind: .fixedExtension,
            effect: .allow,
            effectiveAt: now,
            expiresAt: expiry
        )

        let result = ScheduleResolver().resolve(
            schedule: try WeeklySchedule.defaultWorkWeek(),
            overrides: [override],
            at: now,
            calendar: calendar,
            warnings: WarningPreferences()
        )

        #expect(result.phase == .temporarilyExtended)
        #expect(result.isAvailable)
        #expect(result.nextTransition == ScheduleTransition(date: expiry, cause: .overrideExpires))
    }

    /// 1 - Name: Force-pause override leaves schedule unchanged.
    /// 2 - Description: Verifies that a safety-only force pause does not grant or block application availability.
    /// 3 - Assumptions: Force-pause policy is enforced by the application coordinator, not the schedule resolver.
    /// 4 - Expectations: The weekly schedule remains authoritative for phase and next transition.
    @Test
    func forcePauseOverrideLeavesScheduleUnchanged() throws {
        let calendar = utcCalendar()
        let now = date(2026, 9, 7, 10, 0, calendar: calendar)
        let pause = try ScheduleOverride(
            kind: .forceEscalationPaused,
            effect: .unchanged,
            effectiveAt: now,
            expiresAt: date(2026, 9, 8, 9, 0, calendar: calendar)
        )

        let result = ScheduleResolver().resolve(
            schedule: try WeeklySchedule.defaultWorkWeek(),
            overrides: [pause],
            at: now,
            calendar: calendar,
            warnings: WarningPreferences()
        )

        #expect(result.phase == .workAvailable)
        #expect(result.nextTransition?.date == date(2026, 9, 7, 17, 0, calendar: calendar))
    }

    /// 1 - Name: Earlier custom cutoff.
    /// 2 - Description: Models availability until a custom cutoff followed by a blocked override.
    /// 3 - Assumptions: The paired overrides are committed atomically by the application layer.
    /// 4 - Expectations: Work is available before the cutoff and blocked immediately afterward.
    @Test
    func earlierCustomCutoff() throws {
        let calendar = utcCalendar()
        let start = date(2026, 9, 7, 10, 0, calendar: calendar)
        let cutoff = date(2026, 9, 7, 15, 0, calendar: calendar)
        let nextStart = date(2026, 9, 8, 9, 0, calendar: calendar)
        let allow = try ScheduleOverride(
            kind: .customCutoff,
            effect: .allow,
            effectiveAt: start,
            expiresAt: cutoff
        )
        let block = try ScheduleOverride(
            kind: .customCutoff,
            effect: .block,
            effectiveAt: cutoff,
            expiresAt: nextStart
        )
        let resolver = ScheduleResolver()
        let schedule = try WeeklySchedule.defaultWorkWeek()

        let before = resolver.resolve(
            schedule: schedule,
            overrides: [allow, block],
            at: date(2026, 9, 7, 14, 59, calendar: calendar),
            calendar: calendar,
            warnings: WarningPreferences()
        )
        let after = resolver.resolve(
            schedule: schedule,
            overrides: [allow, block],
            at: date(2026, 9, 7, 15, 0, calendar: calendar),
            calendar: calendar,
            warnings: WarningPreferences()
        )

        #expect(before.isAvailable)
        #expect(after.phase == .workClosed)
        #expect(after.nextTransition == ScheduleTransition(
            date: nextStart,
            cause: .overrideExpires
        ))
    }

    /// 1 - Name: Continuously available week.
    /// 2 - Description: Resolves seven available-all-day rules without exposing the finite scan horizon.
    /// 3 - Assumptions: Weekly recurrence has no blocked gap.
    /// 4 - Expectations: Work is available with no artificial next transition.
    @Test
    func continuouslyAvailableWeekHasNoArtificialCutoff() throws {
        let rules = Dictionary(
            uniqueKeysWithValues: Weekday.allCases.map {
                ($0, DayRule.availableAllDay)
            }
        )
        let calendar = utcCalendar()
        let result = ScheduleResolver().resolve(
            schedule: try WeeklySchedule(rules: rules),
            overrides: [],
            at: date(2026, 9, 7, 12, 0, calendar: calendar),
            calendar: calendar,
            warnings: WarningPreferences()
        )

        #expect(result.isAvailable)
        #expect(result.nextTransition == nil)
    }

    /// 1 - Name: Blocking override expires into active base window.
    /// 2 - Description: Blocks part of a scheduled window and reports override expiry as next availability.
    /// 3 - Assumptions: Base schedule remains available when the override expires.
    /// 4 - Expectations: Both next transition and next availability equal the override expiry.
    @Test
    func blockingOverrideExpiryIsNextAvailability() throws {
        let calendar = utcCalendar()
        let now = date(2026, 9, 7, 10, 0, calendar: calendar)
        let expiry = date(2026, 9, 7, 11, 0, calendar: calendar)
        let block = try ScheduleOverride(
            kind: .takeDayOff,
            effect: .block,
            effectiveAt: now,
            expiresAt: expiry
        )
        let result = ScheduleResolver().resolve(
            schedule: try WeeklySchedule.defaultWorkWeek(),
            overrides: [block],
            at: now,
            calendar: calendar,
            warnings: WarningPreferences()
        )

        #expect(!result.isAvailable)
        #expect(result.nextAvailability == expiry)
        #expect(result.nextTransition == ScheduleTransition(
            date: expiry,
            cause: .overrideExpires
        ))
    }

    /// 1 - Name: Blocked-interval boundary helpers.
    /// 2 - Description: Verifies the shared next-window, blocked-identity, and force-pause calculations.
    /// 3 - Assumptions: Monday after cutoff and Tuesday before opening belong to one blocked interval.
    /// 4 - Expectations: Both instants share an identifier and expire at Tuesday’s opening.
    @Test
    func blockedIntervalBoundaryHelpers() throws {
        let resolver = ScheduleResolver()
        let schedule = try WeeklySchedule.defaultWorkWeek()
        let calendar = utcCalendar()
        let mondayEvening = date(2026, 9, 7, 18, 0, calendar: calendar)
        let tuesdayMorning = date(2026, 9, 8, 8, 0, calendar: calendar)
        let nextOpening = date(2026, 9, 8, 9, 0, calendar: calendar)

        let mondayID = resolver.blockedIntervalID(
            for: schedule,
            at: mondayEvening,
            calendar: calendar
        )
        let tuesdayID = resolver.blockedIntervalID(
            for: schedule,
            at: tuesdayMorning,
            calendar: calendar
        )

        #expect(mondayID == tuesdayID)
        #expect(resolver.nextWindowStart(
            for: schedule,
            afterCurrentIntervalAt: mondayEvening,
            calendar: calendar
        ) == nextOpening)
        #expect(resolver.forcePauseExpiry(
            for: schedule,
            at: mondayEvening,
            calendar: calendar
        ) == nextOpening)
    }

    /// 1 - Name: Spring-forward schedule.
    /// 2 - Description: Resolves a window across the America/New_York DST gap.
    /// 3 - Assumptions: A nonexistent local boundary advances to the next valid wall-clock instant.
    /// 4 - Expectations: Resolution produces a valid interval and does not depend on a fixed 24-hour day.
    @Test
    func springForwardSchedule() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        var rules = blockedRules()
        rules[.sunday] = .scheduled(
            start: try LocalTime(hour: 1, minute: 30),
            end: try LocalTime(hour: 3, minute: 30),
            endsNextDay: false
        )
        let schedule = try WeeklySchedule(rules: rules)
        let result = ScheduleResolver().resolve(
            schedule: schedule,
            overrides: [],
            at: date(2026, 3, 8, 1, 45, calendar: calendar),
            calendar: calendar,
            warnings: WarningPreferences()
        )

        #expect(result.isAvailable)
        #expect(result.nextTransition?.date == date(2026, 3, 8, 3, 30, calendar: calendar))
    }

    /// 1 - Name: Contradictory overnight rule.
    /// 2 - Description: Validates that an overnight window cannot enter a day explicitly blocked all day.
    /// 3 - Assumptions: Blocked-all-day is an explicit policy boundary rather than an empty schedule placeholder.
    /// 4 - Expectations: Schedule construction reports the source and destination weekdays.
    @Test
    func overnightConflictIsRejected() throws {
        var rules = blockedRules()
        rules[.monday] = .scheduled(
            start: try LocalTime(hour: 22, minute: 0),
            end: try LocalTime(hour: 2, minute: 0),
            endsNextDay: true
        )

        #expect(throws: ValidationError.overnightConflictsWithBlockedDay(
            source: .monday,
            destination: .tuesday
        )) {
            _ = try WeeklySchedule(rules: rules)
        }
    }
}

private func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}

private func blockedRules() -> [Weekday: DayRule] {
    Dictionary(uniqueKeysWithValues: Weekday.allCases.map { ($0, .blockedAllDay) })
}

private func date(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    _ hour: Int,
    _ minute: Int,
    _ second: Int = 0,
    calendar: Calendar
) -> Date {
    calendar.date(from: DateComponents(
        timeZone: calendar.timeZone,
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: minute,
        second: second
    ))!
}
