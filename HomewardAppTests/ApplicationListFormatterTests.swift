import Testing
@testable import Homeward

// 1 - Name: Application list formatter test file.
// 2 - Description: Verifies concise application summaries and duplicate-process disambiguation used by closing controls.
// 3 - Assumptions: Display names can repeat when one application owns multiple running processes.
// 4 - Expectations: Unique names stay calm while duplicate names expose explicit process scope.

/// 1 - Name: Application list formatter suite.
/// 2 - Description: Covers process labels for unique and duplicate application names.
/// 3 - Assumptions: Process identifiers distinguish simultaneous instances without exposing unrelated metadata.
/// 4 - Expectations: Action labels identify the exact process only when the display name alone is ambiguous.
@Suite("Application list formatter")
@MainActor
struct ApplicationListFormatterTests {
    /// 1 - Name: Unique process label.
    /// 2 - Description: Formats one application name with no duplicate peer.
    /// 3 - Assumptions: A unique display name already identifies the target clearly.
    /// 4 - Expectations: The visible label remains the original application name.
    @Test
    func uniqueNameRemainsConcise() {
        #expect(ApplicationListFormatter.processLabel(
            name: "Studio",
            processIdentifier: 41,
            allNames: ["Studio", "Messages"]
        ) == "Studio")
    }

    /// 1 - Name: Duplicate process label.
    /// 2 - Description: Formats one of two running processes sharing an application name.
    /// 3 - Assumptions: The process identifier is the user-visible action scope for duplicate names.
    /// 4 - Expectations: The label appends the exact process identifier.
    @Test
    func duplicateNameIncludesProcessIdentifier() {
        #expect(ApplicationListFormatter.processLabel(
            name: "Studio",
            processIdentifier: 42,
            allNames: ["Studio", "Studio"]
        ) == "Studio — Process 42")
    }
}
