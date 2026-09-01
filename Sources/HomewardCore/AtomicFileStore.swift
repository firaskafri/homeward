import Foundation

public actor AtomicFileStore<Value: Codable & Sendable> {
    public let fileURL: URL
    public let backupURL: URL

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager: FileManager

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.backupURL = fileURL.appendingPathExtension("previous")
        self.fileManager = FileManager()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        self.decoder = decoder
    }

    public func load() throws -> Value? {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(Value.self, from: data)
    }

    public func loadRecoveryCandidate() throws -> Value? {
        guard fileManager.fileExists(atPath: backupURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: backupURL)
        return try decoder.decode(Value.self, from: data)
    }

    public func save(_ value: Value) throws {
        let directory = fileURL.deletingLastPathComponent()
        try createSecureDirectoryIfNeeded(directory)

        let data = try encoder.encode(value)
        _ = try decoder.decode(Value.self, from: data)

        if fileManager.fileExists(atPath: fileURL.path) {
            let current = try Data(contentsOf: fileURL)
            _ = try decoder.decode(Value.self, from: current)
            try current.write(to: backupURL, options: .atomic)
            try setOwnerOnlyFilePermissions(at: backupURL)
        }

        try data.write(to: fileURL, options: .atomic)
        try setOwnerOnlyFilePermissions(at: fileURL)
    }

    public func delete() throws {
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.removeItem(at: backupURL)
        }
    }

    private func createSecureDirectoryIfNeeded(_ directory: URL) throws {
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
    }

    private func setOwnerOnlyFilePermissions(at url: URL) throws {
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }
}
