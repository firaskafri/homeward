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

    func discover() async -> [CatalogApplication] {
        let runningURLs = workspace.runningApplications.compactMap(\.bundleURL)
        let discoveredURLs = await Self.discoverApplicationURLs()
        var uniqueByPath: [String: URL] = [:]
        for url in discoveredURLs + runningURLs {
            let standardized = url.standardizedFileURL
            uniqueByPath[standardized.path] = standardized
        }

        return uniqueByPath.values
            .compactMap(descriptor(for:))
            .sorted {
                $0.selection.displayName.localizedStandardCompare(
                    $1.selection.displayName
                ) == .orderedAscending
            }
    }

    func descriptor(for url: URL) -> CatalogApplication? {
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
        let selection = SelectedApplication(
            bundleIdentifier: bundleIdentifier,
            bundlePath: url.standardizedFileURL.path,
            displayName: displayName,
            developerName: developer,
            isResolvable: true
        )

        return CatalogApplication(
            id: selection.stableSelectionKey,
            selection: selection,
            icon: workspace.icon(forFile: url.path)
        )
    }

    private nonisolated static func discoverApplicationURLs() async -> [URL] {
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
        return roots.flatMap { root -> [URL] in
            guard let contents = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isApplicationKey],
                options: [.skipsHiddenFiles]
            ) else {
                return []
            }
            return contents.filter {
                $0.pathExtension.lowercased() == "app"
            }
        }
    }
}
