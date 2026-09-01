import Foundation
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

    /// 1 - Name: Custom cutoff override pair.
    /// 2 - Description: Verifies the app model stores availability until cutoff and blocking afterward as one logical change.
    /// 3 - Assumptions: The selected cutoff is a valid future instant within the current local day.
    /// 4 - Expectations: The configuration contains one allow and one future block override.
    @Test
    func customCutoffOverridePair() async throws {
        let fixture = try AppModelFixture()
        defer { fixture.remove() }
        let model = try AppModel(repository: HomewardRepository(
            directoryURL: fixture.directoryURL
        ))
        let now = Date()
        let calendar = Calendar.autoupdatingCurrent
        let midnight = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: now)
        )!
        let cutoff = min(now.addingTimeInterval(30), midnight.addingTimeInterval(-0.1))

        await model.chooseCutoff(cutoff)

        let custom = model.configuration.overrides.filter {
            $0.kind == .customCutoff
        }
        #expect(custom.count == 2)
        #expect(Set(custom.map(\.effect)) == [.allow, .block])
    }

    /// 1 - Name: Stop Force Quit runtime latch.
    /// 2 - Description: Applies the safety action before relying on persistence.
    /// 3 - Assumptions: No running targets are required to create the blocked-interval pause.
    /// 4 - Expectations: Runtime policy and persisted configuration both report force escalation paused.
    @Test
    func stopForceQuitCreatesSafetyLatch() async throws {
        let fixture = try AppModelFixture()
        defer { fixture.remove() }
        let model = try AppModel(repository: HomewardRepository(
            directoryURL: fixture.directoryURL
        ))

        await model.stopForceQuit()

        #expect(model.forceEscalationPaused)
        #expect(model.configuration.overrides.contains {
            $0.kind == .forceEscalationPaused
        })
    }

    /// 1 - Name: Return to weekly schedule preserves force pause.
    /// 2 - Description: Removes today-only availability policy without bypassing an explicit Firm safety pause.
    /// 3 - Assumptions: Stop Force Quit and availability overrides have distinct purposes.
    /// 4 - Expectations: Only the force-pause override remains.
    @Test
    func returnToWeeklySchedulePreservesForcePause() async throws {
        let fixture = try AppModelFixture()
        defer { fixture.remove() }
        let model = try AppModel(repository: HomewardRepository(
            directoryURL: fixture.directoryURL
        ))
        await model.stopForceQuit()
        await model.createExtension(minutes: 10)

        await model.returnToWeeklySchedule()

        #expect(model.configuration.overrides.allSatisfy {
            $0.kind == .forceEscalationPaused
        })
    }

    /// 1 - Name: Protected app rejected at model boundary.
    /// 2 - Description: Attempts to add Finder without going through the picker.
    /// 3 - Assumptions: Persisted and programmatic inputs are untrusted.
    /// 4 - Expectations: Finder is not selected and an explanatory error is published.
    @Test
    func protectedAppRejectedAtModelBoundary() async throws {
        let fixture = try AppModelFixture()
        defer { fixture.remove() }
        let model = try AppModel(repository: HomewardRepository(
            directoryURL: fixture.directoryURL
        ))
        let finder = SelectedApplication(
            bundleIdentifier: "com.apple.finder",
            bundlePath: "/System/Library/CoreServices/Finder.app",
            displayName: "Finder"
        )

        await model.addApplication(finder)

        #expect(model.configuration.selectedApplications.isEmpty)
        #expect(model.lastError != nil)
    }

    /// 1 - Name: Repository validates decoded configuration.
    /// 2 - Description: Writes a syntactically valid but protected selection directly to storage.
    /// 3 - Assumptions: Codable decoding bypasses model initializers and therefore requires an explicit validation pass.
    /// 4 - Expectations: Repository load rejects the protected persisted policy.
    @Test
    func repositoryValidatesDecodedConfiguration() async throws {
        let fixture = try AppModelFixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(
            at: fixture.directoryURL,
            withIntermediateDirectories: true
        )
        var configuration = try HomewardConfiguration.initial()
        configuration.selectedApplications = [
            SelectedApplication(
                bundleIdentifier: "com.apple.finder",
                bundlePath: "/System/Library/CoreServices/Finder.app",
                displayName: "Finder"
            ),
        ]
        let data = try JSONEncoder().encode(configuration)
        try data.write(
            to: fixture.directoryURL.appendingPathComponent("configuration.json")
        )
        let repository = HomewardRepository(directoryURL: fixture.directoryURL)

        await #expect(throws: ConfigurationError.protectedApplicationSelection(
            "com.apple.finder"
        )) {
            _ = try await repository.loadConfiguration()
        }
    }
}

private struct AppModelFixture {
    let directoryURL: URL

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("HomewardAppModelTests-\(UUID().uuidString)")
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
