import Foundation
import HomewardCore

enum HomewardRuntime {
    static let nativeTestEnvironmentKey = "HOMEWARD_TESTING"
    static let uiTestEnvironmentKey = "HOMEWARD_UI_TESTING"
    static let xctestConfigurationEnvironmentKey =
        "XCTestConfigurationFilePath"
    static let testShellBundleIdentifier =
        "com.firaskafri.homeward.testshell"
    static let testShellStorageArgument = "--homeward-shell-storage="
    static let testShellScenarioArgument = "--homeward-shell-runtime="
    static let testReadyFileArgument = "--homeward-test-ready-file="
    static let uiTestStorageArgument = "--homeward-ui-test-storage="
    static let uiTestScenarioArgument = "--homeward-ui-test-scenario="

    static func resolvedEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> [String: String] {
        var resolved = environment
        if bundleIdentifier == testShellBundleIdentifier {
            resolved[uiTestEnvironmentKey] = "1"
            if let storage = argumentValue(
                prefix: testShellStorageArgument,
                arguments: arguments
            ) {
                resolved["HOMEWARD_STORAGE_DIRECTORY"] = storage
            }
            if let scenario = argumentValue(
                prefix: testShellScenarioArgument,
                arguments: arguments
            ) {
                resolved[HomewardUITestScenarioFixture.environmentKey] =
                    scenario
            }
        }
        if isAutomatedTest(environment: resolved) {
            if let storage = argumentValue(
                prefix: uiTestStorageArgument,
                arguments: arguments
            ) {
                resolved["HOMEWARD_STORAGE_DIRECTORY"] = storage
            }
            if let scenario = argumentValue(
                prefix: uiTestScenarioArgument,
                arguments: arguments
            ) {
                resolved[HomewardUITestScenarioFixture.environmentKey] =
                    scenario
            }
            if let readyFile = argumentValue(
                prefix: testReadyFileArgument,
                arguments: arguments
            ) {
                resolved["HOMEWARD_TEST_READY_FILE"] = readyFile
            }
        }
        return resolved
    }

    static func isAutomatedTest(environment: [String: String]) -> Bool {
        environment[nativeTestEnvironmentKey] == "1"
            || environment[uiTestEnvironmentKey] == "1"
            || environment[xctestConfigurationEnvironmentKey] != nil
    }

    private static func argumentValue(
        prefix: String,
        arguments: [String]
    ) -> String? {
        guard let argument = arguments.first(where: {
            $0.hasPrefix(prefix)
        }) else {
            return nil
        }
        let value = String(argument.dropFirst(prefix.count))
        return value.isEmpty ? nil : value
    }
}

struct ControlledApplicationIdentity {
    let bundleIdentifier: String
    let bundlePath: String
    private let canonicalBundlePath: String
    private let canonicalProductsPath: String

    init(bundleIdentifier: String, bundlePath: String) {
        self.bundleIdentifier = bundleIdentifier
        let bundleURL = URL(fileURLWithPath: bundlePath)
            .standardizedFileURL
        self.bundlePath = bundleURL.path
        canonicalBundlePath = bundleURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        canonicalProductsPath = bundleURL
            .deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }

    func matches(
        bundleIdentifier: String?,
        bundleURL: URL?
    ) -> Bool {
        guard bundleIdentifier == self.bundleIdentifier,
              let bundleURL else {
            return false
        }
        let standardized = bundleURL.standardizedFileURL
        let canonical = standardized
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let isSymbolicLink = (
            try? standardized.resourceValues(
                forKeys: [.isSymbolicLinkKey]
            ).isSymbolicLink
        ) ?? false
        return !isSymbolicLink
            && standardized.path == bundlePath
            && canonical.path == canonicalBundlePath
            && canonical.deletingLastPathComponent().path
                == canonicalProductsPath
    }
}

enum RunningApplicationControlPolicy {
    case userSelections
    case only(ControlledApplicationIdentity)

    private static let fixtureBundleIdentifier =
        "com.firaskafri.homeward.fixture"

    static func fixtureIdentity(
        productsDirectoryURL: URL
    ) -> ControlledApplicationIdentity {
        ControlledApplicationIdentity(
            bundleIdentifier: fixtureBundleIdentifier,
            bundlePath: productsDirectoryURL
                .appendingPathComponent("HomewardFixture.app")
                .path
        )
    }

    static func forRuntime(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homewardBundleURL: URL = Bundle.main.bundleURL
    ) -> RunningApplicationControlPolicy {
        if HomewardRuntime.isAutomatedTest(environment: environment) {
            return .only(fixtureIdentity(
                productsDirectoryURL:
                    homewardBundleURL.deletingLastPathComponent()
            ))
        }

        return .userSelections
    }

    func permits(
        bundleIdentifier: String?,
        bundleURL: URL?
    ) -> Bool {
        switch self {
        case .userSelections:
            return bundleIdentifier.map {
                !SelectedApplication.protectedBundleIdentifiers.contains($0)
            } ?? true
        case let .only(identity):
            return identity.matches(
                bundleIdentifier: bundleIdentifier,
                bundleURL: bundleURL
            )
        }
    }
}
