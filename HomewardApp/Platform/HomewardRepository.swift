import Foundation
import HomewardCore

actor HomewardRepository {
    nonisolated private static let configurationFilename =
        "configuration.json"
    nonisolated private static let notesFilename = "notes.json"

    private let directoryProvider: @Sendable () throws -> URL
    private var configurationStore: AtomicFileStore<HomewardConfiguration>?
    private var notesStore: AtomicFileStore<NotesDocument>?

    init() {
        self.init(environment: ProcessInfo.processInfo.environment)
    }

    init(environment: [String: String]) {
        directoryProvider = {
            try Self.defaultDirectoryURL(environment: environment)
        }
    }

    init(directoryURL: URL) {
        directoryProvider = { directoryURL }
        let stores = Self.makeStores(directoryURL: directoryURL)
        configurationStore = stores.configuration
        notesStore = stores.notes
    }

    init(
        directoryProvider: @escaping @Sendable () throws -> URL
    ) {
        self.directoryProvider = directoryProvider
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
        let configurationStore = try stores().configuration
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
        let configurationStore = try stores().configuration
        let validated = configuration
        try validated.validate()
        try await configurationStore.save(validated)
        return validated
    }

    @discardableResult
    func replaceConfigurationDuringRecovery(
        _ configuration: HomewardConfiguration
    ) async throws -> HomewardConfiguration {
        let configurationStore = try stores().configuration
        let validated = configuration
        try validated.validate()
        try await configurationStore.replaceDuringRecovery(validated)
        return validated
    }

    func configurationRecoveryCandidate() async throws -> HomewardConfiguration? {
        let configurationStore = try stores().configuration
        guard let configuration = try await configurationStore
            .loadRecoveryCandidate() else {
            return nil
        }
        try configuration.validate()
        return configuration
    }

    func loadNotes() async throws -> NotesDocument {
        let notesStore = try stores().notes
        let notes = try await notesStore.load() ?? NotesDocument()
        try notes.validate()
        return notes
    }

    @discardableResult
    func saveNotes(_ notes: NotesDocument) async throws -> NotesDocument {
        let notesStore = try stores().notes
        let validated = notes
        try validated.validate()
        try await notesStore.save(validated)
        return validated
    }

    @discardableResult
    func replaceNotesDuringRecovery(
        _ notes: NotesDocument
    ) async throws -> NotesDocument {
        let notesStore = try stores().notes
        let validated = notes
        try validated.validate()
        try await notesStore.replaceDuringRecovery(validated)
        return validated
    }

    func notesRecoveryCandidate() async throws -> NotesDocument? {
        let notesStore = try stores().notes
        guard let notes = try await notesStore.loadRecoveryCandidate() else {
            return nil
        }
        try notes.validate()
        return notes
    }

    func resetNotes() async throws {
        let notesStore = try stores().notes
        try await notesStore.delete()
    }

    private func stores() throws -> (
        configuration: AtomicFileStore<HomewardConfiguration>,
        notes: AtomicFileStore<NotesDocument>
    ) {
        if let configurationStore, let notesStore {
            return (configurationStore, notesStore)
        }
        let directoryURL = try directoryProvider()
        let stores = Self.makeStores(directoryURL: directoryURL)
        configurationStore = stores.configuration
        notesStore = stores.notes
        return stores
    }

    nonisolated private static func makeStores(
        directoryURL: URL
    ) -> (
        configuration: AtomicFileStore<HomewardConfiguration>,
        notes: AtomicFileStore<NotesDocument>
    ) {
        (
            AtomicFileStore(
                fileURL: directoryURL.appendingPathComponent(
                    configurationFilename
                )
            ),
            AtomicFileStore(
                fileURL: directoryURL.appendingPathComponent(notesFilename)
            )
        )
    }
}
