import AppKit
import Foundation
import HomewardCore

@MainActor
struct CatalogApplication: Identifiable {
    let id: String
    let selection: SelectedApplication
    let icon: NSImage
}

@MainActor
final class ApplicationCatalog {
    private struct ApplicationMetadata: Sendable {
        let bundleIdentifier: String?
        let bundlePath: String
        let displayName: String
        let developerName: String?
    }

    static let browserBundleIdentifiers: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "org.mozilla.firefox",
        "company.thebrowser.Browser",
        "com.brave.Browser",
        "com.microsoft.edgemac",
    ]

    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func discover() async throws -> [CatalogApplication] {
        let runningURLs = workspace.runningApplications.compactMap(\.bundleURL)
        let discoveredURLs = try await Self.discoverApplicationURLs()
        var uniqueByPath: [String: URL] = [:]
        for url in discoveredURLs + runningURLs {
            let standardized = url.standardizedFileURL
            uniqueByPath[standardized.path] = standardized
        }

        let metadata = await Self.applicationMetadata(
            for: Array(uniqueByPath.values)
        )
        return metadata
            .map(catalogApplication(from:))
            .sorted {
                $0.selection.displayName.localizedStandardCompare(
                    $1.selection.displayName
                ) == .orderedAscending
            }
    }

    func descriptor(for url: URL) -> CatalogApplication? {
        guard let metadata = Self.applicationMetadata(for: url) else {
            return nil
        }
        return catalogApplication(from: metadata)
    }

    private func catalogApplication(
        from metadata: ApplicationMetadata
    ) -> CatalogApplication {
        let selection = SelectedApplication(
            bundleIdentifier: metadata.bundleIdentifier,
            bundlePath: metadata.bundlePath,
            displayName: metadata.displayName,
            developerName: metadata.developerName,
            isResolvable: true
        )
        return CatalogApplication(
            id: selection.stableSelectionKey,
            selection: selection,
            icon: workspace.icon(forFile: metadata.bundlePath)
        )
    }

    private nonisolated static func applicationMetadata(
        for urls: [URL]
    ) async -> [ApplicationMetadata] {
        urls.compactMap(applicationMetadata(for:))
    }

    private nonisolated static func applicationMetadata(
        for url: URL
    ) -> ApplicationMetadata? {
        guard url.pathExtension.lowercased() == "app",
              let bundle = Bundle(url: url),
              bundle.executableURL != nil
        else {
            return nil
        }

        let info = bundle.infoDictionary ?? [:]
        if info["LSBackgroundOnly"] as? Bool == true || info["LSUIElement"] as? Bool == true {
            return nil
        }

        let bundleIdentifier = bundle.bundleIdentifier
        if let bundleIdentifier,
           SelectedApplication.protectedBundleIdentifiers.contains(
               bundleIdentifier
           ) {
            return nil
        }

        let displayName = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let developer = info["NSHumanReadableCopyright"] as? String
        return ApplicationMetadata(
            bundleIdentifier: bundleIdentifier,
            bundlePath: url.standardizedFileURL.path,
            displayName: displayName,
            developerName: developer
        )
    }

    private nonisolated static func discoverApplicationURLs() async throws
        -> [URL]
    {
        let fileManager = FileManager()
        let homeApplications = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(
                fileURLWithPath: "/System/Applications/Utilities",
                isDirectory: true
            ),
            homeApplications,
        ]
        var applications: [URL] = []
        for root in roots where fileManager.fileExists(atPath: root.path) {
            let contents = try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isApplicationKey],
                options: [.skipsHiddenFiles]
            )
            applications.append(contentsOf: contents.filter {
                $0.pathExtension.lowercased() == "app"
            })
        }
        return applications
    }
}
