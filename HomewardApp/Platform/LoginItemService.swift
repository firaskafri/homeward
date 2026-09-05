import Foundation
import AppKit
import ServiceManagement

enum InstallationLocationStatus: Equatable {
    case applications
    case outsideApplications(URL)
    case requiresRelaunch(URL)
    case unavailable

    var supportsStartAtLogin: Bool {
        self == .applications
    }
}

@MainActor
final class InstallationLocationService {
    private let statusProvider: () -> InstallationLocationStatus
    private let reveal: (URL) -> Void

    init(
        bundleURL: URL = Bundle.main.bundleURL,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        applicationsURL: URL = URL(
            fileURLWithPath: "/Applications",
            isDirectory: true
        ),
        fileManager: FileManager = .default,
        workspace: NSWorkspace = .shared
    ) {
        let launchedURL = bundleURL.resolvingSymlinksInPath()
            .standardizedFileURL
        let applicationsURL = applicationsURL.resolvingSymlinksInPath()
            .standardizedFileURL
        let bookmarkData = try? launchedURL.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        statusProvider = {
            let currentURL: URL
            if let bookmarkData {
                var isStale = false
                currentURL = (
                    try? URL(
                        resolvingBookmarkData: bookmarkData,
                        options: [.withoutUI, .withoutMounting],
                        relativeTo: nil,
                        bookmarkDataIsStale: &isStale
                    )
                )?.resolvingSymlinksInPath().standardizedFileURL
                    ?? launchedURL
            } else {
                currentURL = launchedURL
            }
            guard currentURL.pathExtension == "app" else {
                return .unavailable
            }
            guard currentURL.deletingLastPathComponent()
                    == applicationsURL else {
                if let installedURL = Self.installedApplicationURL(
                    named: launchedURL.lastPathComponent,
                    bundleIdentifier: bundleIdentifier,
                    in: applicationsURL,
                    fileManager: fileManager
                ) {
                    return .requiresRelaunch(installedURL)
                }
                return .outsideApplications(currentURL)
            }
            return launchedURL.deletingLastPathComponent() == applicationsURL
                ? .applications
                : .requiresRelaunch(currentURL)
        }
        reveal = { workspace.activateFileViewerSelecting([$0]) }
    }

    private static func installedApplicationURL(
        named applicationName: String,
        bundleIdentifier: String?,
        in applicationsURL: URL,
        fileManager: FileManager
    ) -> URL? {
        let preferredURL = applicationsURL.appendingPathComponent(
            applicationName,
            isDirectory: true
        )
        func matchesInstalledApplication(_ candidate: URL) -> Bool {
            guard candidate.pathExtension == "app",
                  fileManager.fileExists(atPath: candidate.path) else {
                return false
            }
            guard let bundleIdentifier else {
                return candidate.standardizedFileURL
                    == preferredURL.standardizedFileURL
            }
            return Bundle(url: candidate)?.bundleIdentifier == bundleIdentifier
        }
        if matchesInstalledApplication(preferredURL) {
            return preferredURL.resolvingSymlinksInPath().standardizedFileURL
        }
        guard bundleIdentifier != nil,
              let candidates = try? fileManager.contentsOfDirectory(
                  at: applicationsURL,
                  includingPropertiesForKeys: nil,
                  options: [.skipsHiddenFiles]
              ) else {
            return nil
        }
        return candidates
            .sorted { $0.path < $1.path }
            .first(where: matchesInstalledApplication)?
            .resolvingSymlinksInPath().standardizedFileURL
    }

    init(
        statusProvider: @escaping () -> InstallationLocationStatus,
        reveal: @escaping (URL) -> Void = { _ in }
    ) {
        self.statusProvider = statusProvider
        self.reveal = reveal
    }

    var status: InstallationLocationStatus {
        statusProvider()
    }

    func showInFinder() {
        switch status {
        case let .outsideApplications(url), let .requiresRelaunch(url):
            reveal(url)
        case .applications, .unavailable:
            break
        }
    }
}

@MainActor
final class LoginItemService {
    enum Status: Equatable {
        case notRegistered
        case enabled
        case requiresApproval
        case notFound
        case unavailable
    }

    enum ServiceError: Error, Equatable {
        case unavailable
    }

    private let statusProvider: () -> Status
    private let register: () throws -> Void
    private let unregister: () throws -> Void
    private let openSettings: () -> Void

    init(service: SMAppService = .mainApp) {
        statusProvider = {
            switch service.status {
            case .notRegistered:
                return .notRegistered
            case .enabled:
                return .enabled
            case .requiresApproval:
                return .requiresApproval
            case .notFound:
                return .notFound
            @unknown default:
                return .unavailable
            }
        }
        register = {
            try service.register()
        }
        unregister = {
            try service.unregister()
        }
        openSettings = {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    init(
        statusProvider: @escaping () -> Status,
        register: @escaping () throws -> Void = {},
        unregister: @escaping () throws -> Void = {},
        openSettings: @escaping () -> Void = {}
    ) {
        self.statusProvider = statusProvider
        self.register = register
        self.unregister = unregister
        self.openSettings = openSettings
    }

    static func isolatedForUITesting() -> LoginItemService {
        LoginItemService(statusProvider: { .notRegistered })
    }

    var status: Status {
        statusProvider()
    }

    func enable() throws {
        guard statusProvider() != .unavailable else {
            throw ServiceError.unavailable
        }
        try register()
    }

    func disable() throws {
        switch statusProvider() {
        case .enabled, .requiresApproval:
            try unregister()
        case .notRegistered, .notFound:
            return
        case .unavailable:
            throw ServiceError.unavailable
        }
    }

    func openSystemSettings() {
        openSettings()
    }
}
