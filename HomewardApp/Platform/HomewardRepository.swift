import Foundation
import HomewardCore

actor HomewardRepository {
    private let configurationStore: AtomicFileStore<HomewardConfiguration>
    private let notesStore: AtomicFileStore<NotesDocument>

    init() throws {
        let fileManager = FileManager()
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
        guard let configuration = try await configurationStore.load() else {
            return nil
        }
        try configuration.validate()
        return configuration
    }

    @discardableResult
    func saveConfiguration(
        _ configuration: HomewardConfiguration
    ) async throws -> HomewardConfiguration {
        let validated = configuration
        try validated.validate()
        try await configurationStore.save(validated)
        return validated
    }

    @discardableResult
    func replaceConfigurationDuringRecovery(
        _ configuration: HomewardConfiguration
    ) async throws -> HomewardConfiguration {
        let validated = configuration
        try validated.validate()
        try await configurationStore.replaceDuringRecovery(validated)
        return validated
    }

    func configurationRecoveryCandidate() async throws -> HomewardConfiguration? {
        guard let configuration = try await configurationStore
            .loadRecoveryCandidate() else {
            return nil
        }
        try configuration.validate()
        return configuration
    }

    func loadNotes() async throws -> NotesDocument {
        let notes = try await notesStore.load() ?? NotesDocument()
        try notes.validate()
        return notes
    }

    @discardableResult
    func saveNotes(_ notes: NotesDocument) async throws -> NotesDocument {
        let validated = notes
        try validated.validate()
        try await notesStore.save(validated)
        return validated
    }

    func resetNotes() async throws {
        try await notesStore.delete()
    }
}
