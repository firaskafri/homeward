import Foundation
import Testing
@testable import HomewardCore

// 1 - Name: Enforcement planner test file.
// 2 - Description: Verifies safe application matching, deterministic target ownership, and fail-open Firm eligibility.
// 3 - Assumptions: Platform adapters provide immutable snapshots and retain real AppKit process handles separately.
// 4 - Expectations: Only current, selected, identifiable, non-protected processes become uniquely owned targets.

/// 1 - Name: Enforcement planner suite.
/// 2 - Description: Exercises protected-process filtering, target deduplication, and force planning without termination APIs.
/// 3 - Assumptions: Bundle identity applies to every matching copy and UUID order resolves overlapping selections.
/// 4 - Expectations: Safety failures exclude targets and each process session has one deterministic selection owner.
@Suite("Enforcement planner")
struct EnforcementPlannerTests {
    /// 1 - Name: Bundle identifier matches every copy.
    /// 2 - Description: Creates targets for two running processes with the same selected bundle identifier.
    /// 3 - Assumptions: Duplicate installed copies share one selection policy by design.
    /// 4 - Expectations: Both distinct process sessions become targets.
    @Test
    func bundleIdentifierMatchesEveryCopy() {
        let selection = SelectedApplication(
            bundleIdentifier: "com.example.editor",
            bundlePath: "/Applications/Editor.app",
            displayName: "Editor"
        )
        let processes = [
            process(pid: 10, bundleIdentifier: "com.example.editor", path: "/Applications/Editor.app"),
            process(pid: 11, bundleIdentifier: "com.example.editor", path: "/Users/me/Editor.app"),
        ]

        let targets = EnforcementPlanner().targets(
            selections: [selection],
            runningApplications: processes
        )

        #expect(targets.count == 2)
        #expect(Set(targets.map(\.id)).count == 2)
    }

    /// 1 - Name: Identifier-less selection uses exact standardized path.
    /// 2 - Description: Matches a path-only selection to one canonicalized bundle path.
    /// 3 - Assumptions: Platform discovery has already rejected ambiguous replacements.
    /// 4 - Expectations: Only the exact standardized path becomes a target.
    @Test
    func identifierlessSelectionUsesPath() {
        let selection = SelectedApplication(
            bundleIdentifier: nil,
            bundlePath: "/Applications/../Applications/Tool.app",
            displayName: "Tool"
        )
        let targets = EnforcementPlanner().targets(
            selections: [selection],
            runningApplications: [
                process(pid: 10, bundleIdentifier: nil, path: "/Applications/Tool.app"),
                process(pid: 11, bundleIdentifier: nil, path: "/Users/me/Tool.app"),
            ]
        )

        #expect(targets.map(\.process.processIdentifier) == [10])
    }

    /// 1 - Name: Duplicate process target ownership.
    /// 2 - Description: Matches one process through bundle and path selections supplied in both orders.
    /// 3 - Assumptions: Selection UUID text is a stable ownership tie-break independent of caller order.
    /// 4 - Expectations: One process-session target remains and the lower UUID selection owns it.
    @Test
    func duplicateProcessTargetsUseDeterministicSelectionOwner() {
        let lowerIDSelection = SelectedApplication(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            bundleIdentifier: "com.example.editor",
            bundlePath: "/Applications/Editor.app",
            displayName: "Editor"
        )
        let higherIDSelection = SelectedApplication(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            bundleIdentifier: nil,
            bundlePath: "/Applications/Editor.app",
            displayName: "Editor by path"
        )
        let running = process(
            pid: 10,
            bundleIdentifier: "com.example.editor",
            path: "/Applications/Editor.app"
        )
        let planner = EnforcementPlanner()

        let forward = planner.targets(
            selections: [lowerIDSelection, higherIDSelection],
            runningApplications: [running]
        )
        let reversed = planner.targets(
            selections: [higherIDSelection, lowerIDSelection],
            runningApplications: [running]
        )

        #expect(forward.count == 1)
        #expect(reversed.count == 1)
        #expect(forward.first?.selectionID == lowerIDSelection.id)
        #expect(reversed.first?.selectionID == lowerIDSelection.id)
    }

