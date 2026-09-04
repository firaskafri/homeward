import Foundation
import HomewardCore

actor HomewardRepository {
    nonisolated private static let configurationFilename =
        "configuration.json"
    nonisolated private static let notesFilename = "notes.json"

    private let configurationStore: AtomicFileStore<HomewardConfiguration>
    private let notesStore: AtomicFileStore<NotesDocument>

    init() throws {
        self.init(directoryURL: try Self.defaultDirectoryURL())
    }

    init(directoryURL: URL) {
        configurationStore = AtomicFileStore(
            fileURL: directoryURL.appendingPathComponent(
                Self.configurationFilename
            )
        )
        notesStore = AtomicFileStore(
            fileURL: directoryURL.appendingPathComponent(Self.notesFilename)
        )
    }

    nonisolated static func defaultDirectoryURL(
        fileManager: FileManager = FileManager(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL {
        if let storagePath = environment["HOMEWARD_STORAGE_DIRECTORY"],
           !storagePath.isEmpty {
            return URL(fileURLWithPath: storagePath, isDirectory: true)
        }
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return applicationSupport
            .appendingPathComponent("Homeward", isDirectory: true)
    }

    nonisolated static func shouldPresentMainWindow() -> Bool {
        guard let directoryURL = try? defaultDirectoryURL() else {
            return true
        }
        return shouldPresentMainWindow(directoryURL: directoryURL)
    }

    nonisolated static func shouldPresentMainWindow(
        directoryURL: URL
    ) -> Bool {
        do {
            let configurationURL = directoryURL.appendingPathComponent(
                configurationFilename
            )
            guard FileManager.default.fileExists(
                atPath: configurationURL.path
            ) else {
                return true
            }
            let data = try Data(contentsOf: configurationURL)
            let configuration = try JSONDecoder().decode(
                HomewardConfiguration.self,
                from: data
            )
            return !configuration.completedOnboarding
        } catch {
            return true
        }
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
