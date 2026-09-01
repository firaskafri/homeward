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
    static let protectedBundleIdentifiers: Set<String> = [
        "com.apple.finder",
        "com.apple.systempreferences",
        "com.apple.SystemSettings",
        "com.apple.loginwindow",
        "com.apple.dock",
        "com.firaskafri.homeward",
    ]

    private let fileManager: FileManager
    private let workspace: NSWorkspace

    init(
        fileManager: FileManager = .default,
        workspace: NSWorkspace = .shared
    ) {
        self.fileManager = fileManager
        self.workspace = workspace
    }

    func discover() -> [CatalogApplication] {
        let homeApplications = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
            homeApplications,
        ]

        let runningURLs = workspace.runningApplications.compactMap(\.bundleURL)
        let discoveredURLs = roots.flatMap(applicationURLs(in:))
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
           Self.protectedBundleIdentifiers.contains(bundleIdentifier) {
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
            isAvailable: true
        )

        return CatalogApplication(
            id: selection.stableSelectionKey,
            selection: selection,
            icon: workspace.icon(forFile: url.path)
        )
    }

    func isProtected(_ url: URL) -> Bool {
        guard let bundleIdentifier = Bundle(url: url)?.bundleIdentifier else {
            return false
        }
        return Self.protectedBundleIdentifiers.contains(bundleIdentifier)
    }

    private func applicationURLs(in root: URL) -> [URL] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isApplicationKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return contents.filter { $0.pathExtension.lowercased() == "app" }
    }
}
