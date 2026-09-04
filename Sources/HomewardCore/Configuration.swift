import Foundation

public struct HomewardConfiguration: Codable, Equatable, Sendable {
    private struct LegacyWarningPreferences: Decodable {
        let gentleExtensionEnabled: Bool?
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case schedule
        case selectedApplications
        case closeMode
        case warningPreferences
        case gentleShortcutExtensionEnabled
        case overrides
        case consumedGentleExtensionIntervalIDs
        case onboardingScheduleConfirmed
        case completedOnboarding
    }

    public static let currentSchemaVersion = 1

    public private(set) var schemaVersion: Int
    public var schedule: WeeklySchedule
    public var selectedApplications: [SelectedApplication]
    public var closeMode: CloseMode
    public var warningPreferences: WarningPreferences
    public var gentleShortcutExtensionEnabled: Bool
    public private(set) var overrides: [ScheduleOverride]
    public private(set) var consumedGentleExtensionIntervalIDs: Set<String>
    public var onboardingScheduleConfirmed: Bool
    public var completedOnboarding: Bool

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        schedule: WeeklySchedule,
        selectedApplications: [SelectedApplication] = [],
        closeMode: CloseMode = .gentle,
        warningPreferences: WarningPreferences = WarningPreferences(),
        gentleShortcutExtensionEnabled: Bool = false,
        overrides: [ScheduleOverride] = [],
        consumedGentleExtensionIntervalIDs: Set<String> = [],
        onboardingScheduleConfirmed: Bool = false,
        completedOnboarding: Bool = false
    ) throws {
        self.schemaVersion = schemaVersion
        self.schedule = schedule
        self.selectedApplications = selectedApplications
        self.closeMode = closeMode
        self.warningPreferences = warningPreferences
        self.gentleShortcutExtensionEnabled = gentleShortcutExtensionEnabled
        self.overrides = overrides.sorted(by: ScheduleOverride.precedenceOrder)
        self.consumedGentleExtensionIntervalIDs = consumedGentleExtensionIntervalIDs
        self.onboardingScheduleConfirmed = onboardingScheduleConfirmed
        self.completedOnboarding = completedOnboarding
        try validate()
    }

    public static func initial() throws -> HomewardConfiguration {
        try HomewardConfiguration(schedule: .defaultWorkWeek())
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ConfigurationError.unsupportedSchemaVersion(schemaVersion)
        }
        try schedule.validate()
        try selectedApplications.forEach { try $0.validate() }

        let keys = selectedApplications.map(\.stableSelectionKey)
        guard Set(keys).count == keys.count else {
            throw ConfigurationError.duplicateApplicationSelection
        }
        let identifiers = selectedApplications.map(\.id)
        guard Set(identifiers).count == identifiers.count else {
            throw ConfigurationError.duplicateApplicationIdentifier
        }
        if let protectedIdentifier = selectedApplications.first(
            where: \.isProtected
        )?.bundleIdentifier {
            throw ConfigurationError.protectedApplicationSelection(
                protectedIdentifier
            )
        }

        try overrides.forEach { try $0.validate() }
        let overrideIDs = overrides.map(\.id)
        guard Set(overrideIDs).count == overrideIDs.count else {
            throw ConfigurationError.duplicateOverride
        }
        guard consumedGentleExtensionIntervalIDs.allSatisfy({
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            throw ValidationError.invalidIntervalIdentifier
        }
    }

    public mutating func replaceActiveAvailabilityOverrides(
        with replacements: [ScheduleOverride],
        at date: Date
    ) {
        overrides.removeAll {
            $0.kind != .forceEscalationPaused && $0.isActive(at: date)
        }
        overrides.append(contentsOf: replacements)
        overrides.sort(by: ScheduleOverride.precedenceOrder)
    }

    public mutating func replaceUnexpiredAvailabilityOverrides(
        with replacements: [ScheduleOverride],
        at date: Date
    ) {
        overrides.removeAll {
            $0.kind != .forceEscalationPaused && $0.expiresAt > date
        }
        overrides.append(contentsOf: replacements)
        overrides.sort(by: ScheduleOverride.precedenceOrder)
    }

    public mutating func clearAvailabilityOverrides() {
        overrides.removeAll { $0.kind != .forceEscalationPaused }
    }

    public mutating func setForceEscalationPause(
        _ pause: ScheduleOverride
    ) {
        overrides.removeAll { $0.kind == .forceEscalationPaused }
        overrides.append(pause)
        overrides.sort(by: ScheduleOverride.precedenceOrder)
    }

    public mutating func clearForceEscalationPause() {
        overrides.removeAll { $0.kind == .forceEscalationPaused }
    }

    public mutating func markGentleExtensionConsumed(
        in intervalID: String
    ) throws {
        guard !intervalID.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw ValidationError.invalidIntervalIdentifier
        }
        consumedGentleExtensionIntervalIDs.insert(intervalID)
    }

    public mutating func clearGentleExtensionConsumption() {
        consumedGentleExtensionIntervalIDs.removeAll()
    }

    @discardableResult
    public mutating func removeExpiredOverrides(at date: Date) -> Bool {
        let previousCount = overrides.count
        overrides.removeAll { $0.expiresAt <= date }
        return overrides.count != previousCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let warningPreferences = try container.decode(
            WarningPreferences.self,
            forKey: .warningPreferences
        )
        let gentleExtensionEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .gentleShortcutExtensionEnabled
        ) ?? container.decode(
            LegacyWarningPreferences.self,
            forKey: .warningPreferences
        ).gentleExtensionEnabled ?? false
        try self.init(
            schemaVersion: container.decode(Int.self, forKey: .schemaVersion),
            schedule: container.decode(WeeklySchedule.self, forKey: .schedule),
            selectedApplications: container.decode(
                [SelectedApplication].self,
                forKey: .selectedApplications
            ),
            closeMode: container.decode(CloseMode.self, forKey: .closeMode),
            warningPreferences: warningPreferences,
            gentleShortcutExtensionEnabled: gentleExtensionEnabled,
            overrides: container.decode(
                [ScheduleOverride].self,
                forKey: .overrides
            ),
            consumedGentleExtensionIntervalIDs: container.decodeIfPresent(
                Set<String>.self,
                forKey: .consumedGentleExtensionIntervalIDs
            ) ?? [],
            onboardingScheduleConfirmed: container.decodeIfPresent(
                Bool.self,
                forKey: .onboardingScheduleConfirmed
            ) ?? false,
            completedOnboarding: container.decode(
                Bool.self,
                forKey: .completedOnboarding
            )
        )
    }
}

