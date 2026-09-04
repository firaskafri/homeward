# Homeward Threshold UX Specification

This document is the normative product and interaction contract for the
Homeward Threshold direction. It describes required behavior, including work
that is not implemented yet. `TRACEABILITY.md` is the sole source for current
implementation status.

The words **must**, **should**, and **may** describe requirements.

## Product promise

Homeward is a calm native macOS utility that closes selected work applications
outside user-defined work windows. It helps a person honor a boundary; it is
not a security boundary and does not promise to prevent an application from
starting.

Homeward must not add accounts, analytics, cloud sync, content inspection,
scores, streaks, punitive language, or surveillance. It manages GUI
application processes only. It must not imply that it can protect files,
browser activity, terminal commands, AI conversations, or access to work.

## Safety and privacy invariants

These requirements override visual or convenience goals:

1. Homeward must not close applications until onboarding is completed.
2. If saved configuration cannot be verified, closing must pause and recovery
   must say so before presenting any schedule-derived status.
3. An unresolved app selection must fail open: Homeward must not request a
   normal or forced quit for that selection until the user repairs it.
4. Firm Close must request a normal quit first, provide a complete 30-second
   grace period for each process session, and keep Stop Force Quit available.
5. Force escalation must pause when its safety controls are not visible or the
   user session is inactive. Resuming must start a new complete grace period.
6. Hiding or closing an armed Firm panel and opening Change Today Only from
   that panel must stop force escalation before the panel disappears.
7. Homeward must never launch a selected app. Preview may activate an
   already-running app only after the user chooses Show App.
8. Notification text must be generic by default: no selected-app names, note
   text, or other content that reveals the user's work.
9. Automatically resurfaced thoughts must conceal their text until the user
   deliberately opens the review. No thought text may appear while the session
   is locked or inactive.
10. A save failure must leave the previously verified policy in effect and
    explain what was not applied.

## Shared state model

Today, the menu bar, panels, notifications, and accessibility output must be
derived from one status model. When more than one condition applies, use this
precedence:

1. Configuration recovery
2. Starting or delayed startup
3. Onboarding
4. Active closing, Firm countdown, force paused, or force failed
5. Work extended
6. Winding down
7. Work available or work closed

Readiness issues such as notifications being off, Start at Login requiring
approval, zero selected apps, or unresolved apps are attention items. They do
not replace the schedule state, except that configuration recovery replaces
all schedule-derived copy because enforcement is paused.

Every primary status presentation must answer:

- What is Homeward doing now?
- What is the next meaningful transition, including a localized date and time
  when one exists?
- Which weekly rule or today-only change governs the state?
- What single action is most useful now?
- Is closing active, paused, or degraded?

State titles, exact actions, announcements, and recovery behavior are defined
in `UI-STATE-MATRIX.md`. Approved strings are defined in `COPY.md`.

## Information architecture

### Menu bar

The menu-bar item is the persistent entry point while Homeward runs. Its label
must expose the semantic state to accessibility APIs. Showing the next
transition time is an optional presentation preference.

The compact menu must contain, in order:

- Current state and next transition
- Active today-only change or closing status
- One contextual primary action
- Saved Thoughts count when thoughts are available to review
- Needs Attention when a repair or system setting is required
- Open Homeward, Settings, and Quit

Recovery and setup replace the normal menu with one route to the required task
plus Quit.

### Main window

The Threshold information architecture is:

- **Today:** state, next transition, primary action, active override, selected
  apps, closing progress, and readiness issues
- **Schedule:** weekly availability and save consequences
- **Work Apps:** selected apps, discovery, search, repair, and browser scope
- **Closing:** Gentle/Firm behavior, warnings, extension, and preview
- **Saved Thoughts:** persistent review and recovery destination
- **Settings:** startup, notifications, menu-bar presentation, privacy,
  reset, version, support, and update guidance

Open Homeward, Settings, Needs Attention, Saved Thoughts, and notification
actions must route to their named destination. Reopening from Finder or
Spotlight must bring the existing window forward, including when the menu-bar
item is hidden.

## Interaction contract

### Actions and consequences

- Each surface must have one visually obvious primary action.
- An action that opens choices or confirmation uses an ellipsis. An action
  that executes immediately does not.
- Before a schedule, app-selection, or today-only change can immediately close
  apps, confirmation must name that consequence and the configured Gentle or
  Firm flow.
- Destructive reset actions must identify retained and deleted data.
- A pending save disables duplicate submission, preserves the draft, and
  exposes a progress state without changing focus.
- Success is shown near the initiating control. Failure remains visible until
  dismissed or superseded and returns focus to the failed control or error
  summary.
- Escape and the red close button dismiss without changing policy, except that
  dismissing an armed Firm panel must first stop force escalation.
- Quit must explain that pending force quits are cancelled, apps already asked
  to quit may still close, and monitoring stops until Homeward reopens.
- Drag-and-drop must always have a visible Choose Application alternative.

### Focus and presentation

- Passive informational UI must not activate Homeward or take focus from the
  current app, including a save dialog.
- User-invoked windows and panels must become key, focus their heading or first
  meaningful control, and restore the previous app/control on dismissal where
  AppKit permits.
- A Firm countdown may activate Homeward to expose safety controls. It must
  initially focus Stop Force Quit, never move focus as the timer changes, and
  restore the prior app/control when dismissed.
- Blocked-launch feedback and automatic thought availability are passive.
  Their actions must also be reachable from the menu or main window.
