import Foundation
import HomewardCore
import Testing
@testable import Homeward

// 1 - Name: Running application control policy test file.
// 2 - Description: Verifies typed test-environment isolation and fixture-only
//     lifecycle control while normal launches use non-protected selections.
// 3 - Assumptions: Automated runtimes are identified and empty launch
//     arguments are rejected before lifecycle control.
// 4 - Expectations: Automated tests are fixture-only and normal runs reject
//     protected applications at the final control boundary.

/// 1 - Name: Running application control policy suite.
/// 2 - Description: Exercises test argument isolation and the identity
///     allowlists enforced immediately before lifecycle operations.
/// 3 - Assumptions: Bundle path and identifier must both match the policy's
///     canonical identity.
/// 4 - Expectations: Mismatched identities cannot be activated, normally
///     terminated, or force-terminated through the controller.
@Suite("Running application control policy")
@MainActor
struct RunningApplicationControlPolicyTests {
    /// 1 - Name: UI-test argument isolation.
    /// 2 - Description: Resolves typed shell arguments only for the shell bundle and release arguments only in an automated runtime.
    /// 3 - Assumptions: UI test launch environments can be incomplete before SwiftUI app initialization.
    /// 4 - Expectations: Test hosts receive deterministic isolation while an ordinary production launch ignores test-only arguments.
    @Test
    func testArgumentsApplyOnlyToAutomatedBundles() {
        let arguments = [
            "HomewardTestShell",
            "--homeward-shell-storage=/tmp/homeward-shell",
            "--homeward-shell-runtime=outsideApplications",
            "--homeward-test-ready-file=/tmp/homeward-ready",
        ]
        let shell = HomewardRuntime.resolvedEnvironment(
            environment: [:],
            arguments: arguments,
            bundleIdentifier: HomewardRuntime.testShellBundleIdentifier
        )
        let production = HomewardRuntime.resolvedEnvironment(
            environment: [:],
            arguments: arguments,
            bundleIdentifier: "com.firaskafri.homeward"
        )
        let emptyShellArguments = HomewardRuntime.resolvedEnvironment(
            environment: [:],
            arguments: [
                "HomewardTestShell",
                "--homeward-shell-storage=",
                "--homeward-shell-runtime=",
            ],
            bundleIdentifier: HomewardRuntime.testShellBundleIdentifier
        )
        let releaseTest = HomewardRuntime.resolvedEnvironment(
            environment: [HomewardRuntime.uiTestEnvironmentKey: "1"],
            arguments: [
                "Homeward",
                "--homeward-ui-test-storage=/tmp/release-e2e",
                "--homeward-ui-test-scenario=releaseLifecycle",
                "--homeward-test-ready-file=/tmp/release-ready",
            ],
            bundleIdentifier: "com.firaskafri.homeward"
        )

        #expect(shell[HomewardRuntime.uiTestEnvironmentKey] == "1")
        #expect(
            shell["HOMEWARD_STORAGE_DIRECTORY"]
                == "/tmp/homeward-shell"
        )
        #expect(
            shell[HomewardUITestScenarioFixture.environmentKey]
                == "outsideApplications"
        )
        #expect(
            shell["HOMEWARD_TEST_READY_FILE"]
                == "/tmp/homeward-ready"
        )
        #expect(production.isEmpty)
        #expect(
            emptyShellArguments["HOMEWARD_STORAGE_DIRECTORY"] == nil
        )
        #expect(
            emptyShellArguments[
                HomewardUITestScenarioFixture.environmentKey
            ] == nil
        )
        #expect(
            releaseTest["HOMEWARD_STORAGE_DIRECTORY"]
                == "/tmp/release-e2e"
        )
        #expect(
            releaseTest[HomewardUITestScenarioFixture.environmentKey]
                == "releaseLifecycle"
        )
        #expect(
            releaseTest["HOMEWARD_TEST_READY_FILE"]
                == "/tmp/release-ready"
        )
    }

    /// 1 - Name: Automated runtime fixture allowlist.
    /// 2 - Description: Builds each automated-test policy and checks the
    ///     adjacent fixture's exact identity.
    /// 3 - Assumptions: Xcode places Homeward and HomewardFixture in the same
    ///     build-products directory.
    /// 4 - Expectations: Only that fixture is permitted; Slack, Cursor, and a
    ///     copied fixture are rejected.
    @Test
    func automatedRuntimeAllowsOnlyAdjacentFixture() {
        let homewardURL = URL(
            fileURLWithPath: "/tmp/HomewardBuild/Debug/Homeward.app"
        )
        let fixtureURL = URL(
            fileURLWithPath: "/tmp/HomewardBuild/Debug/HomewardFixture.app"
        )
        let testEnvironments = [
            ["HOMEWARD_TESTING": "1"],
            ["HOMEWARD_UI_TESTING": "1"],
            [
                "XCTestConfigurationFilePath":
                    "/tmp/test.xctestconfiguration",
            ],
        ]

        for environment in testEnvironments {
            let policy = RunningApplicationControlPolicy.forRuntime(
                environment: environment,
                homewardBundleURL: homewardURL
            )

            #expect(policy.permits(
                bundleIdentifier: "com.firaskafri.homeward.fixture",
                bundleURL: fixtureURL
            ))
            #expect(!policy.permits(
                bundleIdentifier: "com.example.fixture-copy",
                bundleURL: fixtureURL
            ))
            #expect(!policy.permits(
                bundleIdentifier: "com.firaskafri.homeward.fixture",
                bundleURL: URL(fileURLWithPath: "/tmp/HomewardFixture.app")
            ))
            #expect(!policy.permits(
                bundleIdentifier: "com.tinyspeck.slackmacgap",
                bundleURL: URL(fileURLWithPath: "/Applications/Slack.app")
            ))
            #expect(!policy.permits(
                bundleIdentifier: "com.todesktop.230313mzl4w4u92",
                bundleURL: URL(fileURLWithPath: "/Applications/Cursor.app")
            ))
        }
    }

    /// 1 - Name: Normal runtime application control.
    /// 2 - Description: Builds the runtime policy without an automated-test
    ///     environment and revalidates protected identities.
    /// 3 - Assumptions: Users choose their managed applications in Homeward.
    /// 4 - Expectations: The controller permits ordinary selections and
    ///     rejects Cursor even if a crafted selection reaches this boundary.
    @Test
    func normalRuntimeAllowsOnlyUnprotectedSelections() {
        let policy = RunningApplicationControlPolicy.forRuntime(
            environment: [:],
            homewardBundleURL: URL(fileURLWithPath: "/tmp/Homeward.app")
        )

        #expect(policy.permits(
            bundleIdentifier: "com.example.work",
            bundleURL: URL(fileURLWithPath: "/Applications/Work.app")
        ))
        #expect(policy.permits(
            bundleIdentifier: "com.example.communication",
            bundleURL: URL(fileURLWithPath: "/Applications/Communication.app")
        ))
        #expect(!policy.permits(
            bundleIdentifier: SelectedApplication.cursorBundleIdentifier,
            bundleURL: URL(fileURLWithPath: "/Applications/Cursor.app")
        ))
    }

    /// 1 - Name: Automated fixture symlink rejection.
    /// 2 - Description: Places a symbolic link at the otherwise expected adjacent fixture path.
    /// 3 - Assumptions: A copied or redirected fixture must not inherit the automated lifecycle allowlist.
    /// 4 - Expectations: The final policy rejects the symlink even when its bundle identifier matches.
    @Test
    func automatedRuntimeRejectsSymlinkedFixture() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let products = root.appendingPathComponent(
            "Release",
            isDirectory: true
        )
        let target = root.appendingPathComponent(
            "ActualFixture.app",
            isDirectory: true
        )
        let fixture = products.appendingPathComponent(
            "HomewardFixture.app",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: products,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: target,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: fixture,
            withDestinationURL: target
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let policy = RunningApplicationControlPolicy.forRuntime(
            environment: ["HOMEWARD_TESTING": "1"],
            homewardBundleURL: products.appendingPathComponent("Homeward.app")
        )

        #expect(!policy.permits(
            bundleIdentifier: "com.firaskafri.homeward.fixture",
            bundleURL: fixture
        ))
    }
}