public struct NotesDocument: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case notes
    }

    public static let currentSchemaVersion = 1

    public private(set) var schemaVersion: Int
    public private(set) var notes: [TomorrowNote]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        notes: [TomorrowNote] = []
    ) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ConfigurationError.unsupportedSchemaVersion(schemaVersion)
        }
        self.schemaVersion = schemaVersion
        self.notes = notes.sorted(by: Self.noteOrder)
        try validate()
    }

    public mutating func append(_ note: TomorrowNote) throws {
        try note.validate()
        guard !notes.contains(where: { $0.id == note.id }) else {
            throw ConfigurationError.duplicateNote
        }
        notes.append(note)
        notes.sort(by: Self.noteOrder)
    }

    public mutating func markPresented(
        id: UUID,
        in intervalID: String
    ) throws {
        guard let index = notes.firstIndex(where: { $0.id == id }) else {
            throw ConfigurationError.noteNotFound(id)
        }
        try notes[index].markPresented(in: intervalID)
    }

    @discardableResult
    public mutating func remove(id: UUID) -> TomorrowNote? {
        guard let index = notes.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        return notes.remove(at: index)
    }

    private static func noteOrder(lhs: TomorrowNote, rhs: TomorrowNote) -> Bool {
        if lhs.createdAt == rhs.createdAt {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhs.createdAt < rhs.createdAt
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ConfigurationError.unsupportedSchemaVersion(schemaVersion)
        }
        try notes.forEach { try $0.validate() }
        let noteIDs = notes.map(\.id)
        guard Set(noteIDs).count == noteIDs.count else {
            throw ConfigurationError.duplicateNote
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: container.decode(Int.self, forKey: .schemaVersion),
            notes: container.decode([TomorrowNote].self, forKey: .notes)
        )
    }
}

public enum ConfigurationError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case duplicateApplicationSelection
    case duplicateApplicationIdentifier
    case protectedApplicationSelection(String)
    case duplicateOverride
    case duplicateNote
    case noteNotFound(UUID)
}
