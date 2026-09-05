import AppKit
import Foundation
import HomewardCore

@MainActor
final class HomewardUITestScenarioFixture {
    static let environmentKey = "HOMEWARD_UI_TEST_SCENARIO"

    enum Scenario: String {
        case standard
        case delayedStartupRetry
        case loginApproval
        case loginEnabled
        case movedToApplications
        case outsideApplications
    }

    private let scenario: Scenario
    private var catalogDiscoveryCount = 0

    init(environment: [String: String]) {
        guard environment[HomewardRuntime.uiTestEnvironmentKey] == "1" else {
            preconditionFailure(
                "UI test scenarios require HOMEWARD_UI_TESTING=1."
            )
        }
        let rawValue = environment[Self.environmentKey]
            ?? Scenario.standard.rawValue
        guard let scenario = Scenario(rawValue: rawValue) else {
            preconditionFailure("Unknown Homeward UI test scenario: \(rawValue)")
        }
        self.scenario = scenario
    }

    var beginsInDelayedStartup: Bool {
        scenario == .delayedStartupRetry
    }

    func discoverApplications() async throws -> [CatalogApplication] {
        catalogDiscoveryCount += 1
        if scenario == .delayedStartupRetry,
           catalogDiscoveryCount == 1 {
            try await Task.sleep(for: .seconds(30))
        }
        guard scenario == .outsideApplications else {
            return []
        }
        return [
            application(
                name: "Studio",
                bundleIdentifier: "com.homeward.preview.studio",
                path: "/Applications/Studio.app"
            ),
            application(
                name: "Team Messages",
                bundleIdentifier: "com.homeward.preview.messages",
                path: "/Applications/Team Messages.app"
            ),
            application(
                name: "Work Mail",
                bundleIdentifier: "com.homeward.preview.mail",
                path: "/Applications/Work Mail.app"
            ),
        ]
    }

    var installationLocationService: InstallationLocationService {
        switch scenario {
        case .outsideApplications:
            InstallationLocationService(
                statusProvider: {
                    .outsideApplications(
                        URL(fileURLWithPath: "/tmp/HomewardUITests/Homeward.app")
                    )
                }
            )
        case .movedToApplications:
            InstallationLocationService(
                statusProvider: {
                    .requiresRelaunch(
                        URL(fileURLWithPath: "/Applications/Homeward.app")
                    )
                }
            )
        case .standard, .delayedStartupRetry, .loginApproval, .loginEnabled:
            InstallationLocationService(statusProvider: { .applications })
        }
    }

    var loginItemService: LoginItemService {
        let status: LoginItemService.Status = switch scenario {
        case .loginApproval:
            .requiresApproval
        case .loginEnabled:
            .enabled
        default:
            .notRegistered
        }
        return LoginItemService(statusProvider: { status })
    }

    private func application(
        name: String,
        bundleIdentifier: String,
        path: String
    ) -> CatalogApplication {
        CatalogApplication(
            id: bundleIdentifier,
            selection: SelectedApplication(
                bundleIdentifier: bundleIdentifier,
                bundlePath: path,
                displayName: name,
                developerName: "Homeward Preview"
            ),
            icon: NSImage(size: NSSize(width: 16, height: 16))
        )
    }
}
