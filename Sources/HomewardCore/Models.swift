import Foundation

public enum Weekday: Int, Codable, CaseIterable, Sendable {
    case sunday = 1
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
}

public struct LocalTime: Codable, Equatable, Comparable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case hour
        case minute
    }

    public let hour: Int
    public let minute: Int

    public init(hour: Int, minute: Int) throws {
        self.hour = hour
        self.minute = minute
        try validate()
    }

    public static func < (lhs: LocalTime, rhs: LocalTime) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }

    public func validate() throws {
        guard (0...23).contains(hour), (0...59).contains(minute) else {
            throw ValidationError.invalidLocalTime(hour: hour, minute: minute)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            hour: container.decode(Int.self, forKey: .hour),
            minute: container.decode(Int.self, forKey: .minute)
        )
    }
}

public enum DayRule: Codable, Equatable, Sendable {
    case scheduled(start: LocalTime, end: LocalTime, endsNextDay: Bool)
    case availableAllDay
    case blockedAllDay
}

public struct WeeklySchedule: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case rules
    }

    public private(set) var rules: [Weekday: DayRule]

    public init(rules: [Weekday: DayRule]) throws {
        guard Set(rules.keys) == Set(Weekday.allCases) else {
            throw ValidationError.incompleteWeek
        }
        self.rules = rules
        try validate()
    }

    public static func defaultWorkWeek() throws -> WeeklySchedule {
        let defaultRule = try defaultWorkdayRule()
        var rules = Dictionary(
            uniqueKeysWithValues: Weekday.allCases.map { ($0, DayRule.blockedAllDay) }
        )
        for weekday in [Weekday.monday, .tuesday, .wednesday, .thursday, .friday] {
            rules[weekday] = defaultRule
        }
        return try WeeklySchedule(rules: rules)
    }

    public static func defaultWorkdayRule() throws -> DayRule {
        .scheduled(
            start: try LocalTime(hour: 9, minute: 0),
            end: try LocalTime(hour: 17, minute: 0),
            endsNextDay: false
        )
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
            try start.validate()
            try end.validate()
            if start == end {
                throw ValidationError.equalScheduleBoundaries(weekday)
            }
            if endsNextDay {
                guard end < start else {
                    throw ValidationError.invalidOvernightWindow(weekday)
                }
                guard let nextWeekday = Weekday(
                    rawValue: weekday.rawValue % 7 + 1
                ) else {
                    throw ValidationError.incompleteWeek
                }
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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            rules: container.decode([Weekday: DayRule].self, forKey: .rules)
        )
    }
}

public enum CloseMode: String, Codable, Equatable, Sendable {
    case gentle
    case firm
}

public enum WarningLeadTime: Int, CaseIterable, Sendable {
    case fifteenMinute = 15
    case fiveMinute = 5

    public var offset: TimeInterval {
        TimeInterval(rawValue * 60)
    }
}

public struct WarningPreferences: Codable, Equatable, Sendable {
    public var fifteenMinuteWarningEnabled: Bool
    public var fiveMinuteWarningEnabled: Bool

    public init(
        fifteenMinuteWarningEnabled: Bool = true,
        fiveMinuteWarningEnabled: Bool = true
    ) {
        self.fifteenMinuteWarningEnabled = fifteenMinuteWarningEnabled
        self.fiveMinuteWarningEnabled = fiveMinuteWarningEnabled
    }

    public var enabledLeadTimes: [WarningLeadTime] {
        var leadTimes: [WarningLeadTime] = []
        if fifteenMinuteWarningEnabled {
            leadTimes.append(.fifteenMinute)
        }
        if fiveMinuteWarningEnabled {
            leadTimes.append(.fiveMinute)
        }
        return leadTimes
    }

    public var enabledOffsets: [TimeInterval] {
        enabledLeadTimes.map(\.offset)
    }
}

public struct WarningActionContext: Equatable, Sendable {
    public let cutoff: Date

    public init(cutoff: Date) {
        self.cutoff = cutoff
    }

    public func isCurrent(
        for schedule: ResolvedSchedule,
        at date: Date
    ) -> Bool {
        cutoff.timeIntervalSinceReferenceDate.isFinite
            && date.timeIntervalSinceReferenceDate.isFinite
            && date < cutoff
            && schedule.isAvailable
            && schedule.nextTransition
                == ScheduleTransition(date: cutoff, cause: .workWindowEnds)
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
    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case effect
        case effectiveAt
        case expiresAt
        case relatedIntervalID
    }

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
        self.id = id
        self.kind = kind
        self.effect = effect
        self.effectiveAt = effectiveAt
        self.expiresAt = expiresAt
        self.relatedIntervalID = relatedIntervalID?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        try validate()
    }

    static func precedenceOrder(
        _ lhs: ScheduleOverride,
        _ rhs: ScheduleOverride
    ) -> Bool {
        if lhs.effectiveAt == rhs.effectiveAt {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhs.effectiveAt < rhs.effectiveAt
    }

    public func isActive(at date: Date) -> Bool {
        effectiveAt <= date && date < expiresAt
    }

    public func validate() throws {
        guard expiresAt > effectiveAt else {
            throw ValidationError.invalidOverrideRange
        }
        let validEffect: Bool
        switch kind {
        case .endWorkNow, .takeDayOff:
            validEffect = effect == .block
        case .fixedExtension, .makeAvailable:
            validEffect = effect == .allow
        case .customCutoff:
            validEffect = effect == .allow || effect == .block
        case .forceEscalationPaused:
            validEffect = effect == .unchanged
        }
        guard validEffect else {
            throw ValidationError.invalidOverrideEffect(kind: kind, effect: effect)
        }
        if kind == .forceEscalationPaused {
            guard relatedIntervalID?.isEmpty == false else {
                throw ValidationError.invalidOverrideInterval(kind)
            }
        } else if kind == .fixedExtension {
            guard relatedIntervalID == nil
                    || relatedIntervalID?.isEmpty == false else {
                throw ValidationError.invalidOverrideInterval(kind)
            }
        } else if relatedIntervalID != nil {
            throw ValidationError.invalidOverrideInterval(kind)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            kind: container.decode(OverrideKind.self, forKey: .kind),
            effect: container.decode(AvailabilityEffect.self, forKey: .effect),
            effectiveAt: container.decode(Date.self, forKey: .effectiveAt),
            expiresAt: container.decode(Date.self, forKey: .expiresAt),
            relatedIntervalID: container.decodeIfPresent(
                String.self,
                forKey: .relatedIntervalID
            )
        )
    }
}