    /// 1 - Name: Missing launch identity fails open.
    /// 2 - Description: Excludes a running process that lacks a launch date.
    /// 3 - Assumptions: PID alone is insufficient protection against process reuse.
    /// 4 - Expectations: The planner creates no enforcement target.
    @Test
    func missingLaunchIdentityFailsOpen() {
        let selection = SelectedApplication(
            bundleIdentifier: "com.example.editor",
            bundlePath: "/Applications/Editor.app",
            displayName: "Editor"
        )
        let unidentified = RunningApplicationSnapshot(
            processIdentifier: 10,
            bundleIdentifier: "com.example.editor",
            bundlePath: "/Applications/Editor.app",
            displayName: "Editor",
            launchedAt: nil
        )

        let targets = EnforcementPlanner().targets(
            selections: [selection],
            runningApplications: [unidentified]
        )

        #expect(targets.isEmpty)
    }

    /// 1 - Name: Unresolved selection fails open.
    /// 2 - Description: Excludes a selected application whose persisted bundle can no longer be resolved.
    /// 3 - Assumptions: A stale bundle identity must be reselected before enforcement can safely resume.
    /// 4 - Expectations: The planner creates no normal-quit or force-quit target.
    @Test
    func unresolvedSelectionFailsOpen() throws {
        let selection = SelectedApplication(
            bundleIdentifier: "com.example.editor",
            bundlePath: "/Applications/Editor.app",
            displayName: "Editor",
            isResolvable: false
        )
        let running = process(
            pid: 10,
            bundleIdentifier: "com.example.editor",
            path: "/Applications/Editor.app"
        )

        let targets = EnforcementPlanner().targets(
            selections: [selection],
            runningApplications: [running]
        )
        let craftedTarget = try EnforcementTarget(
            selectionID: selection.id,
            process: running
        )
        let forceEligible = EnforcementPlanner().forceEligibleTargetIDs(
            session: EnforcementSession(
                mode: .firm,
                startedAt: Date(timeIntervalSince1970: 0),
                targets: [craftedTarget]
            ),
            at: Date(timeIntervalSince1970: 60),
            schedule: ResolvedSchedule(
                phase: .workClosed,
                isAvailable: false,
                activeBaseInterval: nil,
                activeOverride: nil,
                nextTransition: nil,
                nextAvailability: nil
            ),
            currentSelections: [selection],
            currentlyRunning: [running]
        )

        #expect(targets.isEmpty)
        #expect(forceEligible.isEmpty)
    }

    /// 1 - Name: Protected selection fails open.
    /// 2 - Description: Revalidates protected identity at the termination-planning boundary.
    /// 3 - Assumptions: Persisted or in-memory policy may be corrupted outside the normal picker.
    /// 4 - Expectations: Finder never becomes a normal or forced termination target.
    @Test
    func protectedSelectionFailsOpen() throws {
        let selection = SelectedApplication(
            bundleIdentifier: "com.apple.finder",
            bundlePath: "/System/Library/CoreServices/Finder.app",
            displayName: "Finder"
        )
        let running = process(
            pid: 10,
            bundleIdentifier: "com.apple.finder",
            path: "/System/Library/CoreServices/Finder.app"
        )

        let targets = EnforcementPlanner().targets(
            selections: [selection],
            runningApplications: [running]
        )
        let craftedTarget = try EnforcementTarget(
            selectionID: selection.id,
            process: running
        )
        let session = EnforcementSession(
            mode: .firm,
            startedAt: Date(timeIntervalSince1970: 0),
            targets: [craftedTarget]
        )
        let blocked = ResolvedSchedule(
            phase: .workClosed,
            isAvailable: false,
            activeBaseInterval: nil,
            activeOverride: nil,
            nextTransition: nil,
            nextAvailability: nil
        )
        let forceEligible = EnforcementPlanner().forceEligibleTargetIDs(
            session: session,
            at: Date(timeIntervalSince1970: 60),
            schedule: blocked,
            currentSelections: [selection],
            currentlyRunning: [running]
        )

        #expect(targets.isEmpty)
        #expect(forceEligible.isEmpty)
    }

    /// 1 - Name: Path-only selection cannot target protected process.
    /// 2 - Description: Revalidates the running process bundle identity when an unprotected path-only selection matches it.
    /// 3 - Assumptions: A protected running app reports its protected bundle identifier even if selection metadata omits it.
    /// 4 - Expectations: Finder is excluded from normal targeting and from force eligibility for a crafted session.
    @Test
    func pathOnlySelectionCannotTargetProtectedRunningApplication() throws {
        let selection = SelectedApplication(
            bundleIdentifier: nil,
            bundlePath: "/System/Library/CoreServices/Finder.app",
            displayName: "Finder by path"
        )
        let running = process(
            pid: 10,
            bundleIdentifier: "com.apple.finder",
            path: "/System/Library/CoreServices/Finder.app"
        )
        let planner = EnforcementPlanner()
        let targets = planner.targets(
            selections: [selection],
            runningApplications: [running]
        )
        let craftedTarget = try EnforcementTarget(
            selectionID: selection.id,
            process: running
        )
        let forceEligible = planner.forceEligibleTargetIDs(
            session: EnforcementSession(
                mode: .firm,
                startedAt: Date(timeIntervalSince1970: 0),
                targets: [craftedTarget]
            ),
            at: Date(timeIntervalSince1970: 60),
            schedule: ResolvedSchedule(
                phase: .workClosed,
                isAvailable: false,
                activeBaseInterval: nil,
                activeOverride: nil,
                nextTransition: nil,
                nextAvailability: nil
            ),
            currentSelections: [selection],
            currentlyRunning: [running]
        )

        #expect(targets.isEmpty)
        #expect(forceEligible.isEmpty)
    }

