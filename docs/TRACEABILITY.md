# Homeward Threshold Requirement Traceability

This document maps the Threshold product contract to the current source and
evidence boundary. `UX-SPEC.md`, `UI-STATE-MATRIX.md`, `COPY.md`, and
`ACCESSIBILITY.md` are normative requirements. `DECISIONS.md` records the MVP
baseline.

Status meanings:

- **Implemented:** corresponding source behavior is present.
- **Partial:** part of the requirement exists, but the contract is not met.
- **Pending:** no conforming implementation was found.
- **Manual evidence:** source may exist, but the behavior cannot be accepted
  without platform or assistive-technology testing.

Statuses reflect source inspection of the current working tree during the
September 2026 Phase 2 review. Listed tests identify automated evidence;
platform and manual evidence remain separate release gates.

Version 0.1.0 is English-only and uses generic notifications. Detailed
notifications, Saved Thoughts system notifications, automatic updates,
localization, and a permanent notes archive are deferred and are not baseline
release requirements.

## Product, state, and navigation

| ID | Requirement | Source or evidence | Status |
| --- | --- | --- | --- |
| PRD-001 | Calm native macOS utility; no accounts, analytics, cloud sync, inspection, gamification, or security-boundary claim | `README.md`, `DECISIONS.md`, native SwiftUI/AppKit views | Implemented product boundary; visual Threshold redesign pending |
| STA-001 | Startup shows no schedule-derived state until configuration is verified | `RootView.swift`, `HomewardApp.swift`, `AppModel.start()` | Implemented in source: the window and menu-bar accessibility value gate schedule state on readiness |
| STA-002 | Delayed startup has explicit non-enforcement copy and Retry | Required by `UI-STATE-MATRIX.md` | Pending |
| STA-003 | Configuration failure supersedes schedule state and pauses closing | `AppModel.start()`, `RootView.swift`, recovery app-model tests | Partial: recovery and warning cleanup are implemented in source; automated stale-notification cleanup evidence is still missing |
| NAV-001 | Menu is the persistent compact status surface | `HomewardApp.swift` | Implemented baseline |
| NAV-002 | Main destinations are Today, Schedule, Work Apps, Closing, Saved Thoughts, and Settings | `HomewardRoute`, `ManagementView.swift`, native Settings scene | Implemented |
| NAV-003 | Open, Settings, Needs Attention, Saved Thoughts, and notification actions route truthfully | `HomewardApp.swift`, `ManagementView.swift`, `PresentationCoordinator.swift` | Partial: Open, Settings/Needs Attention, and the Saved Thoughts destination route correctly; notification actions apply contextual behavior but do not route stale actions to Today with an explanation |
| NAV-004 | Finder/Spotlight reopen and hidden-status-item fallback bring the existing window forward | `HomewardApplicationDelegate.applicationShouldHandleReopen`, `HomewardUITests.testCompletedSetupReopensToday()` | Implemented source and automated UI coverage; unlocked-session execution remains required |
| STA-004 | One shared presentation model drives Today, menu, notifications, and accessibility output | `SchedulePresentation`, `HomewardApp.swift`, `OverviewView.swift`, `HomewardNotificationService.swift` | Partial: schedule formatting is shared, event/privacy presentation is not |

## Onboarding and preview

| ID | Requirement | Source or evidence | Status |
| --- | --- | --- | --- |
| ONB-001 | Setup is resumable and closing stays off until final completion | `OnboardingView.swift`, `AppModel.reconcile()` | Implemented |
| ONB-002 | Completion requires a confirmed schedule and one resolvable app that Homeward is allowed to manage | `AppModel.completeOnboarding()`, `AppModelTests.onboardingRejectsOnlyUnresolvedApplications()` | Implemented |
| ONB-003 | Notifications and Start at Login are recommended, nonblocking readiness steps | `OnboardingView.swift` | Implemented |
| ONB-004 | Disabled progression explains its blocker visibly and programmatically | `OnboardingView.swift`, accessibility UI tests | Partial |
| PRE-001 | Preview is optional and offers explicit Run Preview and Skip Preview choices | `OnboardingView.swift` | Partial: preview is optional in practice, but explicit Skip Preview is missing |
| PRE-002 | Preview operates on one chosen, already-running app and never launches or force-quits it | `AppModel.startPreview()`, `PreviewView` | Implemented |
| PRE-003 | Preview cancellation states that an accepted normal quit is irreversible | `PreviewView` | Pending copy |
| PRE-004 | Preview covers first exit, relaunch, second exit, completion, attention, timeout, and cancellation | `AppModel.PreviewState`, `PreviewView`, preview tests | Implemented baseline; reason-specific recovery remains partial |

