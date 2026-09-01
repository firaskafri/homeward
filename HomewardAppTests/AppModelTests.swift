import Testing
@testable import Homeward
import HomewardCore

// 1 - Name: Homeward application-model test file.
// 2 - Description: Verifies app-layer defaults and safety policy exposed to the native UI.
// 3 - Assumptions: Tests do not start workspace monitoring or issue application termination requests.
// 4 - Expectations: Initialization is side-effect free and defaults match the approved product contract.

/// 1 - Name: Homeward application-model suite.
/// 2 - Description: Covers app composition behavior that is not part of the pure core package.
/// 3 - Assumptions: Repository creation does not write until an explicit save.
/// 4 - Expectations: App startup values are safe before asynchronous bootstrap begins.
@Suite("Homeward application model")
@MainActor
struct AppModelTests {
    /// 1 - Name: Safe initialization defaults.
    /// 2 - Description: Creates the production model without starting platform observation.
    /// 3 - Assumptions: No persisted configuration is loaded until start is called.
    /// 4 - Expectations: Gentle mode and incomplete onboarding prevent termination.
    @Test
    func safeInitializationDefaults() throws {
        let model = try AppModel.makeDefault()

        #expect(model.configuration.closeMode == .gentle)
        #expect(!model.configuration.completedOnboarding)
        #expect(model.closingRows.isEmpty)
    }

    /// 1 - Name: Protected application policy.
    /// 2 - Description: Confirms Homeward and critical system applications are always excluded.
    /// 3 - Assumptions: Protection is bundle-identifier based and has no user override.
    /// 4 - Expectations: Finder, System Settings, and Homeward are present in the denylist.
    @Test
    func protectedApplicationPolicy() {
        #expect(ApplicationCatalog.protectedBundleIdentifiers.contains("com.apple.finder"))
        #expect(ApplicationCatalog.protectedBundleIdentifiers.contains("com.apple.SystemSettings"))
        #expect(ApplicationCatalog.protectedBundleIdentifiers.contains("com.firaskafri.homeward"))
    }
}
