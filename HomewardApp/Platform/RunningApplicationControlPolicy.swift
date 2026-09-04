import Foundation

enum HomewardRuntime {
    static let nativeTestEnvironmentKey = "HOMEWARD_TESTING"
    static let uiTestEnvironmentKey = "HOMEWARD_UI_TESTING"
    static let xctestConfigurationEnvironmentKey =
        "XCTestConfigurationFilePath"

    static func isAutomatedTest(environment: [String: String]) -> Bool {
        environment[nativeTestEnvironmentKey] == "1"
            || environment[uiTestEnvironmentKey] == "1"
            || environment[xctestConfigurationEnvironmentKey] != nil
    }
}

struct ControlledApplicationIdentity {
    let bundleIdentifier: String
    let bundlePath: String

    init(bundleIdentifier: String, bundlePath: String) {
        self.bundleIdentifier = bundleIdentifier
        self.bundlePath = URL(fileURLWithPath: bundlePath)
            .standardizedFileURL
            .path
    }

    func matches(
        bundleIdentifier: String?,
        bundleURL: URL?
    ) -> Bool {
        bundleIdentifier == self.bundleIdentifier
            && bundleURL?.standardizedFileURL.path == bundlePath
    }
}

enum RunningApplicationControlPolicy {
    case unrestricted
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

        return .unrestricted
    }

    func permits(
        bundleIdentifier: String?,
        bundleURL: URL?
    ) -> Bool {
        switch self {
        case .unrestricted:
            return true
        case let .only(identity):
            return identity.matches(
                bundleIdentifier: bundleIdentifier,
                bundleURL: bundleURL
            )
        }
    }
}