public struct SelectedApplication: Codable, Equatable, Identifiable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case id
        case bundleIdentifier
        case bundlePath
        case displayName
        case developerName
        case isResolvable
        case isAvailable
    }

    public static let protectedBundleIdentifiers: Set<String> = [
        "com.apple.finder",
        "com.apple.systempreferences",
        "com.apple.SystemSettings",
        "com.apple.loginwindow",
        "com.apple.dock",
        "com.firaskafri.homeward",
    ]

    public let id: UUID
    public var bundleIdentifier: String?
    public var bundlePath: String
    public var displayName: String
    public var developerName: String?
    public var isResolvable: Bool

    public init(
        id: UUID = UUID(),
        bundleIdentifier: String?,
        bundlePath: String,
        displayName: String,
        developerName: String? = nil,
        isResolvable: Bool = true
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.bundlePath = bundlePath
        self.displayName = displayName
        self.developerName = developerName
        self.isResolvable = isResolvable
    }

    public var stableSelectionKey: String {
        bundleIdentifier ?? URL(fileURLWithPath: bundlePath).standardizedFileURL.path
    }

    public var isProtected: Bool {
        bundleIdentifier.map(Self.protectedBundleIdentifiers.contains) ?? false
    }

    public func validate() throws {
        let identifier = bundleIdentifier?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard identifier == nil || identifier?.isEmpty == false,
              !bundlePath.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ).isEmpty,
              !displayName.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ).isEmpty else {
            throw ValidationError.invalidApplicationSelection(id)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let isResolvable: Bool
        if let value = try container.decodeIfPresent(
            Bool.self,
            forKey: .isResolvable
        ) {
            isResolvable = value
        } else if let legacyValue = try container.decodeIfPresent(
            Bool.self,
            forKey: .isAvailable
        ) {
            isResolvable = legacyValue
        } else {
            isResolvable = true
        }
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            bundleIdentifier: try container.decodeIfPresent(
                String.self,
                forKey: .bundleIdentifier
            ),
            bundlePath: try container.decode(String.self, forKey: .bundlePath),
            displayName: try container.decode(String.self, forKey: .displayName),
            developerName: try container.decodeIfPresent(
                String.self,
                forKey: .developerName
            ),
            isResolvable: isResolvable
        )
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(bundleIdentifier, forKey: .bundleIdentifier)
        try container.encode(bundlePath, forKey: .bundlePath)
        try container.encode(displayName, forKey: .displayName)
        try container.encodeIfPresent(developerName, forKey: .developerName)
        try container.encode(isResolvable, forKey: .isResolvable)
    }
}

public struct TomorrowNote: Codable, Equatable, Identifiable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case id
        case text
        case createdAt
        case lastPresentedIntervalID
    }

    public static let maximumCharacterCount = 500

    public let id: UUID
    public private(set) var text: String
    public let createdAt: Date
    public private(set) var lastPresentedIntervalID: String?

    public init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = Date(),
        lastPresentedIntervalID: String? = nil
    ) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = id
        self.text = trimmed
        self.createdAt = createdAt
        self.lastPresentedIntervalID = lastPresentedIntervalID
        try validate()
    }

    public func validate() throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ValidationError.emptyNote
        }
        guard trimmed == text else {
            throw ValidationError.noteRequiresTrimming
        }
        guard text.count <= Self.maximumCharacterCount else {
            throw ValidationError.noteTooLong(maximum: Self.maximumCharacterCount)
        }
        if let lastPresentedIntervalID,
           lastPresentedIntervalID.trimmingCharacters(
               in: .whitespacesAndNewlines
           ).isEmpty {
            throw ValidationError.invalidIntervalIdentifier
        }
    }

    public mutating func markPresented(in intervalID: String) throws {
        guard !intervalID.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw ValidationError.invalidIntervalIdentifier
        }
        lastPresentedIntervalID = intervalID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            text: container.decode(String.self, forKey: .text),
            createdAt: container.decode(Date.self, forKey: .createdAt),
            lastPresentedIntervalID: container.decodeIfPresent(
                String.self,
                forKey: .lastPresentedIntervalID
            )
        )
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
    case invalidOverrideEffect(kind: OverrideKind, effect: AvailabilityEffect)
    case invalidOverrideInterval(OverrideKind)
    case invalidApplicationSelection(UUID)
    case invalidIntervalIdentifier
    case emptyNote
    case noteRequiresTrimming
    case noteTooLong(maximum: Int)
}
