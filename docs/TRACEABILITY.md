# Homeward Requirement Traceability

The repository-visible implementation baseline is in `DECISIONS.md`; this
document maps that baseline to code and evidence. The original planning PRD is
owner-local and intentionally excluded from the repository.

## Scheduling — SCH-001 through SCH-007

- Implementation: `Models.swift`, `ScheduleResolver.swift`,
  `ScheduleEditorView.swift`, `AppModel.swift`
- Automated evidence: `ScheduleResolverTests.swift`,
  `ModelTests.swift`
- Manual evidence still required: clock/time-zone changes and sleep/wake on a
  macOS 15 device

## Application selection — APP-001 through APP-007

- Implementation: `ApplicationCatalog.swift`, `AppPickerView.swift`,
  `Enforcement.swift`
- Automated evidence: `EnforcementPlannerTests.swift`,
  `AppModelTests.swift`
- Manual evidence still required: nonstandard app locations, drag-and-drop,
  moved apps, and representative signed applications

## Wind-down — WND-001 through WND-005

- Implementation: `HomewardNotificationService.swift`, `AppModel.swift`,
  `ClosingSettingsView.swift`
- Automated evidence: schedule warning-boundary tests
- Manual evidence still required: real notification authorization, delivery,
  and actions

## Gentle Close — GNT-001 through GNT-005

- Implementation: `AppModel.swift`, `RunningApplicationController.swift`,
  `ClosingPanel.swift`
- Automated evidence: enforcement planner tests and fixture normal/refused
  termination tests
- Manual evidence still required: real save dialogs and focus restoration

## Firm Close — FRM-001 through FRM-009

- Implementation: `AppModel.swift`, `Enforcement.swift`,
  `ClosingPanel.swift`
- Automated evidence: full-grace and cancellation tests plus fixture force
  termination
- Manual evidence still required: visible countdown, session lock, Spaces,
  multiple displays, VoiceOver, and Stop Force Quit

## Blocked launch — BLK-001 through BLK-006

- Implementation: `WorkspaceMonitor.swift`, `AppModel.swift`,
  `BlockedLaunchPanel.swift`
- Automated evidence: launch-observation fixture and process-matching tests
- Manual evidence still required: launch flash, panel cadence, and extension
  interaction

## Tomorrow notes — NTE-001 through NTE-005

- Implementation: `Configuration.swift`, `AtomicFileStore.swift`,
  `NotesViews.swift`, `AppModel.swift`
- Automated evidence: note validation/order and persistence tests
- Manual evidence still required: keyboard flow, automatic next-window
  presentation, and assistive-technology review

## Reliability — REL-001 through REL-006

- Implementation: `WorkspaceMonitor.swift`, `LoginItemService.swift`,
  `HomewardRepository.swift`, `AppModel.swift`
- Automated evidence: atomic-store, startup-state, fixture lifecycle, and UI
  reachability tests
- Manual evidence still required: Start at Login approval, logout/login,
  restart, wake, and crash recovery

## Distribution and dogfood

- Automated local evidence: `scripts/verify.sh`
- Blocked: Developer ID signing, notarization, Gatekeeper on a clean account,
  seven crash-free days, and two full workweeks of behavioral dogfood