- Simultaneous events must use this priority: configuration recovery, Firm
  safety, save/error recovery, blocked-launch feedback, thought availability,
  informational status. Lower-priority events wait or aggregate; they must not
  cover a higher-priority safety control.
- Repeated blocked launches and multiple process instances must be aggregated
  or explicitly identified. Action scope must say whether it affects one
  process, one selected app, or all selected apps.

### Notifications

- Notifications are optional. Closing continues when authorization is denied
  or unavailable.
- Default warning, blocked-launch, and completion notifications must use
  generic titles and bodies from `COPY.md`.
- Notification actions that alter availability or start closing must be bound
  to the schedule/configuration generation that created the notification.
  Stale actions must do nothing and open Today with a calm explanation.
- Notification content and actions must be removed or replaced after reset,
  schedule changes, authorization changes, or app quit.
- Optional detailed notification content may be added only behind an explicit,
  off-by-default preference. The preference must explain lock-screen exposure.
- No notification may contain saved-thought text.

## Onboarding and preview

Onboarding is resumable and must not enable closing before the final confirmed
action. Completion requires:

- a valid, explicitly confirmed schedule; and
- at least one resolvable selected app that Homeward is allowed to manage.

Start at Login and notifications are recommended readiness steps, not blockers.
The Ready step must summarize the saved schedule, selected apps, closing mode,
and any immediate-close consequence.

Preview is optional and non-destructive:

- The Ready step must provide **Run Preview…** and an explicit
  **Skip Preview** action.
- Skip Preview records an intentional choice for the current onboarding
  completion; it does not disable future preview.
- Preview must state that it requests normal quits only and may close unsaved
  work if the selected app accepts the quit.
- It operates on one explicitly selected, already-running app.
- Each waiting stage has a 60-second timeout, Cancel/End Preview, and a recovery
  instruction.
- A normal quit already accepted by an app cannot be undone. Cancelling only
  prevents subsequent preview steps.
- Preview completion is never required to start Homeward.

## Work Apps

- Show selected apps before catalog results.
- Provide search, drag-and-drop, and Choose Application.
- Disambiguate duplicate names with developer or path information.
- Explain that selecting a browser manages every profile and window.
- Zero apps is a blocking setup state and an attention state after setup.
- An unresolved app remains visible as **Needs reselection**, contributes to
  the attention count, and is excluded from all closing plans until repaired.
- Reselect replaces the saved identity only after validation succeeds. Remove
  stops future management of that selection.
- Adding or repairing an app during blocked time requires confirmation before
  applying the current closing flow.

## Closing behavior

### Gentle Close

Homeward requests a normal quit and never force-quits. If the app remains
open, the user can Show App or Leave Open This Time. Leave Open applies only to
that process session; a later launch remains eligible for closing. The
optional one-time ten-minute extension applies to all selected apps for the
current blocked interval.

### Firm Close

Homeward requests a normal quit, displays a per-process 30-second countdown,
then may force-quit only the same still-running process session. Unsaved
changes can be lost. Stop Force Quit pauses force for all selected apps in the
current blocked interval without making work available. Resume Firm Closing
requires confirmation and a new complete grace period.

Force failure leaves the app open, keeps a visible explanation and Show App
action, and never retries force in a hidden loop.

## Saved Thoughts

- Thought text is local plain text, limited to 500 characters.
- Capture is user-invoked, opens a focused editor, and preserves the draft
  after a save failure.
- Existing thought content stays concealed while work is closed.
- When a normal work window next becomes available, automatic presentation
  says only that saved thoughts are ready. The user must choose Review Saved
  Thoughts before text appears.
- Keep defers a thought for the current interval. Mark Done removes it only
  with a user-controlled restoration path. Delete requires confirmation.
- Storage failure must distinguish unavailable reading from failed mutation.
  Configuration recovery must never reset notes. Notes recovery must never
  reset configuration.

## Recovery and readiness

Configuration recovery must show **App closing is paused** and offer Retry,
Restore Previous Settings, and Reset Setup. Reset Setup must preserve saved
thoughts. No schedule status or closing action is valid until recovery
succeeds.

Notes recovery must say **Saved thoughts are unavailable** while confirming
that app closing still works. It must offer Retry and an explicit reset; a
validated backup restore may be offered only when a recovery candidate exists.

Notification and Start at Login problems are nonblocking attention states.
Their copy must explain the consequence and route to the relevant system
setting. Zero apps and unresolved apps are product-readiness issues and must
route to Work Apps.

## Visual language and window behavior

- Use native SwiftUI/AppKit controls, semantic colors, system typography, SF
  Symbols, and a consistent four-point spacing rhythm.
- Use tabular digits for times and countdowns.
- Avoid decorative progress, gradients, gamification, punishment imagery, and
  continuous idle/countdown animation.
- State must never depend on color alone.
- Motion must be brief, interruptible, and replaced under Reduce Motion.
- Onboarding and the main window are resizable. At minimum size, current state,
  next transition, and primary action remain visible without scrolling.
- Utility panels remain inside the visible display frame. Firm safety remains
  reachable from the menu if its panel is hidden.
- Placement and focus require manual checks across Spaces, full-screen apps,
  menu-bar crowding/notches, and multiple displays.

Accessibility requirements and evidence boundaries are defined in
`ACCESSIBILITY.md`.

## Acceptance boundary

This contract is complete only when every visible state maps to a core or
app-model source, every policy-changing action maps to one model intent, and
every row in `UI-STATE-MATRIX.md` has evidence. A successful compile or
unreviewed screenshot does not establish conformance, accessibility, or
release readiness.
