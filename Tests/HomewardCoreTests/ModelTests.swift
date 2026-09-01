import Foundation
import Testing
@testable import HomewardCore

// 1 - Name: Domain model test file.
// 2 - Description: Verifies model validation, defaults, identity keys, and tomorrow-note lifecycle rules.
// 3 - Assumptions: Domain values reject invalid input before platform or persistence layers receive it.
// 4 - Expectations: Invalid states are unrepresentable and defaults match the approved product contract.

/// 1 - Name: Domain model suite.
/// 2 - Description: Covers value validation and configuration-level invariants.
/// 3 - Assumptions: UUID and Date values are supplied explicitly when deterministic comparison matters.
/// 4 - Expectations: Every model either initializes validly or returns the documented validation error.
@Suite("Domain models")
struct ModelTests {
    /// 1 - Name: Invalid local time.
    /// 2 - Description: Rejects hours and minutes outside civil-time bounds.
    /// 3 - Assumptions: Homeward supports minute precision.
    /// 4 - Expectations: Invalid components report their original values.
    @Test
    func invalidLocalTime() {
        #expect(throws: ValidationError.invalidLocalTime(hour: 24, minute: 0)) {
            _ = try LocalTime(hour: 24, minute: 0)
        }
        #expect(throws: ValidationError.invalidLocalTime(hour: 12, minute: 60)) {
            _ = try LocalTime(hour: 12, minute: 60)
        }
    }

    /// 1 - Name: Default preferences.
    /// 2 - Description: Verifies warning and Gentle-extension defaults.
    /// 3 - Assumptions: Fifteen- and five-minute warnings begin enabled.
    /// 4 - Expectations: The Gentle shortcut is disabled until explicitly enabled.
    @Test
    func defaultPreferences() {
        let preferences = WarningPreferences()

        #expect(preferences.fifteenMinuteWarningEnabled)
        #expect(preferences.fiveMinuteWarningEnabled)
        #expect(!preferences.gentleExtensionEnabled)
    }

    /// 1 - Name: Stable application selection key.
    /// 2 - Description: Uses bundle identity when present and a standardized path otherwise.
    /// 3 - Assumptions: A bundle identifier intentionally manages all matching installed copies.
    /// 4 - Expectations: Bundle and path selections generate deterministic distinct keys.
    @Test
    func stableApplicationSelectionKey() {
        let bundled = SelectedApplication(
            bundleIdentifier: "com.example.editor",
            bundlePath: "/Applications/Editor.app",
            displayName: "Editor"
        )
        let pathOnly = SelectedApplication(
            bundleIdentifier: nil,
            bundlePath: "/Applications/../Applications/Tool.app",
            displayName: "Tool"
        )

        #expect(bundled.stableSelectionKey == "com.example.editor")
        #expect(pathOnly.stableSelectionKey == "/Applications/Tool.app")
    }

    /// 1 - Name: Duplicate application selection.
    /// 2 - Description: Rejects duplicate bundle-identifier selections in one configuration.
    /// 3 - Assumptions: Duplicate paths or identifiers do not represent separate policy entries.
    /// 4 - Expectations: Configuration initialization fails before duplicate policy can persist.
    @Test
    func duplicateApplicationSelection() throws {
        let first = SelectedApplication(
            bundleIdentifier: "com.example.editor",
            bundlePath: "/Applications/Editor.app",
            displayName: "Editor"
        )
        let second = SelectedApplication(
            bundleIdentifier: "com.example.editor",
            bundlePath: "/Users/example/Editor.app",
            displayName: "Editor Copy"
        )

        #expect(throws: ConfigurationError.duplicateApplicationSelection) {
            _ = try HomewardConfiguration(
                schedule: .defaultWorkWeek(),
                selectedApplications: [first, second]
            )
        }
    }

    /// 1 - Name: Tomorrow-note validation.
    /// 2 - Description: Rejects empty notes and content longer than the approved 500-character bound.
    /// 3 - Assumptions: Swift String count represents user-perceived extended grapheme clusters.
    /// 4 - Expectations: Valid content is trimmed and invalid content receives a specific error.
    @Test
    func tomorrowNoteValidation() throws {
        #expect(throws: ValidationError.emptyNote) {
            _ = try TomorrowNote(text: "  \n ")
        }
        #expect(throws: ValidationError.noteTooLong(maximum: 500)) {
            _ = try TomorrowNote(text: String(repeating: "a", count: 501))
        }

        let note = try TomorrowNote(text: "  Review the build  ")
        #expect(note.text == "Review the build")
    }

    /// 1 - Name: Tomorrow-note ordering and removal.
    /// 2 - Description: Appends notes deterministically and removes completed content without an archive.
    /// 3 - Assumptions: Creation time is the primary order and UUID is the stable tie-breaker.
    /// 4 - Expectations: Notes remain oldest-first and removed notes leave the document.
    @Test
    func tomorrowNoteOrderingAndRemoval() throws {
        let earlier = try TomorrowNote(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            text: "Earlier",
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let later = try TomorrowNote(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            text: "Later",
            createdAt: Date(timeIntervalSince1970: 2)
        )
        var document = try NotesDocument(notes: [later])
        document.append(earlier)

        #expect(document.notes.map(\.text) == ["Earlier", "Later"])
        #expect(document.remove(id: earlier.id) == earlier)
        #expect(document.notes == [later])
    }

    /// 1 - Name: Gentle-extension consumption persistence.
    /// 2 - Description: Round-trips the blocked-interval identifier used to enforce one shortcut extension.
    /// 3 - Assumptions: Deliberate menu extensions remain separate from the one-time Gentle shortcut.
    /// 4 - Expectations: Codable configuration preserves the consumed interval exactly.
    @Test
    func gentleExtensionConsumptionPersistence() throws {
        var configuration = try HomewardConfiguration.initial()
        configuration.consumedGentleExtensionIntervalIDs.insert("blocked-interval-1")

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(HomewardConfiguration.self, from: data)

        #expect(decoded.consumedGentleExtensionIntervalIDs == ["blocked-interval-1"])
    }
}
