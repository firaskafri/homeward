import Foundation

public struct HomewardConfiguration: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var schedule: WeeklySchedule
    public var selectedApplications: [SelectedApplication]
    public var closeMode: CloseMode
    public var warningPreferences: WarningPreferences
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
        self.overrides = overrides
        self.consumedGentleExtensionIntervalIDs = consumedGentleExtensionIntervalIDs
        self.onboardingScheduleConfirmed = onboardingScheduleConfirmed
        self.completedOnboarding = completedOnboarding
        try validate()
    }

    public static func initial() throws -> HomewardConfiguration {
        try HomewardConfiguration(schedule: .defaultWorkWeek())
    }

    public mutating func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ConfigurationError.unsupportedSchemaVersion(schemaVersion)
        }
        try schedule.validate()

        let keys = selectedApplications.map(\.stableSelectionKey)
        guard Set(keys).count == keys.count else {
            throw ConfigurationError.duplicateApplicationSelection
        }
        if let protectedIdentifier = selectedApplications.first(
            where: \.isProtected
        )?.bundleIdentifier {
            throw ConfigurationError.protectedApplicationSelection(
                protectedIdentifier
            )
        }

        try overrides.forEach { try $0.validate() }
        overrides = overrides.sorted(by: { $0.effectiveAt < $1.effectiveAt })
    }
}

public struct NotesDocument: Codable, Equatable, Sendable {
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

    public mutating func keep(id: UUID, presentedIn intervalID: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else {
            return
        }
        notes[index].lastPresentedIntervalID = intervalID
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

    public mutating func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ConfigurationError.unsupportedSchemaVersion(schemaVersion)
        }
        try notes.forEach { try $0.validate() }
        let noteIDs = notes.map(\.id)
        guard Set(noteIDs).count == noteIDs.count else {
            throw ConfigurationError.duplicateNote
        }
        notes.sort(by: Self.noteOrder)
    }
}

public enum ConfigurationError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case duplicateApplicationSelection
    case protectedApplicationSelection(String)
    case duplicateNote
}
