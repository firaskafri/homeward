import Foundation
import HomewardCore
import Testing
@testable import Homeward

// 1 - Name: Running application control policy test file.
// 2 - Description: Verifies automated tests are fixture-only while normal app
//     launches control only non-protected user selections.
// 3 - Assumptions: Automated runtimes are identified before lifecycle control.
// 4 - Expectations: Automated tests are fixture-only and normal runs reject
//     protected applications at the final control boundary.

/// 1 - Name: Running application control policy suite.
/// 2 - Description: Exercises the identity allowlists enforced immediately
///     before lifecycle operations.
/// 3 - Assumptions: Bundle path and identifier must both match the policy's
///     canonical identity.
/// 4 - Expectations: Mismatched identities cannot be activated, normally
///     terminated, or force-terminated through the controller.
@Suite("Running application control policy")
@MainActor
struct RunningApplicationControlPolicyTests {
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
}
