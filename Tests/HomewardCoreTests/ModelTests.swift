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
    func defaultPreferences() throws {
        let preferences = WarningPreferences()
        let configuration = try HomewardConfiguration.initial()

        #expect(preferences.fifteenMinuteWarningEnabled)
        #expect(preferences.fiveMinuteWarningEnabled)
        #expect(!configuration.gentleShortcutExtensionEnabled)
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

    /// 1 - Name: Missing application identity.
    /// 2 - Description: Rejects a persisted selection without a bundle identifier or usable path.
    /// 3 - Assumptions: Enforcement cannot safely match an application without stable identity.
    /// 4 - Expectations: Configuration validation reports the invalid selection identifier.
    @Test
    func missingApplicationIdentityIsRejected() throws {
        let id = UUID()
        let selection = SelectedApplication(
            id: id,
            bundleIdentifier: nil,
            bundlePath: " ",
            displayName: "Unknown"
        )

        #expect(throws: ValidationError.invalidApplicationSelection(id)) {
            _ = try HomewardConfiguration(
                schedule: .defaultWorkWeek(),
                selectedApplications: [selection]
            )
        }
    }

    /// 1 - Name: Force-pause interval identity.
    /// 2 - Description: Rejects a force-escalation pause that is not tied to one blocked interval.
    /// 3 - Assumptions: Safety pauses must expire with the interval in which the user requested them.
    /// 4 - Expectations: A missing interval identifier fails override construction.
    @Test
    func forcePauseRequiresIntervalIdentity() {
        #expect(throws: ValidationError.invalidOverrideInterval(
            .forceEscalationPaused
        )) {
            _ = try ScheduleOverride(
                kind: .forceEscalationPaused,
                effect: .unchanged,
                effectiveAt: Date(timeIntervalSince1970: 1),
                expiresAt: Date(timeIntervalSince1970: 2)
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
        #expect(throws: ValidationError.noteTooLong(
            maximum: TomorrowNote.maximumCharacterCount
        )) {
            _ = try TomorrowNote(
                text: String(
                    repeating: "a",
                    count: TomorrowNote.maximumCharacterCount + 1
                )
            )
        }

        let note = try TomorrowNote(text: "  Review the build  ")
        #expect(note.text == "Review the build")
    }

    /// 1 - Name: Tomorrow-note ordering and removal.
    /// 2 - Description: Appends notes deterministically and removes completed content without an archive.
    /// 3 - Assumptions: Creation time is the primary order and UUID is the stable tie-breaker.
    /// 4 - Expectations: Notes remain oldest-first, remove cleanly, and reject duplicate identifiers.
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
        try document.append(earlier)

        #expect(document.notes.map(\.text) == ["Earlier", "Later"])
        #expect(document.remove(id: earlier.id) == earlier)
        #expect(document.notes == [later])
        #expect(throws: ConfigurationError.duplicateNote) {
            _ = try NotesDocument(notes: [later, later])
        }
    }

    /// 1 - Name: Gentle-extension consumption persistence.
    /// 2 - Description: Round-trips the blocked-interval identifier used to enforce one shortcut extension.
    /// 3 - Assumptions: Deliberate menu extensions remain separate from the one-time Gentle shortcut.
    /// 4 - Expectations: Codable configuration preserves the consumed interval exactly.
    @Test
    func gentleExtensionConsumptionPersistence() throws {
        var configuration = try HomewardConfiguration.initial()
        try configuration.markGentleExtensionConsumed(
            in: "blocked-interval-1"
        )

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(HomewardConfiguration.self, from: data)

        #expect(decoded.consumedGentleExtensionIntervalIDs == ["blocked-interval-1"])
    }

    /// 1 - Name: Expired override pruning.
    /// 2 - Description: Removes completed temporary policy while preserving current policy.
    /// 3 - Assumptions: Override expiry is half-open and an override ending now is expired.
    /// 4 - Expectations: Pruning reports a change and retains only the active override.
    @Test
    func expiredOverridePruning() throws {
        let now = Date(timeIntervalSince1970: 100)
        let expired = try ScheduleOverride(
            kind: .fixedExtension,
            effect: .allow,
            effectiveAt: Date(timeIntervalSince1970: 50),
            expiresAt: now
        )
        let active = try ScheduleOverride(
            kind: .takeDayOff,
            effect: .block,
            effectiveAt: Date(timeIntervalSince1970: 75),
            expiresAt: Date(timeIntervalSince1970: 125)
        )
        var configuration = try HomewardConfiguration(
            schedule: .defaultWorkWeek(),
            overrides: [expired, active]
        )

        let didRemoveExpiredOverride = configuration.removeExpiredOverrides(
            at: now
        )
        #expect(didRemoveExpiredOverride)
        #expect(configuration.overrides == [active])
        let didRemoveAnotherOverride = configuration.removeExpiredOverrides(
            at: now
        )
        #expect(!didRemoveAnotherOverride)
    }

    /// 1 - Name: Protected persisted application.
    /// 2 - Description: Rejects a protected bundle identifier even when it enters configuration outside the picker.
    /// 3 - Assumptions: Persisted files are untrusted input and must repeat safety validation.
    /// 4 - Expectations: Finder cannot become an enforcement selection.
    @Test
    func protectedPersistedApplicationIsRejected() throws {
        var configuration = try HomewardConfiguration.initial()
        configuration.selectedApplications = [
            SelectedApplication(
                bundleIdentifier: "com.apple.finder",
                bundlePath: "/System/Library/CoreServices/Finder.app",
                displayName: "Finder"
            ),
        ]

        #expect(throws: ConfigurationError.protectedApplicationSelection(
            "com.apple.finder"
        )) {
            try configuration.validate()
        }
    }

    /// 1 - Name: Decoded local-time validation.
    /// 2 - Description: Verifies Codable applies the same validation as the public initializer.
    /// 3 - Assumptions: Persisted JSON is untrusted and must not create an invalid model.
    /// 4 - Expectations: Decoding an out-of-range hour throws the domain validation error.
    @Test
    func decodedLocalTimeValidation() {
        #expect(throws: ValidationError.invalidLocalTime(hour: 99, minute: 0)) {
            _ = try JSONDecoder().decode(
                LocalTime.self,
                from: Data(#"{"hour":99,"minute":0}"#.utf8)
            )
        }
    }
}
