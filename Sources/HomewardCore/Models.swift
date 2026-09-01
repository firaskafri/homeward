import Foundation

public enum Weekday: Int, Codable, CaseIterable, Comparable, Sendable {
    case sunday = 1
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct LocalTime: Codable, Equatable, Comparable, Hashable, Sendable {
    public let hour: Int
    public let minute: Int

    public init(hour: Int, minute: Int) throws {
        guard (0...23).contains(hour), (0...59).contains(minute) else {
            throw ValidationError.invalidLocalTime(hour: hour, minute: minute)
        }
        self.hour = hour
        self.minute = minute
    }

    public static func < (lhs: LocalTime, rhs: LocalTime) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }
}

public enum DayRule: Codable, Equatable, Sendable {
    case scheduled(start: LocalTime, end: LocalTime, endsNextDay: Bool)
    case availableAllDay
    case blockedAllDay
}

public struct WeeklySchedule: Codable, Equatable, Sendable {
    public private(set) var rules: [Weekday: DayRule]

    public init(rules: [Weekday: DayRule]) throws {
        guard Set(rules.keys) == Set(Weekday.allCases) else {
            throw ValidationError.incompleteWeek
        }
        self.rules = rules
        try validate()
    }

    public static func defaultWorkWeek() throws -> WeeklySchedule {
        let start = try LocalTime(hour: 9, minute: 0)
        let end = try LocalTime(hour: 17, minute: 0)
        var rules = Dictionary(
            uniqueKeysWithValues: Weekday.allCases.map { ($0, DayRule.blockedAllDay) }
        )
        for weekday in [Weekday.monday, .tuesday, .wednesday, .thursday, .friday] {
            rules[weekday] = .scheduled(start: start, end: end, endsNextDay: false)
        }
        return try WeeklySchedule(rules: rules)
    }

    public mutating func setRule(_ rule: DayRule, for weekday: Weekday) throws {
        let previous = rules[weekday]
        rules[weekday] = rule
        do {
            try validate()
        } catch {
            rules[weekday] = previous
            throw error
        }
    }

    public func rule(for weekday: Weekday) -> DayRule {
        rules[weekday] ?? .blockedAllDay
    }

    public func validate() throws {
        for weekday in Weekday.allCases {
            guard let rule = rules[weekday] else {
                throw ValidationError.incompleteWeek
            }
            guard case let .scheduled(start, end, endsNextDay) = rule else {
                continue
            }
            if start == end {
                throw ValidationError.equalScheduleBoundaries(weekday)
            }
            if endsNextDay {
                guard end < start else {
                    throw ValidationError.invalidOvernightWindow(weekday)
                }
                let nextWeekday = Weekday(rawValue: weekday.rawValue % 7 + 1)!
                if case .blockedAllDay = rules[nextWeekday] {
                    throw ValidationError.overnightConflictsWithBlockedDay(
                        source: weekday,
                        destination: nextWeekday
                    )
                }
            } else if end < start {
                throw ValidationError.sameDayWindowEndsBeforeStart(weekday)
            }
        }
    }
}

public enum CloseMode: String, Codable, Equatable, Sendable {
    case gentle
    case firm
}

public struct WarningPreferences: Codable, Equatable, Sendable {
    public var fifteenMinuteWarningEnabled: Bool
    public var fiveMinuteWarningEnabled: Bool
    public var gentleExtensionEnabled: Bool

    public init(
        fifteenMinuteWarningEnabled: Bool = true,
        fiveMinuteWarningEnabled: Bool = true,
        gentleExtensionEnabled: Bool = false
    ) {
        self.fifteenMinuteWarningEnabled = fifteenMinuteWarningEnabled
        self.fiveMinuteWarningEnabled = fiveMinuteWarningEnabled
        self.gentleExtensionEnabled = gentleExtensionEnabled
    }
}

public enum OverrideKind: String, Codable, Equatable, Sendable {
    case endWorkNow
    case fixedExtension
    case customCutoff
    case makeAvailable
    case takeDayOff
    case forceEscalationPaused
}

public enum AvailabilityEffect: String, Codable, Equatable, Sendable {
    case allow
    case block
    case unchanged
}

public struct ScheduleOverride: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kind: OverrideKind
    public let effect: AvailabilityEffect
    public let effectiveAt: Date
    public let expiresAt: Date
    public let relatedIntervalID: String?

    public init(
        id: UUID = UUID(),
        kind: OverrideKind,
        effect: AvailabilityEffect,
        effectiveAt: Date,
        expiresAt: Date,
        relatedIntervalID: String? = nil
    ) throws {
        guard expiresAt > effectiveAt else {
            throw ValidationError.invalidOverrideRange
        }
        self.id = id
        self.kind = kind
        self.effect = effect
        self.effectiveAt = effectiveAt
        self.expiresAt = expiresAt
        self.relatedIntervalID = relatedIntervalID
    }

    public func isActive(at date: Date) -> Bool {
        effectiveAt <= date && date < expiresAt
    }
}

public struct SelectedApplication: Codable, Equatable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var bundleIdentifier: String?
    public var bundlePath: String
    public var displayName: String
    public var developerName: String?
    public var isAvailable: Bool

    public init(
        id: UUID = UUID(),
        bundleIdentifier: String?,
        bundlePath: String,
        displayName: String,
        developerName: String? = nil,
        isAvailable: Bool = true
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.bundlePath = bundlePath
        self.displayName = displayName
        self.developerName = developerName
        self.isAvailable = isAvailable
    }

    public var stableSelectionKey: String {
        bundleIdentifier ?? URL(fileURLWithPath: bundlePath).standardizedFileURL.path
    }
}

public struct TomorrowNote: Codable, Equatable, Identifiable, Sendable {
    public static let maximumCharacterCount = 500

    public let id: UUID
    public var text: String
    public let createdAt: Date
    public var lastPresentedIntervalID: String?

    public init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = Date(),
        lastPresentedIntervalID: String? = nil
    ) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ValidationError.emptyNote
        }
        guard trimmed.count <= Self.maximumCharacterCount else {
            throw ValidationError.noteTooLong(maximum: Self.maximumCharacterCount)
        }
        self.id = id
        self.text = trimmed
        self.createdAt = createdAt
        self.lastPresentedIntervalID = lastPresentedIntervalID
    }
}

public enum ValidationError: Error, Equatable, Sendable {
    case invalidLocalTime(hour: Int, minute: Int)
    case incompleteWeek
    case equalScheduleBoundaries(Weekday)
    case sameDayWindowEndsBeforeStart(Weekday)
    case invalidOvernightWindow(Weekday)
    case overnightConflictsWithBlockedDay(source: Weekday, destination: Weekday)
    case invalidOverrideRange
    case emptyNote
    case noteTooLong(maximum: Int)
}