## Schedule and today-only changes

| ID | Requirement | Source or evidence | Status |
| --- | --- | --- | --- |
| SCH-001 | Seven-day schedule supports scheduled, available-all-day, blocked-all-day, and validated overnight windows | `Models.swift`, `ScheduleResolver.swift`, `ScheduleEditorView.swift`, `ScheduleResolverTests.swift`, `ModelTests.swift` | Implemented |
| SCH-002 | Rules follow the Mac's current wall clock, locale, and time zone | `ScheduleResolver.swift`, `WorkspaceMonitor.swift` | Implemented source; manual clock/time-zone evidence required |
| SCH-003 | Available, winding down, closed, extended, next transition, and no-future-window states are deterministic | `ScheduleResolver.swift`, `PresentationFormatting.swift`, schedule tests | Implemented baseline |
| SCH-004 | Draft, validation, saving, success, failure, and stale-policy conflict states follow the matrix | `ScheduleEditorView.swift`, `AppModel.commit()` | Partial |
| SCH-005 | A change that makes the current time unavailable confirms the exact Gentle/Firm consequence | `ScheduleEditorView.swift`, `OverviewView.swift`, `HomewardApp.swift` | Partial: confirmation exists but says configured closing flow |
| SCH-006 | Today-only overrides are bounded and Return to Weekly Schedule explains immediate closing when applicable | `Models.swift`, `ScheduleResolver.swift`, `AppModel.swift` | Partial: override logic exists; consequence confirmation is incomplete |

## Application selection and fail-open behavior

| ID | Requirement | Source or evidence | Status |
| --- | --- | --- | --- |
| APP-001 | Search, catalog loading/empty states, drag-and-drop, and Choose Application are available | `ApplicationCatalog.swift`, `AppPickerView.swift` | Implemented baseline |
| APP-002 | System and unsupported apps are rejected | `Models.swift`, `ApplicationCatalog.swift`, `AppModel.addApplication()` | Implemented |
| APP-003 | Browser selection explains whole-browser scope | `AppPickerView.swift` | Implemented |
| APP-004 | Adding or repairing an app during blocked time confirms immediate closing | `AppPickerView.swift` | Implemented baseline |
| APP-005 | Zero apps blocks onboarding and becomes a post-setup attention state | `OnboardingView.swift`, `AppPickerView.swift` | Partial: setup blocking exists; post-setup attention is pending |
| APP-006 | Unresolved apps remain visible and repairable | `SelectedApplication.isResolvable`, `AppModel.refreshCatalog()`, `AppPickerView.swift` | Implemented |
| APP-007 | Unresolved apps fail open and are excluded from all normal/force closing plans | `AppModel.activateRuntime()`, `EnforcementPlanner.targets()`, `forceEligibleTargetIDs()`, startup/planner tests | Implemented |
| APP-008 | Duplicate names and multiple instances are visibly disambiguated with explicit action scope | `ApplicationCatalog.swift`, `ClosingPanel.swift` | Partial |

## Gentle, Firm, and blocked-launch behavior

| ID | Requirement | Source or evidence | Status |
| --- | --- | --- | --- |
| GNT-001 | Gentle requests normal quit and never force-quits | `AppModel.beginEnforcement()`, enforcement/fixture tests | Implemented |
| GNT-002 | Needs-attention offers Show App and per-process Leave Open This Time | `ClosingPanel.swift`, `AppModel.leaveOpen()` | Implemented |
| GNT-003 | Optional one-time ten-minute extension affects all selected apps for the blocked interval | `AppModel.useGentleShortcutExtension()`, core model tests | Implemented baseline |
| FRM-001 | Firm requests normal quit and gives each process a complete 30-second grace | `AppModel.beginEnforcement()`, `Enforcement.swift`, full-grace tests | Implemented source |
| FRM-002 | Stop Force Quit is always available and pauses all force for the current blocked interval without granting availability | `ClosingPanel.swift`, `AppModel.stopForceQuit()` | Implemented source; manual safety evidence required |
| FRM-003 | Hidden/occluded or inactive-session safety UI prevents force | `ClosingPanel.swift`, `AppModel.attemptForceTermination()`, `WorkspaceMonitor.swift` | Implemented source; lock/Spaces/display evidence required |
| FRM-004 | Resume requests normal quit and starts a new full grace period | `AppModel.resumeFirmClosing()`, `HomewardApp.swift` | Implemented source |
| FRM-005 | Countdown announces 30, 15, and 5 once without moving focus | `CountdownAnnouncementPolicy`, `AppModel.announceCountdownIfNeeded()` | Partial: milestones exist; focus stability needs UI/manual evidence |
| FRM-006 | Firm panel initially focuses Stop and restores previous app/control | `ClosingPanel.swift` | Partial: restoration exists for some paths; initial Stop focus and normal automatic activation are not guaranteed |
| FRM-007 | Force failure stays visible, does not retry invisibly, and offers Show App | `AppModel.attemptForceTermination()`, `ClosingPanel.swift` | Implemented baseline |
| BLK-001 | Relaunched selected processes are closed according to current schedule and mode | `WorkspaceMonitor.swift`, `AppModel.handleLaunchSnapshot()`, fixture/process tests | Implemented baseline |
| BLK-002 | Blocked-launch feedback is passive, deduplicated/aggregated, and privacy-safe by default | `BlockedLaunchPanel.swift`, `AppModel.showBlockedLaunchFeedback()` | Partial: passive and cooldown behavior exist; app name is exposed |
| BLK-003 | Process identity prevents a deadline or termination event from transferring to a relaunch/PID reuse | `ProcessSessionID`, `EnforcementPlanner.forceEligibleTargetIDs()`, `AppModel.terminationMatches()`, identity tests | Implemented source; fixture evidence remains required |

