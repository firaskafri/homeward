import Foundation

public actor AtomicFileStore<Value: Codable & Sendable> {
    private static var backupExtension: String { "previous" }
    private static var quarantinePrefix: String { "corrupt-" }
    private static var directoryPermissions: Int { 0o700 }
    private static var filePermissions: Int { 0o600 }

    private let fileURL: URL
    private let backupURL: URL

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager: FileManager

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.backupURL = fileURL.appendingPathExtension(Self.backupExtension)
        self.fileManager = FileManager()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        self.decoder = decoder
    }

    public func load() throws -> Value? {
        try load(from: fileURL)
    }

    public func loadRecoveryCandidate() throws -> Value? {
        try load(from: backupURL)
    }

    public func save(_ value: Value) throws {
        let directory = fileURL.deletingLastPathComponent()
        try createSecureDirectoryIfNeeded(directory)

        let data = try encodedAndVerified(value)

        if fileManager.fileExists(atPath: fileURL.path) {
            let current = try Data(contentsOf: fileURL)
            _ = try decoder.decode(Value.self, from: current)
            try write(current, to: backupURL)
        }

        try write(data, to: fileURL)
    }

    public func replaceDuringRecovery(_ value: Value) throws {
        let directory = fileURL.deletingLastPathComponent()
        try createSecureDirectoryIfNeeded(directory)

        let data = try encodedAndVerified(value)

        if fileManager.fileExists(atPath: fileURL.path) {
            try removeQuarantinedFiles()
            let quarantineURL = fileURL
                .appendingPathExtension(
                    Self.quarantinePrefix + UUID().uuidString
                )
            try fileManager.moveItem(at: fileURL, to: quarantineURL)
            try setOwnerOnlyFilePermissions(at: quarantineURL)
        }

        try write(data, to: fileURL)
    }

    public func delete() throws {
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.removeItem(at: backupURL)
        }
        try removeQuarantinedFiles()
    }

    private func createSecureDirectoryIfNeeded(_ directory: URL) throws {
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: Self.directoryPermissions]
        )
        try fileManager.setAttributes(
            [.posixPermissions: Self.directoryPermissions],
            ofItemAtPath: directory.path
        )
    }

    private func setOwnerOnlyFilePermissions(at url: URL) throws {
        try fileManager.setAttributes(
            [.posixPermissions: Self.filePermissions],
            ofItemAtPath: url.path
        )
    }

    private func load(from url: URL) throws -> Value? {
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return try decoder.decode(Value.self, from: Data(contentsOf: url))
    }

    private func encodedAndVerified(_ value: Value) throws -> Data {
        let data = try encoder.encode(value)
        _ = try decoder.decode(Value.self, from: data)
        return data
    }

    private func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try setOwnerOnlyFilePermissions(at: url)
    }

    private func removeQuarantinedFiles() throws {
        let directory = fileURL.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: directory.path) else {
            return
        }
        let files = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        let prefix = fileURL.lastPathComponent + "." + Self.quarantinePrefix
        for file in files where file.lastPathComponent.hasPrefix(prefix) {
            try fileManager.removeItem(at: file)
        }
    }
}
