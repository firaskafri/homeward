import Foundation

enum BuiltApplicationLocatorError: Error {
    case missingTestRunner
    case invalidBuildProduct(URL)
}

enum BuiltApplicationLocator {
    static func productsDirectory(testBundle: Bundle) throws -> URL {
        var runnerURL = testBundle.bundleURL.standardizedFileURL
        while runnerURL.pathExtension != "app", runnerURL.path != "/" {
            runnerURL.deleteLastPathComponent()
        }
        guard runnerURL.pathExtension == "app" else {
            throw BuiltApplicationLocatorError.missingTestRunner
        }
        return runnerURL.deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .standardizedFileURL
    }

    static func application(
        named name: String,
        bundleIdentifier: String,
        testBundle: Bundle
    ) throws -> URL {
        try application(
            named: name,
            bundleIdentifier: bundleIdentifier,
            productsDirectory: productsDirectory(testBundle: testBundle)
        )
    }

    static func application(
        named name: String,
        bundleIdentifier: String,
        productsDirectory: URL
    ) throws -> URL {
        let unresolved = productsDirectory.appendingPathComponent(
            name,
            isDirectory: true
        )
        let resolved = unresolved.resolvingSymlinksInPath()
            .standardizedFileURL
        let isSymbolicLink = (
            try? unresolved.resourceValues(
                forKeys: [.isSymbolicLinkKey]
            ).isSymbolicLink
        ) ?? false
        guard !isSymbolicLink,
              resolved.deletingLastPathComponent() == productsDirectory,
              FileManager.default.fileExists(atPath: resolved.path),
              Bundle(url: resolved)?.bundleIdentifier == bundleIdentifier
        else {
            throw BuiltApplicationLocatorError.invalidBuildProduct(
                unresolved
            )
        }
        return resolved
    }
}
