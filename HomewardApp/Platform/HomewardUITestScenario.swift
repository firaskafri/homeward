import Foundation

@MainActor
final class HomewardUITestScenarioFixture {
    static let environmentKey = "HOMEWARD_UI_TEST_SCENARIO"

    enum Scenario: String {
        case standard
        case delayedStartupRetry
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
        return []
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
        case .standard, .delayedStartupRetry:
            InstallationLocationService(statusProvider: { .applications })
        }
    }
}
