import Foundation
import Testing
@testable import HomewardCore

// 1 - Name: Schedule resolver test file.
// 2 - Description: Verifies weekly resolution, warning refreshes, deterministic overrides, overnight windows, and DST boundaries.
// 3 - Assumptions: Tests use fixed calendars and time zones so host locale and clock cannot affect results.
// 4 - Expectations: Availability, precedence, phases, transitions, and validation remain deterministic at tested boundaries.

/// 1 - Name: Schedule resolver suite.
/// 2 - Description: Exercises pure schedule behavior, including future policy refresh and civil-day boundaries.
/// 3 - Assumptions: Work intervals are half-open and the schedule follows the supplied calendar time zone.
/// 4 - Expectations: The resolver derives current state and the earliest policy transition solely from explicit inputs.
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

    /// 1 - Name: Warning-boundary refreshes.
    /// 2 - Description: Selects each enabled warning boundary before the final schedule cutoff.
    /// 3 - Assumptions: Warning offsets are measured backward from a work-window end transition.
    /// 4 - Expectations: Refresh advances from fifteen minutes to five minutes and then to cutoff.
    @Test
    func warningBoundariesDriveRefresh() throws {
        let calendar = utcCalendar()
        let resolver = ScheduleResolver()
        let schedule = try WeeklySchedule.defaultWorkWeek()
        let preferences = WarningPreferences()
        let beforeWarnings = date(2026, 9, 7, 16, 40, calendar: calendar)
        let atFifteen = date(2026, 9, 7, 16, 45, calendar: calendar)
        let atFive = date(2026, 9, 7, 16, 55, calendar: calendar)

        let initial = resolver.resolve(
            schedule: schedule,
            overrides: [],
            at: beforeWarnings,
            calendar: calendar,
            warnings: preferences
        )
        let windingDown = resolver.resolve(
            schedule: schedule,
            overrides: [],
            at: atFifteen,
            calendar: calendar,
            warnings: preferences
        )
        let finalWarning = resolver.resolve(
            schedule: schedule,
            overrides: [],
            at: atFive,
            calendar: calendar,
            warnings: preferences
        )

        #expect(resolver.nextRefreshDate(
            for: initial,
            after: beforeWarnings,
            warnings: preferences
        ) == atFifteen)
        #expect(resolver.nextRefreshDate(
            for: windingDown,
            after: atFifteen,
            warnings: preferences
        ) == atFive)
        #expect(resolver.nextRefreshDate(
            for: finalWarning,
            after: atFive,
            warnings: preferences
        ) == date(2026, 9, 7, 17, 0, calendar: calendar))
    }

    /// 1 - Name: Warning action generation and cutoff validation.
    /// 2 - Description: Accepts only an action tied to the current policy generation and future work-window cutoff.
    /// 3 - Assumptions: Notification actions carry the persisted generation and cutoff that produced their warning.
    /// 4 - Expectations: Changed generations, changed cutoffs, and actions handled at or after cutoff are rejected.
    @Test
    func warningActionRequiresCurrentCutoff() throws {
        let calendar = utcCalendar()
        let now = date(2026, 9, 7, 16, 50, calendar: calendar)
        let cutoff = date(2026, 9, 7, 17, 0, calendar: calendar)
        let resolved = ScheduleResolver().resolve(
            schedule: try WeeklySchedule.defaultWorkWeek(),
            overrides: [],
            at: now,
            calendar: calendar,
            warnings: WarningPreferences()
        )

        #expect(WarningActionContext(
            cutoff: cutoff,
            policyGeneration: 7
        ).isCurrent(
            for: resolved,
            policyGeneration: 7,
            at: now
        ))
        #expect(!WarningActionContext(
            cutoff: cutoff.addingTimeInterval(60),
            policyGeneration: 7
        ).isCurrent(for: resolved, policyGeneration: 7, at: now))
        #expect(!WarningActionContext(
            cutoff: cutoff,
            policyGeneration: 6
        ).isCurrent(for: resolved, policyGeneration: 7, at: now))
        #expect(!WarningActionContext(
            cutoff: cutoff,
            policyGeneration: 7
        ).isCurrent(
            for: resolved,
            policyGeneration: 7,
            at: cutoff
        ))
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

    /// 1 - Name: Equal-time override precedence.
    /// 2 - Description: Resolves conflicting active overrides with identical effective times in both input orders.
    /// 3 - Assumptions: Lexically greater UUID text has later precedence when effective times tie.
    /// 4 - Expectations: The same higher-UUID blocking override wins regardless of array order.
    @Test
    func equalTimeOverridesUseUUIDPrecedence() throws {
        let calendar = utcCalendar()
        let now = date(2026, 9, 7, 10, 0, calendar: calendar)
        let expiry = date(2026, 9, 7, 11, 0, calendar: calendar)
        let allow = try ScheduleOverride(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            kind: .fixedExtension,
            effect: .allow,
            effectiveAt: now,
            expiresAt: expiry
        )
        let block = try ScheduleOverride(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            kind: .takeDayOff,
            effect: .block,
            effectiveAt: now,
            expiresAt: expiry
        )
        let resolver = ScheduleResolver()
        let schedule = try WeeklySchedule.defaultWorkWeek()

        let forward = resolver.resolve(
            schedule: schedule,
            overrides: [allow, block],
            at: now,
            calendar: calendar,
            warnings: WarningPreferences()
        )
        let reversed = resolver.resolve(
            schedule: schedule,
            overrides: [block, allow],
            at: now,
            calendar: calendar,
            warnings: WarningPreferences()
        )

        #expect(forward.activeOverride == block)
        #expect(reversed.activeOverride == block)
        #expect(!forward.isAvailable)
        #expect(!reversed.isAvailable)
    }

    /// 1 - Name: Future override refresh.
    /// 2 - Description: Schedules refresh at an upcoming availability override before the base work-window cutoff.
    /// 3 - Assumptions: Force-pause overrides do not change availability and therefore do not require schedule refresh.
    /// 4 - Expectations: The base transition remains intact while the policy-changing effective time refreshes first.
    @Test
    func futurePolicyOverrideStartsNextRefresh() throws {
        let calendar = utcCalendar()
        let now = date(2026, 9, 7, 10, 0, calendar: calendar)
        let pauseStart = date(2026, 9, 7, 10, 30, calendar: calendar)
        let blockStart = date(2026, 9, 7, 11, 0, calendar: calendar)
        let blockEnd = date(2026, 9, 7, 12, 0, calendar: calendar)
        let pause = try ScheduleOverride(
            kind: .forceEscalationPaused,
            effect: .unchanged,
            effectiveAt: pauseStart,
            expiresAt: blockEnd,
            relatedIntervalID: "blocked-1"
        )
        let block = try ScheduleOverride(
            kind: .takeDayOff,
            effect: .block,
            effectiveAt: blockStart,
            expiresAt: blockEnd
        )
        let resolver = ScheduleResolver()
        let warnings = WarningPreferences()
        let resolved = resolver.resolve(
            schedule: try WeeklySchedule.defaultWorkWeek(),
            overrides: [pause, block],
            at: now,
            calendar: calendar,
            warnings: warnings
        )

        #expect(resolved.nextTransition == ScheduleTransition(
            date: date(2026, 9, 7, 17, 0, calendar: calendar),
            cause: .workWindowEnds
        ))
        #expect(resolved.nextOverrideEffectiveAt == blockStart)
        #expect(resolver.nextRefreshDate(
            for: resolved,
            after: now,
            warnings: warnings
        ) == blockStart)
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
            expiresAt: date(2026, 9, 8, 9, 0, calendar: calendar),
            relatedIntervalID: "blocked-test"
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

    /// 1 - Name: Overlapping blocking overrides.
    /// 2 - Description: Resolves a newer block that expires while an older block remains active.
    /// 3 - Assumptions: Override precedence follows effective time and the base schedule is available.
    /// 4 - Expectations: Transition and availability skip the newer expiry and use the final block expiry.
    @Test
    func overlappingBlocksUseActualAvailabilityBoundary() throws {
        let calendar = utcCalendar()
        let now = date(2026, 9, 7, 10, 0, calendar: calendar)
        let finalExpiry = date(2026, 9, 7, 12, 0, calendar: calendar)
        let olderBlock = try ScheduleOverride(
            kind: .takeDayOff,
            effect: .block,
            effectiveAt: date(2026, 9, 7, 9, 0, calendar: calendar),
            expiresAt: finalExpiry
        )
        let newerBlock = try ScheduleOverride(
            kind: .endWorkNow,
            effect: .block,
            effectiveAt: date(2026, 9, 7, 9, 30, calendar: calendar),
            expiresAt: date(2026, 9, 7, 11, 0, calendar: calendar)
        )

        let result = ScheduleResolver().resolve(
            schedule: try WeeklySchedule.defaultWorkWeek(),
            overrides: [olderBlock, newerBlock],
            at: now,
            calendar: calendar,
            warnings: WarningPreferences()
        )

        #expect(!result.isAvailable)
        #expect(result.nextAvailability == finalExpiry)
        #expect(result.nextTransition == ScheduleTransition(
            date: finalExpiry,
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
            overrides: [],
            at: mondayEvening,
            calendar: calendar
        )
        let tuesdayID = resolver.blockedIntervalID(
            for: schedule,
            overrides: [],
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
            overrides: [],
            at: mondayEvening,
            calendar: calendar
        ) == nextOpening)
    }

    /// 1 - Name: Override-defined blocked interval.
    /// 2 - Description: Derives Firm-pause identity and expiry from an active block over an always-available week.
    /// 3 - Assumptions: No weekly blocked boundary exists, so the override is the complete blocking cause.
    /// 4 - Expectations: The identifier follows the override and the pause expires with it.
    @Test
    func overrideDefinesBlockedInterval() throws {
        let resolver = ScheduleResolver()
        let calendar = utcCalendar()
        let now = date(2026, 9, 7, 12, 0, calendar: calendar)
        let expiry = date(2026, 9, 7, 17, 0, calendar: calendar)
        let overrideID = UUID()
        let block = try ScheduleOverride(
            id: overrideID,
            kind: .takeDayOff,
            effect: .block,
            effectiveAt: now,
            expiresAt: expiry
        )
        let rules = Dictionary(
            uniqueKeysWithValues: Weekday.allCases.map {
                ($0, DayRule.availableAllDay)
            }
        )
        let schedule = try WeeklySchedule(rules: rules)

        #expect(resolver.blockedIntervalID(
            for: schedule,
            overrides: [block],
            at: now,
            calendar: calendar
        ) == "override-\(overrideID.uuidString)")
        #expect(resolver.forcePauseExpiry(
            for: schedule,
            overrides: [block],
            at: now,
            calendar: calendar
        ) == expiry)
    }

    /// 1 - Name: Spring-forward schedule.
    /// 2 - Description: Resolves a window across the America/New_York DST gap.
    /// 3 - Assumptions: A nonexistent local boundary advances to the next valid wall-clock instant.
    /// 4 - Expectations: The scheduled interval remains available and ends at the requested post-gap local time.
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

    /// 1 - Name: Spring-forward next local day boundary.
    /// 2 - Description: Computes midnight after the short civil day without reusing resolver date helpers as the oracle.
    /// 3 - Assumptions: New York changes to UTC−04:00 on March 8, 2026, making next midnight epoch 1773028800.
    /// 4 - Expectations: The next boundary equals the literal epoch for March 9 at 00:00 local time.
    @Test
    func nextLocalDayBoundaryAcrossSpringForward() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))

        #expect(ScheduleResolver().nextLocalDayBoundary(
            after: date(2026, 3, 8, 1, 45, calendar: calendar),
            calendar: calendar
        ) == Date(timeIntervalSince1970: 1_773_028_800))
    }

    /// 1 - Name: Fall-back repeated-hour occurrences.
    /// 2 - Description: Resolves a Sunday window spanning both occurrences of 01:30 in New York.
    /// 3 - Assumptions: Starts use the first repeated wall time and ends use the last repeated wall time.
    /// 4 - Expectations: Both 01:45 occurrences are available and the interval ends at 02:30 standard time.
    @Test
    func fallBackWindowIncludesBothRepeatedOccurrences() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(
            TimeZone(identifier: "America/New_York")
        )
        var rules = blockedRules()
        rules[.sunday] = .scheduled(
            start: try LocalTime(hour: 1, minute: 30),
            end: try LocalTime(hour: 2, minute: 30),
            endsNextDay: false
        )
        let schedule = try WeeklySchedule(rules: rules)
        let resolver = ScheduleResolver()

        let firstOccurrence = resolver.resolve(
            schedule: schedule,
            overrides: [],
            at: Date(timeIntervalSince1970: 1_793_511_900),
            calendar: calendar,
            warnings: WarningPreferences()
        )
        let secondOccurrence = resolver.resolve(
            schedule: schedule,
            overrides: [],
            at: Date(timeIntervalSince1970: 1_793_515_500),
            calendar: calendar,
            warnings: WarningPreferences()
        )

        #expect(firstOccurrence.isAvailable)
        #expect(secondOccurrence.isAvailable)
        #expect(
            secondOccurrence.activeBaseInterval?.start
                == Date(timeIntervalSince1970: 1_793_511_000)
        )
        #expect(
            secondOccurrence.nextTransition?.date
                == Date(timeIntervalSince1970: 1_793_518_200)
        )
    }

    /// 1 - Name: Nonexistent spring-forward start.
    /// 2 - Description: Resolves a window whose requested 02:30 start does not exist on the DST transition day.
    /// 3 - Assumptions: The documented next-valid-time policy advances a nonexistent boundary.
    /// 4 - Expectations: The window begins at 03:00 and remains available through its 04:00 end.
    @Test
    func nonexistentStartAdvancesToNextValidTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(
            TimeZone(identifier: "America/New_York")
        )
        var rules = blockedRules()
        rules[.sunday] = .scheduled(
            start: try LocalTime(hour: 2, minute: 30),
            end: try LocalTime(hour: 4, minute: 0),
            endsNextDay: false
        )
        let result = ScheduleResolver().resolve(
            schedule: try WeeklySchedule(rules: rules),
            overrides: [],
            at: Date(timeIntervalSince1970: 1_772_954_100),
            calendar: calendar,
            warnings: WarningPreferences()
        )

        #expect(result.isAvailable)
        #expect(
            result.activeBaseInterval?.start
                == Date(timeIntervalSince1970: 1_772_953_200)
        )
        #expect(
            result.nextTransition?.date
                == Date(timeIntervalSince1970: 1_772_956_800)
        )
    }

    /// 1 - Name: Overnight spring-forward crossing.
    /// 2 - Description: Builds a Saturday overnight interval that crosses New York’s skipped hour.
    /// 3 - Assumptions: Weekly rules use wall-clock boundaries rather than fixed elapsed durations.
    /// 4 - Expectations: The 22:00–03:00 window lasts four elapsed hours and ends at the requested local boundary.
    @Test
    func overnightWindowCrossesSpringForwardTransition() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(
            TimeZone(identifier: "America/New_York")
        )
        var rules = blockedRules()
        rules[.saturday] = .scheduled(
            start: try LocalTime(hour: 22, minute: 0),
            end: try LocalTime(hour: 3, minute: 0),
            endsNextDay: true
        )
        rules[.sunday] = .scheduled(
            start: try LocalTime(hour: 9, minute: 0),
            end: try LocalTime(hour: 10, minute: 0),
            endsNextDay: false
        )
        let intervals = ScheduleResolver().intervals(
            for: try WeeklySchedule(rules: rules),
            around: Date(timeIntervalSince1970: 1_772_950_000),
            calendar: calendar
        )
        let transitionInterval = try #require(intervals.first {
            $0.start == Date(timeIntervalSince1970: 1_772_938_800)
        })

        #expect(
            transitionInterval.end
                == Date(timeIntervalSince1970: 1_772_953_200)
        )
        #expect(
            transitionInterval.end.timeIntervalSince(
                transitionInterval.start
            ) == 4 * 60 * 60
        )
    }

    /// 1 - Name: Fall-back midnight boundary.
    /// 2 - Description: Computes the next local midnight after New York’s 25-hour civil day begins.
    /// 3 - Assumptions: Midnight is calendar-derived and does not add a fixed 24-hour interval.
    /// 4 - Expectations: The boundary is November 2 at 00:00 standard time.
    @Test
    func nextLocalDayBoundaryAcrossFallBack() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(
            TimeZone(identifier: "America/New_York")
        )

        #expect(ScheduleResolver().nextLocalDayBoundary(
            after: Date(timeIntervalSince1970: 1_793_515_500),
            calendar: calendar
        ) == Date(timeIntervalSince1970: 1_793_595_600))
    }

    /// 1 - Name: Fall-back warning boundaries.
    /// 2 - Description: Resolves warning phase and refresh timing after the repeated hour has ended.
    /// 3 - Assumptions: Warning offsets are elapsed durations before the resolved 02:30 cutoff.
    /// 4 - Expectations: 02:20 is winding down and refreshes at the five-minute warning.
    @Test
    func warningsUseResolvedFallBackCutoff() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(
            TimeZone(identifier: "America/New_York")
        )
        var rules = blockedRules()
        rules[.sunday] = .scheduled(
            start: try LocalTime(hour: 1, minute: 30),
            end: try LocalTime(hour: 2, minute: 30),
            endsNextDay: false
        )
        let now = Date(timeIntervalSince1970: 1_793_517_600)
        let preferences = WarningPreferences()
        let resolver = ScheduleResolver()
        let result = resolver.resolve(
            schedule: try WeeklySchedule(rules: rules),
            overrides: [],
            at: now,
            calendar: calendar,
            warnings: preferences
        )

        #expect(result.phase == .windingDown)
        #expect(resolver.nextRefreshDate(
            for: result,
            after: now,
            warnings: preferences
        ) == Date(timeIntervalSince1970: 1_793_517_900))
    }

    /// 1 - Name: Override across time-zone change.
    /// 2 - Description: Resolves one absolute blocking override under two current local time zones.
    /// 3 - Assumptions: Override instants remain absolute while weekly schedule interpretation follows the supplied zone.
    /// 4 - Expectations: The same override blocks in both zones while later weekly availability follows each zone.
    @Test
    func overrideInstantsSurviveTimeZoneChange() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try #require(
            TimeZone(identifier: "America/New_York")
        )
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = try #require(
            TimeZone(identifier: "America/Los_Angeles")
        )
        let now = Date(timeIntervalSince1970: 1_789_000_000)
        let expiry = now.addingTimeInterval(45 * 60)
        let block = try ScheduleOverride(
            kind: .endWorkNow,
            effect: .block,
            effectiveAt: now.addingTimeInterval(-60),
            expiresAt: expiry
        )
        let resolver = ScheduleResolver()
        let schedule = try WeeklySchedule.defaultWorkWeek()

        let eastern = resolver.resolve(
            schedule: schedule,
            overrides: [block],
            at: now,
            calendar: newYork,
            warnings: WarningPreferences()
        )
        let pacific = resolver.resolve(
            schedule: schedule,
            overrides: [block],
            at: now,
            calendar: losAngeles,
            warnings: WarningPreferences()
        )

        #expect(!eastern.isAvailable)
        #expect(!pacific.isAvailable)
        #expect(eastern.activeOverride == block)
        #expect(pacific.activeOverride == block)
        #expect(eastern.nextAvailability != pacific.nextAvailability)
    }

    /// 1 - Name: Weekly schedule follows time-zone change.
    /// 2 - Description: Resolves the same absolute instant before and after changing the calendar time zone.
    /// 3 - Assumptions: Monday 21:00 UTC is after cutoff in New York and inside work hours in Los Angeles.
    /// 4 - Expectations: Availability changes with the Mac’s current wall-clock zone.
    @Test
    func weeklyScheduleFollowsCurrentTimeZone() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try #require(
            TimeZone(identifier: "America/New_York")
        )
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = try #require(
            TimeZone(identifier: "America/Los_Angeles")
        )
        let instant = date(
            2026,
            9,
            7,
            21,
            0,
            calendar: utcCalendar()
        )
        let resolver = ScheduleResolver()
        let schedule = try WeeklySchedule.defaultWorkWeek()

        let eastern = resolver.resolve(
            schedule: schedule,
            overrides: [],
            at: instant,
            calendar: newYork,
            warnings: WarningPreferences()
        )
        let pacific = resolver.resolve(
            schedule: schedule,
            overrides: [],
            at: instant,
            calendar: losAngeles,
            warnings: WarningPreferences()
        )

        #expect(!eastern.isAvailable)
        #expect(pacific.isAvailable)
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
