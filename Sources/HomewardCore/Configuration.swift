import Foundation

public struct HomewardConfiguration: Codable, Equatable, Sendable {
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

    public var schemaVersion: Int
    public var schedule: WeeklySchedule
    public var selectedApplications: [SelectedApplication]
    public var closeMode: CloseMode
    public var warningPreferences: WarningPreferences
    public var gentleShortcutExtensionEnabled: Bool
    public var overrides: [ScheduleOverride]
    public var consumedGentleExtensionIntervalIDs: Set<String>
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
        self.overrides = overrides.sorted(by: { $0.effectiveAt < $1.effectiveAt })
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
    }

    public mutating func replaceActiveAvailabilityOverrides(
        with replacements: [ScheduleOverride],
        at date: Date
    ) {
        overrides.removeAll {
            $0.kind != .forceEscalationPaused && $0.isActive(at: date)
        }
        overrides.append(contentsOf: replacements)
        overrides.sort(by: { $0.effectiveAt < $1.effectiveAt })
    }

    public mutating func replaceUnexpiredAvailabilityOverrides(
        with replacements: [ScheduleOverride],
        at date: Date
    ) {
        overrides.removeAll {
            $0.kind != .forceEscalationPaused && $0.expiresAt > date
        }
        overrides.append(contentsOf: replacements)
        overrides.sort(by: { $0.effectiveAt < $1.effectiveAt })
    }

    public mutating func clearAvailabilityOverrides() {
        overrides.removeAll { $0.kind != .forceEscalationPaused }
    }

    public mutating func setForceEscalationPause(
        _ pause: ScheduleOverride
    ) {
        overrides.removeAll { $0.kind == .forceEscalationPaused }
        overrides.append(pause)
        overrides.sort(by: { $0.effectiveAt < $1.effectiveAt })
    }

    public mutating func clearForceEscalationPause() {
        overrides.removeAll { $0.kind == .forceEscalationPaused }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: container.decode(Int.self, forKey: .schemaVersion),
            schedule: container.decode(WeeklySchedule.self, forKey: .schedule),
            selectedApplications: container.decode(
                [SelectedApplication].self,
                forKey: .selectedApplications
            ),
            closeMode: container.decode(CloseMode.self, forKey: .closeMode),
            warningPreferences: container.decode(
                WarningPreferences.self,
                forKey: .warningPreferences
            ),
            gentleShortcutExtensionEnabled: container.decodeIfPresent(
                Bool.self,
                forKey: .gentleShortcutExtensionEnabled
            ) ?? false,
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

    public var schemaVersion: Int
    public var notes: [TomorrowNote]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        notes: [TomorrowNote] = []
    ) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ConfigurationError.unsupportedSchemaVersion(schemaVersion)
        }
        self.schemaVersion = schemaVersion
        self.notes = notes.sorted(by: Self.noteOrder)
    }

    public mutating func append(_ note: TomorrowNote) {
        notes.append(note)
        notes.sort(by: Self.noteOrder)
    }

    public mutating func markPresented(id: UUID, in intervalID: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else {
            return
        }
        notes[index].markPresented(in: intervalID)
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
    case duplicateNote
}
