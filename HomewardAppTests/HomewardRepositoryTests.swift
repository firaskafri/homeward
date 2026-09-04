import Foundation
import Testing
@testable import Homeward
import HomewardCore

// 1 - Name: Homeward repository test file.
// 2 - Description: Verifies launch visibility, decoded policy validation, and notes backup restoration.
// 3 - Assumptions: Each test uses a unique temporary storage directory and no production data.
// 4 - Expectations: Repository reads validate domain invariants and explicit recovery restores the prior document.

/// 1 - Name: Homeward repository suite.
/// 2 - Description: Covers synchronous launch policy and validated configuration and notes persistence boundaries.
/// 3 - Assumptions: Atomic storage behavior is exercised through isolated repository instances.
/// 4 - Expectations: Corrupt or invalid state fails open and valid recovery candidates restore deterministically.
@Suite("Homeward repository")
@MainActor
struct HomewardRepositoryTests {
    /// 1 - Name: Initial window launch policy.
    /// 2 - Description: Chooses visible startup for new or corrupt state and quiet startup after completed setup.
    /// 3 - Assumptions: The synchronous launch decision reads the same validated configuration format as the repository.
    /// 4 - Expectations: Missing and corrupt files present a window; a completed configuration suppresses it.
    @Test
    func initialWindowLaunchPolicy() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        #expect(HomewardRepository.shouldPresentMainWindow(
            directoryURL: fixture.directoryURL
        ))

        var configuration = try HomewardConfiguration.initial()
        configuration.onboardingScheduleConfirmed = true
        configuration.completedOnboarding = true
        _ = try await HomewardRepository(
            directoryURL: fixture.directoryURL
        ).saveConfiguration(configuration)
        #expect(!HomewardRepository.shouldPresentMainWindow(
            directoryURL: fixture.directoryURL
        ))

        try Data("corrupt".utf8).write(
            to: fixture.directoryURL.appendingPathComponent(
                "configuration.json"
            )
        )
        #expect(HomewardRepository.shouldPresentMainWindow(
            directoryURL: fixture.directoryURL
        ))
    }

    /// 1 - Name: Repository validates decoded configuration.
    /// 2 - Description: Writes a syntactically valid but protected selection directly to storage.
    /// 3 - Assumptions: Persisted configuration is untrusted and decoding enforces domain invariants.
    /// 4 - Expectations: Repository load rejects the protected persisted policy.
    @Test
    func repositoryValidatesDecodedConfiguration() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(
            at: fixture.directoryURL,
            withIntermediateDirectories: true
        )
        var configuration = try HomewardConfiguration.initial()
        configuration.selectedApplications = [
            SelectedApplication(
                bundleIdentifier: "com.apple.finder",
                bundlePath: "/System/Library/CoreServices/Finder.app",
                displayName: "Finder"
            ),
        ]
        let data = try JSONEncoder().encode(configuration)
        try data.write(
            to: fixture.directoryURL.appendingPathComponent("configuration.json")
        )
        let repository = HomewardRepository(directoryURL: fixture.directoryURL)

        await #expect(throws: ConfigurationError.protectedApplicationSelection(
            "com.apple.finder"
        )) {
            _ = try await repository.loadConfiguration()
        }
    }

    /// 1 - Name: Notes backup restoration.
    /// 2 - Description: Restores the last validated notes document through repository recovery APIs.
    /// 3 - Assumptions: A second successful save creates an explicit previous-document candidate.
    /// 4 - Expectations: Recovery replaces active notes without changing configuration storage.
    @Test
    func repositoryRestoresPreviousNotes() async throws {
        let fixture = AppModelFixture()
        defer { fixture.remove() }
        let repository = HomewardRepository(directoryURL: fixture.directoryURL)
        let first = try NotesDocument(
            notes: [TomorrowNote(text: "First")]
        )
        let second = try NotesDocument(
            notes: [TomorrowNote(text: "Second")]
        )
        _ = try await repository.saveNotes(first)
        _ = try await repository.saveNotes(second)
        let candidate = try #require(
            try await repository.notesRecoveryCandidate()
        )

        _ = try await repository.replaceNotesDuringRecovery(candidate)

        #expect(try await repository.loadNotes() == first)
    }
}