    /// 1 - Name: Firm force eligibility.
    /// 2 - Description: Requires elapsed grace, blocked policy, current selection, and exact live process identity.
    /// 3 - Assumptions: The session began with a normal quit request at its start time.
    /// 4 - Expectations: Eligibility appears only after 30 seconds while every invariant remains true.
    @Test
    func firmForceEligibility() throws {
        let selection = SelectedApplication(
            bundleIdentifier: "com.example.editor",
            bundlePath: "/Applications/Editor.app",
            displayName: "Editor"
        )
        let running = process(
            pid: 10,
            bundleIdentifier: "com.example.editor",
            path: "/Applications/Editor.app"
        )
        let target = try #require(EnforcementPlanner().targets(
            selections: [selection],
            runningApplications: [running]
        ).first)
        let startedAt = Date(timeIntervalSince1970: 100)
        let session = EnforcementSession(
            mode: .firm,
            startedAt: startedAt,
            targets: [target]
        )
        let blocked = ResolvedSchedule(
            phase: .workClosed,
            isAvailable: false,
            activeBaseInterval: nil,
            activeOverride: nil,
            nextTransition: nil,
            nextAvailability: nil
        )

        let before = EnforcementPlanner().forceEligibleTargetIDs(
            session: session,
            at: startedAt.addingTimeInterval(
                HomewardPolicy.firmGracePeriod - 0.001
            ),
            schedule: blocked,
            currentSelections: [selection],
            currentlyRunning: [running]
        )
        let after = EnforcementPlanner().forceEligibleTargetIDs(
            session: session,
            at: startedAt.addingTimeInterval(
                HomewardPolicy.firmGracePeriod
            ),
            schedule: blocked,
            currentSelections: [selection],
            currentlyRunning: [running]
        )

        #expect(before.isEmpty)
        #expect(after == [target.id])
    }

    /// 1 - Name: Firm cancellation invariants.
    /// 2 - Description: Cancels force when paused, available, deselected, or replaced by another process generation.
    /// 3 - Assumptions: Every safety-relaxing event is reflected before force eligibility is evaluated.
    /// 4 - Expectations: Every invalidated case returns an empty eligible-target list.
    @Test
    func firmCancellationInvariants() throws {
        let selection = SelectedApplication(
            bundleIdentifier: "com.example.editor",
            bundlePath: "/Applications/Editor.app",
            displayName: "Editor"
        )
        let running = process(
            pid: 10,
            bundleIdentifier: "com.example.editor",
            path: "/Applications/Editor.app"
        )
        let target = try #require(EnforcementPlanner().targets(
            selections: [selection],
            runningApplications: [running]
        ).first)
        let startedAt = Date(timeIntervalSince1970: 100)
        var paused = EnforcementSession(
            mode: .firm,
            startedAt: startedAt,
            targets: [target]
        )
        paused.forceEscalationPaused = true
        let available = ResolvedSchedule(
            phase: .workAvailable,
            isAvailable: true,
            activeBaseInterval: nil,
            activeOverride: nil,
            nextTransition: nil,
            nextAvailability: nil
        )
        let blocked = ResolvedSchedule(
            phase: .workClosed,
            isAvailable: false,
            activeBaseInterval: nil,
            activeOverride: nil,
            nextTransition: nil,
            nextAvailability: nil
        )
        let deadline = startedAt.addingTimeInterval(
            HomewardPolicy.firmGracePeriod
        )
        let planner = EnforcementPlanner()
        let pausedResult = planner.forceEligibleTargetIDs(
            session: paused,
            at: deadline,
            schedule: blocked,
            currentSelections: [selection],
            currentlyRunning: [running]
        )
        let availableResult = planner.forceEligibleTargetIDs(
            session: EnforcementSession(
                mode: .firm,
                startedAt: startedAt,
                targets: [target]
            ),
            at: deadline,
            schedule: available,
            currentSelections: [selection],
            currentlyRunning: [running]
        )
        let deselectedResult = planner.forceEligibleTargetIDs(
            session: EnforcementSession(
                mode: .firm,
                startedAt: startedAt,
                targets: [target]
            ),
            at: deadline,
            schedule: blocked,
            currentSelections: [],
            currentlyRunning: [running]
        )
        let replacedProcessResult = planner.forceEligibleTargetIDs(
            session: EnforcementSession(
                mode: .firm,
                startedAt: startedAt,
                targets: [target]
            ),
            at: deadline,
            schedule: blocked,
            currentSelections: [selection],
            currentlyRunning: [
                RunningApplicationSnapshot(
                    processIdentifier: running.processIdentifier,
                    bundleIdentifier: running.bundleIdentifier,
                    bundlePath: running.bundlePath,
                    displayName: running.displayName,
                    launchedAt: running.launchedAt?.addingTimeInterval(1)
                ),
            ]
        )

        #expect(pausedResult.isEmpty)
        #expect(availableResult.isEmpty)
        #expect(deselectedResult.isEmpty)
        #expect(replacedProcessResult.isEmpty)
    }

    /// 1 - Name: Enforcement identity invalidation.
    /// 2 - Description: Invalidates active enforcement when schedule, blocked interval, or process generation changes.
    /// 3 - Assumptions: A PID can be reused and schedule edits can preserve the same apparent availability.
    /// 4 - Expectations: Only the exact target under the exact originating policy remains current.
    @Test
    func enforcementIdentityInvalidation() throws {
        let selection = SelectedApplication(
            bundleIdentifier: "com.example.editor",
            bundlePath: "/Applications/Editor.app",
            displayName: "Editor"
        )
        let running = process(
            pid: 10,
            bundleIdentifier: "com.example.editor",
            path: "/Applications/Editor.app"
        )
        let target = try #require(EnforcementPlanner().targets(
            selections: [selection],
            runningApplications: [running]
        ).first)
        let schedule = try WeeklySchedule.defaultWorkWeek()
        let identity = EnforcementIdentity(
            target: target,
            schedule: schedule,
            blockedIntervalID: "blocked-a"
        )
        var changedRules = schedule.rules
        changedRules[.wednesday] = .availableAllDay
        let changedSchedule = try WeeklySchedule(rules: changedRules)
        let reusedPID = RunningApplicationSnapshot(
            processIdentifier: running.processIdentifier,
            bundleIdentifier: running.bundleIdentifier,
            bundlePath: running.bundlePath,
            displayName: running.displayName,
            launchedAt: running.launchedAt?.addingTimeInterval(1)
        )
        let replacementTarget = try #require(EnforcementPlanner().targets(
            selections: [selection],
            runningApplications: [reusedPID]
        ).first)

        #expect(identity.isCurrent(
            schedule: schedule,
            blockedIntervalID: "blocked-a",
            targets: [target]
        ))
        #expect(!identity.isCurrent(
            schedule: changedSchedule,
            blockedIntervalID: "blocked-a",
            targets: [target]
        ))
        #expect(!identity.isCurrent(
            schedule: schedule,
            blockedIntervalID: "blocked-b",
            targets: [target]
        ))
        #expect(!identity.isCurrent(
            schedule: schedule,
            blockedIntervalID: "blocked-a",
            targets: [replacementTarget]
        ))
    }

    /// 1 - Name: Countdown announcement milestones.
    /// 2 - Description: Limits spoken countdown updates to 30, 15, and 5 seconds without duplicates.
    /// 3 - Assumptions: Per-second visual updates continue independently from accessibility announcements.
    /// 4 - Expectations: Milestones announce once and intermediate ticks remain silent.
    @Test
    func countdownAnnouncementMilestones() {
        let policy = CountdownAnnouncementPolicy()

        #expect(policy.shouldAnnounce(secondsRemaining: 30, announced: []))
        #expect(!policy.shouldAnnounce(secondsRemaining: 29, announced: []))
        #expect(!policy.shouldAnnounce(secondsRemaining: 15, announced: [15]))
        #expect(policy.shouldAnnounce(secondsRemaining: 5, announced: [30, 15]))
    }
}

private func process(
    pid: Int32,
    bundleIdentifier: String?,
    path: String
) -> RunningApplicationSnapshot {
    RunningApplicationSnapshot(
        processIdentifier: pid,
        bundleIdentifier: bundleIdentifier,
        bundlePath: path,
        displayName: "Fixture",
        launchedAt: Date(timeIntervalSince1970: TimeInterval(pid))
    )
}
