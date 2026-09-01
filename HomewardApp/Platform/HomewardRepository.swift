import Foundation
import HomewardCore

actor HomewardRepository {
    private let configurationStore: AtomicFileStore<HomewardConfiguration>
    private let notesStore: AtomicFileStore<NotesDocument>

    init(fileManager: FileManager = .default) throws {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport
            .appendingPathComponent("Homeward", isDirectory: true)
        configurationStore = AtomicFileStore(
            fileURL: directory.appendingPathComponent("configuration.json")
        )
        notesStore = AtomicFileStore(
            fileURL: directory.appendingPathComponent("notes.json")
        )
    }

    init(directoryURL: URL) {
        configurationStore = AtomicFileStore(
            fileURL: directoryURL.appendingPathComponent("configuration.json")
        )
        notesStore = AtomicFileStore(
            fileURL: directoryURL.appendingPathComponent("notes.json")
        )
    }

    func loadConfiguration() async throws -> HomewardConfiguration? {
        try await configurationStore.load()
    }

    func saveConfiguration(_ configuration: HomewardConfiguration) async throws {
        var validated = configuration
        try validated.validate()
        try await configurationStore.save(validated)
    }

    func configurationRecoveryCandidate() async throws -> HomewardConfiguration? {
        try await configurationStore.loadRecoveryCandidate()
    }

    func loadNotes() async throws -> NotesDocument {
        try await notesStore.load() ?? NotesDocument()
    }

    func saveNotes(_ notes: NotesDocument) async throws {
        try await notesStore.save(notes)
    }

    func resetConfiguration() async throws {
        try await configurationStore.delete()
    }

    func resetNotes() async throws {
        try await notesStore.delete()
    }
}
