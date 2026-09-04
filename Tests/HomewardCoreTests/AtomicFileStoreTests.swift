import Foundation
import Testing
@testable import HomewardCore

// 1 - Name: Atomic file-store test file.
// 2 - Description: Verifies local Codable persistence, recovery candidates, permissions, and deletion.
// 3 - Assumptions: Tests operate in unique temporary directories on a POSIX macOS filesystem.
// 4 - Expectations: Writes are readable, owner-only, and never silently replace corrupt active data with backup data.

/// 1 - Name: Atomic file-store suite.
/// 2 - Description: Exercises the generic local persistence primitive independently from app lifecycle code.
/// 3 - Assumptions: FileManager reports POSIX permissions for temporary files.
/// 4 - Expectations: Primary and recovery data remain explicit and independently verifiable.
@Suite("Atomic file store")
struct AtomicFileStoreTests {
    /// 1 - Name: Round-trip and permissions.
    /// 2 - Description: Saves and loads a notes document while checking directory and file permissions.
    /// 3 - Assumptions: Atomic replacement preserves the permissions applied after the write.
    /// 4 - Expectations: Loaded content matches and storage is owner-only.
    @Test
    func roundTripAndPermissions() async throws {
        let fixture = TemporaryStoreFixture()
        defer { fixture.remove() }
        let store = AtomicFileStore<NotesDocument>(fileURL: fixture.fileURL)
        let note = try TomorrowNote(text: "Remember this")
        let document = try NotesDocument(notes: [note])

        try await store.save(document)
        let loaded = try await store.load()

        #expect(loaded == document)
        #expect(try permissions(at: fixture.directoryURL) == 0o700)
        #expect(try permissions(at: fixture.fileURL) == 0o600)
    }

    /// 1 - Name: Explicit recovery candidate.
    /// 2 - Description: Keeps the last validated primary as a separate recovery candidate.
    /// 3 - Assumptions: A second successful save rotates the first document to the backup URL.
    /// 4 - Expectations: Recovery is available only through the explicit recovery API.
    @Test
    func explicitRecoveryCandidate() async throws {
        let fixture = TemporaryStoreFixture()
        defer { fixture.remove() }
        let store = AtomicFileStore<NotesDocument>(fileURL: fixture.fileURL)
        let first = try NotesDocument(notes: [TomorrowNote(text: "First")])
        let second = try NotesDocument(notes: [TomorrowNote(text: "Second")])

        try await store.save(first)
        try await store.save(second)

        #expect(try await store.load() == second)
        #expect(try await store.loadRecoveryCandidate() == first)
    }

    /// 1 - Name: Corrupt active data fails open.
    /// 2 - Description: Corrupts the active file after a valid backup exists.
    /// 3 - Assumptions: The store must not silently enforce older data when active data cannot be decoded.
    /// 4 - Expectations: Active load throws while the recovery candidate remains separately readable.
    @Test
    func corruptActiveDataFailsOpen() async throws {
        let fixture = TemporaryStoreFixture()
        defer { fixture.remove() }
        let store = AtomicFileStore<NotesDocument>(fileURL: fixture.fileURL)
        let first = try NotesDocument(notes: [TomorrowNote(text: "First")])
        let second = try NotesDocument(notes: [TomorrowNote(text: "Second")])
        try await store.save(first)
        try await store.save(second)
        try Data("not json".utf8).write(to: fixture.fileURL, options: .atomic)

        await #expect(throws: DecodingError.self) {
            _ = try await store.load()
        }
        #expect(try await store.loadRecoveryCandidate() == first)
    }

    /// 1 - Name: Store deletion.
    /// 2 - Description: Removes active and recovery files without affecting the containing temporary directory.
    /// 3 - Assumptions: Both files may exist after two successful writes.
    /// 4 - Expectations: Neither file remains after deletion.
    @Test
    func deletionRemovesPrimaryAndRecovery() async throws {
        let fixture = TemporaryStoreFixture()
        defer { fixture.remove() }
        let store = AtomicFileStore<NotesDocument>(fileURL: fixture.fileURL)
        try await store.save(NotesDocument())
        try await store.save(NotesDocument())

        try await store.delete()

        #expect(!FileManager.default.fileExists(atPath: fixture.fileURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.fileURL.appendingPathExtension("previous").path))
    }

    /// 1 - Name: Recovery replacement over corrupt primary.
    /// 2 - Description: Replaces undecodable active data without promoting it to the validated backup.
    /// 3 - Assumptions: Recovery is an explicit user action after normal load has failed open.
    /// 4 - Expectations: The replacement becomes active and the earlier validated recovery candidate remains intact.
    @Test
    func recoveryReplacementOverCorruptPrimary() async throws {
        let fixture = TemporaryStoreFixture()
        defer { fixture.remove() }
        let store = AtomicFileStore<NotesDocument>(fileURL: fixture.fileURL)
        let first = try NotesDocument(notes: [TomorrowNote(text: "First")])
        let second = try NotesDocument(notes: [TomorrowNote(text: "Second")])
        let replacement = try NotesDocument(notes: [TomorrowNote(text: "Replacement")])
        try await store.save(first)
        try await store.save(second)
        try Data("corrupt".utf8).write(to: fixture.fileURL, options: .atomic)

        try await store.replaceDuringRecovery(replacement)

        #expect(try await store.load() == replacement)
        #expect(try await store.loadRecoveryCandidate() == first)
    }

    /// 1 - Name: Failed recovery replacement preserves readable state.
    /// 2 - Description: Injects a failure after replacement data is staged but before the active file is exchanged.
    /// 3 - Assumptions: Recovery staging occurs beside the active file and cleanup runs on every exit.
    /// 4 - Expectations: The readable primary and backup remain unchanged and no staged artifact survives.
    @Test
    func failedRecoveryReplacementPreservesReadableState() async throws {
        let fixture = TemporaryStoreFixture()
        defer { fixture.remove() }
        let initialStore = AtomicFileStore<NotesDocument>(
            fileURL: fixture.fileURL
        )
        let first = try NotesDocument(notes: [TomorrowNote(text: "First")])
        let second = try NotesDocument(notes: [TomorrowNote(text: "Second")])
        let replacement = try NotesDocument(
            notes: [TomorrowNote(text: "Replacement")]
        )
        try await initialStore.save(first)
        try await initialStore.save(second)
        let failingStore = AtomicFileStore<NotesDocument>(
            fileURL: fixture.fileURL,
            beforeRecoveryReplacement: {
                throw StoreFixtureError.replacementInterrupted
            }
        )

        await #expect(throws: StoreFixtureError.replacementInterrupted) {
            try await failingStore.replaceDuringRecovery(replacement)
        }

        #expect(try await initialStore.load() == second)
        #expect(try await initialStore.loadRecoveryCandidate() == first)
        let files = try FileManager.default.contentsOfDirectory(
            at: fixture.directoryURL,
            includingPropertiesForKeys: nil
        )
        #expect(!files.contains {
            $0.lastPathComponent.contains(".staged-")
        })
    }
}

/// 1 - Name: Atomic-store fixture error.
/// 2 - Description: Models interruption immediately before a recovery file exchange.
/// 3 - Assumptions: The injected hook runs only after staged data is durable.
/// 4 - Expectations: Tests can assert transactional rollback without filesystem races.
private enum StoreFixtureError: Error {
    case replacementInterrupted
}

private struct TemporaryStoreFixture {
    let directoryURL: URL
    let fileURL: URL

    init() {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("HomewardTests-\(UUID().uuidString)", isDirectory: true)
        fileURL = directoryURL.appendingPathComponent("notes.json")
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}

private func permissions(at url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
}