## Notifications and privacy

| ID | Requirement | Source or evidence | Status |
| --- | --- | --- | --- |
| NOT-001 | Notifications are optional and closing works without authorization | `HomewardNotificationService.swift`, `AppModel.scheduleWarningsIfPossible()` | Implemented |
| NOT-002 | Version 0.1.0 warning, blocked-launch, and completion notifications are generic | `HomewardNotificationService.swift`, `AppModel.showBlockedLaunchFeedback()`, warning-copy tests | Implemented for current notification paths |
| NOT-003 | No notification contains saved-thought or draft text | Notification source and tests | Implemented in current notification paths; future thoughts notification must preserve this |
| NOT-004 | Detailed notifications are outside the version 0.1.0 baseline | `DECISIONS.md`, `UX-SPEC.md` | Deferred after version 0.1.0; no detailed-content preference is implemented or implied |
| NOT-005 | Actions are bound to the schedule/configuration generation that created them; stale actions do nothing safely | `WarningActionContext`, `NotificationResponseRouter`, `AppModel.applyNotificationAction()`, notification-context tests | Partial: warning actions carry a validated cutoff and stale or malformed contexts do nothing; full configuration-generation binding and stale-action explanation remain pending |
| NOT-006 | Pending/delivered actions are cleaned up after reset, schedule changes, authorization changes, recovery, and quit | `replaceWarnings()`, `removeWarnings()`, `AppModel.resetSetup()`, `AppModel.prepareForTermination()`, warning lifecycle tests | Implemented in source; automated coverage exists for replacement, authorization loss, and in-flight shutdown, while platform delivery behavior remains manual |
| NOT-007 | Saved Thoughts system notifications are outside the version 0.1.0 baseline | `DECISIONS.md`, `UX-SPEC.md` | Deferred after version 0.1.0 |

## Saved Thoughts and storage recovery

| ID | Requirement | Source or evidence | Status |
| --- | --- | --- | --- |
| NTE-001 | Notes are local, separate from configuration, trimmed, non-empty, and limited to 500 characters | `Configuration.swift`, `AtomicFileStore.swift`, `HomewardRepository.swift`, model/store tests | Implemented |
| NTE-002 | Capture focuses the editor, prevents duplicate saves, and preserves the draft after failure | `NotesViews.swift`, `AppModel.saveNote()` | Implemented baseline; explicit Saving/success copy is pending |
| NTE-003 | Automatic resurfacing is generic and conceals text until deliberate review | `AppModel.presentNotesIfNeeded()`, `NotesPanelController`, `NotesReviewView` | Pending: current automatic panel renders note text |
| NTE-004 | Thought content is suppressed while the session is locked or inactive | `WorkspaceMonitor.swift`, note presentation path | Pending |
| NTE-005 | Keep defers by interval and Mark Done offers Restore until review dismissal or explicit confirmation | `TomorrowNote.lastPresentedIntervalID`, `NotesReviewView` | Partial: Keep exists; Mark Done currently uses a ten-second undo |
| NTE-006 | Delete is confirmed and irreversible copy is explicit | `NotesReviewView` | Partial: confirmation exists; exact irreversible copy is pending |
| NTE-007 | Notes load/mutation recovery is separate from configuration recovery | `HomewardRepository.swift`, `AppModel.start()`, `GeneralSettingsView.swift` | Partial: storage is separate; dedicated Retry/Restore notes recovery is pending |
| NTE-008 | A permanent notes archive is outside the version 0.1.0 baseline | `DECISIONS.md`, `UX-SPEC.md` | Deferred after version 0.1.0 |
| REC-001 | Configuration recovery offers Retry, validated backup restore, and explicit reset while preserving notes | `RootView.swift`, `HomewardRepository.swift`, `AppModel` recovery methods | Implemented baseline |
| REC-002 | Startup storage initialization failure is presented recoverably rather than terminating | `HomewardRepository`, `AppModel.start()`, `AppModelTests.unavailableStorageEntersRecovery()` | Implemented |

