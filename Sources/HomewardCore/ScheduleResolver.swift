import Foundation

public struct ScheduleInterval: Equatable, Sendable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    public var id: String {
        "\(start.timeIntervalSinceReferenceDate)-\(end.timeIntervalSinceReferenceDate)"
    }

    public func contains(_ date: Date) -> Bool {
        start <= date && date < end
    }
}

public enum SchedulePhase: String, Equatable, Sendable {
    case workAvailable
    case windingDown
    case workClosed
    case temporarilyExtended
}

public enum TransitionCause: String, Equatable, Sendable {
    case workWindowStarts
    case workWindowEnds
    case overrideExpires
}

public struct ScheduleTransition: Equatable, Sendable {
    public let date: Date
    public let cause: TransitionCause

    public init(date: Date, cause: TransitionCause) {
        self.date = date
        self.cause = cause
    }
}

public struct ResolvedSchedule: Equatable, Sendable {
    public let phase: SchedulePhase
    public let isAvailable: Bool
    public let activeBaseInterval: ScheduleInterval?
    public let activeOverride: ScheduleOverride?
    public let nextTransition: ScheduleTransition?
    public let nextAvailability: Date?
    public let warningOffsets: [TimeInterval]

    public init(
        phase: SchedulePhase,
        isAvailable: Bool,
        activeBaseInterval: ScheduleInterval?,
        activeOverride: ScheduleOverride?,
        nextTransition: ScheduleTransition?,
        nextAvailability: Date?,
        warningOffsets: [TimeInterval]
    ) {
        self.phase = phase
        self.isAvailable = isAvailable
        self.activeBaseInterval = activeBaseInterval
        self.activeOverride = activeOverride
        self.nextTransition = nextTransition
        self.nextAvailability = nextAvailability
        self.warningOffsets = warningOffsets
    }
}

public struct ScheduleResolver: Sendable {
    public init() {}

    public func resolve(
        schedule: WeeklySchedule,
        overrides: [ScheduleOverride],
        at now: Date,
        calendar inputCalendar: Calendar,
        warnings: WarningPreferences
    ) -> ResolvedSchedule {
        let calendar = inputCalendar
        let intervals = intervals(
            for: schedule,
            around: now,
            calendar: calendar
        )
        let baseInterval = intervals.first(where: { $0.contains(now) })
        let baseAvailable = baseInterval != nil
        let activeOverride = overrides
            .filter { $0.isActive(at: now) && $0.effect != .unchanged }
            .max(by: { $0.effectiveAt < $1.effectiveAt })

        let isAvailable: Bool
        switch activeOverride?.effect {
        case .allow:
            isAvailable = true
        case .block:
            isAvailable = false
        case .unchanged, nil:
            isAvailable = baseAvailable
        }

        let nextBaseStart = intervals.first(where: { $0.start > now })?.start
        let nextTransition: ScheduleTransition?
        if let activeOverride {
            nextTransition = ScheduleTransition(
                date: activeOverride.expiresAt,
                cause: .overrideExpires
            )
        } else if let baseInterval {
            nextTransition = ScheduleTransition(
                date: baseInterval.end,
                cause: .workWindowEnds
            )
        } else if let nextBaseStart {
            nextTransition = ScheduleTransition(
                date: nextBaseStart,
                cause: .workWindowStarts
            )
        } else {
            nextTransition = nil
        }

        let warningOffsets = enabledWarningOffsets(from: warnings)
        let phase: SchedulePhase
        if activeOverride?.effect == .allow {
            phase = .temporarilyExtended
        } else if isAvailable,
                  let cutoff = nextTransition?.date,
                  nextTransition?.cause == .workWindowEnds,
                  isInsideWarningPeriod(now: now, cutoff: cutoff, offsets: warningOffsets) {
            phase = .windingDown
        } else {
            phase = isAvailable ? .workAvailable : .workClosed
        }

        return ResolvedSchedule(
            phase: phase,
            isAvailable: isAvailable,
            activeBaseInterval: baseInterval,
            activeOverride: activeOverride,
            nextTransition: nextTransition,
            nextAvailability: isAvailable ? nil : nextBaseStart,
            warningOffsets: warningOffsets
        )
    }

    public func intervals(
        for schedule: WeeklySchedule,
        around date: Date,
        calendar: Calendar
    ) -> [ScheduleInterval] {
        let referenceDay = calendar.startOfDay(for: date)
        guard let firstDay = calendar.date(byAdding: .day, value: -8, to: referenceDay) else {
            return []
        }

        var rawIntervals: [ScheduleInterval] = []
        for offset in 0..<24 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay),
                  let weekday = Weekday(rawValue: calendar.component(.weekday, from: day))
            else {
                continue
            }

            switch schedule.rule(for: weekday) {
            case .blockedAllDay:
                continue
            case .availableAllDay:
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else {
                    continue
                }
                rawIntervals.append(ScheduleInterval(start: day, end: nextDay))
            case let .scheduled(start, end, endsNextDay):
                guard let startDate = boundaryDate(
                    on: day,
                    time: start,
                    repeatedTimePolicy: .first,
                    calendar: calendar
                ) else {
                    continue
                }
                let endDay: Date
                if endsNextDay {
                    guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else {
                        continue
                    }
                    endDay = nextDay
                } else {
                    endDay = day
                }
                guard let endDate = boundaryDate(
                    on: endDay,
                    time: end,
                    repeatedTimePolicy: .last,
                    calendar: calendar
                ), startDate < endDate
                else {
                    continue
                }
                rawIntervals.append(ScheduleInterval(start: startDate, end: endDate))
            }
        }

        return merge(rawIntervals.sorted(by: { $0.start < $1.start }))
    }

    private func enabledWarningOffsets(from preferences: WarningPreferences) -> [TimeInterval] {
        var offsets: [TimeInterval] = []
        if preferences.fifteenMinuteWarningEnabled {
            offsets.append(15 * 60)
        }
        if preferences.fiveMinuteWarningEnabled {
            offsets.append(5 * 60)
        }
        return offsets.sorted(by: >)
    }

    private func isInsideWarningPeriod(
        now: Date,
        cutoff: Date,
        offsets: [TimeInterval]
    ) -> Bool {
        guard let maximumOffset = offsets.max() else {
            return false
        }
        return now >= cutoff.addingTimeInterval(-maximumOffset) && now < cutoff
    }

    private func boundaryDate(
        on day: Date,
        time: LocalTime,
        repeatedTimePolicy: Calendar.RepeatedTimePolicy,
        calendar: Calendar
    ) -> Date? {
        var components = calendar.dateComponents([.era, .year, .month, .day], from: day)
        components.hour = time.hour
        components.minute = time.minute
        components.second = 0
        components.timeZone = calendar.timeZone
        guard let searchStart = calendar.date(byAdding: .second, value: -1, to: day) else {
            return nil
        }
        return calendar.nextDate(
            after: searchStart,
            matching: components,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: repeatedTimePolicy,
            direction: .forward
        )
    }

    private func merge(_ intervals: [ScheduleInterval]) -> [ScheduleInterval] {
        var result: [ScheduleInterval] = []
        for interval in intervals {
            guard let previous = result.last else {
                result.append(interval)
                continue
            }
            if interval.start <= previous.end {
                result[result.count - 1] = ScheduleInterval(
                    start: previous.start,
                    end: max(previous.end, interval.end)
                )
            } else {
                result.append(interval)
            }
        }
        return result
    }
}