## Focus, accessibility, visual, and localization

| ID | Requirement | Source or evidence | Status |
| --- | --- | --- | --- |
| FCS-001 | Passive event surfaces do not activate or steal focus | `BlockedLaunchPanel.swift`, `NotesPanelController`, `PresentationCoordinator.swift` | Implemented baseline; save-dialog manual evidence required |
| FCS-002 | User-invoked surfaces become key and restore invoking focus | Panel controllers | Partial |
| FCS-003 | Event priority prevents lower-priority panels from covering recovery or Firm safety | `PresentationCoordinator.swift`, closing-panel priority test | Partial: Firm closing suppresses lower-priority blocked-launch, capture, and review panels; a complete queue and recovery priority remain pending |
| A11Y-001 | All functions are keyboard-operable with visible, unobscured focus and no traps | View source, UI tests, `ACCESSIBILITY.md` manual gate | Partial/manual evidence |
| A11Y-002 | Labels, roles, values, errors, disabled reasons, and status announcements are programmatically available | Accessibility modifiers, `lastError` announcement, UI tests | Partial |
| A11Y-003 | State and action meaning never depend on color alone | SwiftUI views and visual review | Partial/manual evidence |
| A11Y-004 | WCAG 2.2 A/AA contrast, reflow, target size, timing, and error requirements apply where meaningful | `ACCESSIBILITY.md` | Manual evidence; no conformance claim |
| VIS-001 | Native semantic design works in light/dark, increased contrast, reduced motion/transparency, long text, and minimum size | Current SwiftUI views; prototype and screenshot evidence required | Partial/manual evidence |
| LOC-001 | Localization is outside the version 0.1.0 English-only baseline | `DECISIONS.md`, `ACCESSIBILITY.md`, Foundation date formatting | Deferred after version 0.1.0; locale-aware date/time formatting exists, but full string externalization, translated plurals/lists, RTL, and pseudo-localization are not claimed |

## Reliability and release evidence

| ID | Requirement | Source or evidence | Status |
| --- | --- | --- | --- |
| REL-001 | Time-zone, clock, day, wake, and session changes trigger reconciliation | `WorkspaceMonitor.swift`, `AppModel.swift` | Implemented source; device evidence required |
| REL-002 | Configuration and notes saves are validated and atomic | `AtomicFileStore.swift`, `HomewardRepository.swift`, store tests | Implemented source |
| REL-003 | Failed policy saves retain the previous verified policy and explain that no new policy applied | `AppModel.commit()` | Implemented baseline |
| REL-004 | Start at Login statuses and recovery are truthful | `LoginItemService.swift`, onboarding/general settings | Implemented source; system approval/login evidence required |
| REL-005 | Quit paths share one termination policy and do not block OS shutdown | `HomewardApplicationDelegate.applicationShouldTerminate`, `AppModel.prepareForTermination()`, `AppModel.quit()` | Implemented in source; logout/shutdown execution remains a manual platform check |
| REL-006 | UI placement and lifecycle work across lock, sleep/wake, Spaces, full-screen, and multiple displays | Panel factory, workspace monitor, manual test plan | Manual evidence |
| REL-007 | Version 0.1.0 updates use manual download and replacement | `DECISIONS.md`, `DISTRIBUTION.md` | Implemented release policy; automatic updates are deferred |

## Evidence required before status promotion

Run the repository verification layers separately and record their results:

- `swift scripts/check-test-docs.swift`
- `swift test`
- `./scripts/verify.sh`
- UI automation with `RUN_UI_TESTS=1` on an unlocked signed session

Use `HomewardFixture`, never real selected work apps, for destructive lifecycle
automation. Complete the manual accessibility gate in `ACCESSIBILITY.md` and
the platform checks in `STATUS.md`.

Developer ID signing, notarization, stapling, Gatekeeper on a clean account,
seven crash-free days, and two full workweeks of behavioral dogfood remain
outside this documentation contract and are still required before public
release.
