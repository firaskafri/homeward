# Homeward Threshold Accessibility Contract

Homeward targets native macOS accessibility conventions and WCAG 2.2 Level A
and AA where a web success criterion meaningfully maps to a macOS app. WCAG is
not itself a native-app certification standard. Passing automated checks or
meeting this written contract does not establish conformance.

This document defines required behavior and manual evidence. Current
implementation status is tracked in `TRACEABILITY.md`.

## Required behavior

### Perceivable state and content

- Every state, attention item, validation result, progress state, and action
  consequence is available in text. Color and symbols may reinforce meaning
  but never carry it alone.
- Text and essential icons meet at least 4.5:1 normal-text, 3:1 large-text, and
  3:1 non-text contrast where the WCAG measures apply. Disabled native controls
  may use platform conventions, but the reason they are unavailable remains
  readable.
- System text styles and semantic colors respond to light/dark appearance,
  Increase Contrast, and Differentiate Without Color.
- Reduce Transparency replaces translucent material behind meaningful content
  with an opaque semantic background.
- Content reflows without clipping at the largest supported macOS text setting
  and with 2× pseudo-localized strings. Horizontal scrolling must not be
  required for primary state, consequences, or actions.
- At Zoom 200% and 400%, the user can reach every control and read all
  consequences without content being hidden behind a fixed panel.
- App icons are decorative when the adjacent app name provides the same
  information. Missing icons do not remove the app name or state.
- Countdown values use tabular digits visually and a stable accessible label.

Applicable WCAG references: 1.1.1, 1.3.1, 1.3.2, 1.4.1, 1.4.3, 1.4.10,
1.4.11, and 1.4.12.

### Keyboard and control access

- Every function is available with ordinary keyboard navigation and Full
  Keyboard Access. There are no keyboard traps.
- Dragging an application always has a visible **Choose Application…**
  alternative.
- Pointer target size follows standard native control sizing and spacing. Any
  custom target must meet the WCAG 2.2 24-by-24 CSS-pixel-equivalent minimum
  where that metric maps to macOS, or satisfy the spacing exception.
- Escape performs the visible cancel/dismiss action. It never silently changes
  schedule or availability. In an armed Firm panel, Escape first stops force
  escalation, as the visible button label states.
- Return activates a default action only when its consequence is clear and the
  action is enabled. `⌘S`, `⌘Return`, and `⌘Z` are contextual and must not
  conflict with text entry or system commands.
- A disabled action exposes its blocker in adjacent text and through its
  accessibility help/description. Users are not expected to discover a
  requirement by testing a disabled control.
- Visible labels begin the accessible name so Voice Control commands match
  what the user sees. Icon-only buttons require concise unique names.
- Controls with changing state expose name, role, value, and enabled state.

Applicable WCAG references: 2.1.1, 2.1.2, 2.1.4, 2.5.3, 2.5.8, and 4.1.2.

### Focus and presentation

The focus modes in `UI-STATE-MATRIX.md` are required:

- **Passive:** warning transitions, blocked-launch feedback, and automatic
  Saved Thoughts availability do not activate Homeward or take focus from the
  current app, including an open save dialog.
- **Invoked:** a user-opened window or panel becomes key and focuses its
  heading, first invalid control, or first meaningful action. Closing it
  restores the invoking control or prior application where AppKit permits.
- **Safety:** a Firm countdown may activate Homeward so Stop Force Quit remains
  visible. Initial focus goes to Stop Force Quit, not the countdown. The timer
  never moves focus. Dismissal restores the prior app/control.

Focus order follows visual and task order. Focus is visibly distinguishable in
all appearances, is not obscured by overlays or floating panels, and remains
stable when list rows update. Opening Change Today Only from an armed Firm
panel stops force escalation before moving focus.

Applicable WCAG references: 2.4.3, 2.4.6, 2.4.7, 2.4.11, 3.2.1, and 3.2.2.

### Announcements and timing

- State transitions and successful saves use a polite announcement only when
  the information is not otherwise conveyed by the focused control.
- Errors that affect safety or persistence use one high-priority announcement.
  Repeated reconciliation must not repeat the same message.
- Firm countdowns announce 30, 15, and 5 seconds once per process session.
  They do not announce every tick.
- When several Firm countdowns share a deadline, aggregate announcements when
  that is clearer than overlapping app-by-app speech.
- Stop Force Quit remains keyboard- and VoiceOver-operable throughout every
  active countdown. Stopping or hiding replaces the countdown with an
  announced paused state.
- Preview timeouts and the ten-minute Gentle extension are stated before they
  start. The user can end preview or stop force escalation without precision
  timing.
- Progress indicators expose a label. Saving and loading completion are
  announced without moving focus.

Applicable WCAG references: 2.2.1, 2.2.2, and 4.1.3.

### Errors, confirmations, and recovery

- Validation identifies the invalid field, explains how to fix it, preserves
  the draft, and moves focus to that field or a linked error summary.
- Actions that can immediately close apps state the Gentle/Firm consequence
  before execution.
- Firm Close, reset, deletion, quit, and other irreversible or safety-relevant
  actions use a clear confirmation with Cancel.
- A failed save retains the previous verified policy and returns focus to the
  error or initiating control. The message states that no new policy was
  applied.
- Configuration recovery exposes Retry, Restore Previous Settings when
  available, and Reset Setup. It never presents a false schedule status.
- Notes recovery is separate and does not reset configuration.

Applicable WCAG references: 3.3.1, 3.3.2, 3.3.3, and 3.3.4.

### Privacy with assistive technology

- Default notifications expose no selected-app names, app paths, developer
  names, thought text, or draft text.
- Automatic thought availability announces only a generic title and count.
  Thought text enters the accessibility tree only after the user deliberately
  opens Saved Thoughts.
- While the user session is locked or inactive, Homeward does not present or
  announce thought content.
- Sensitive content is not duplicated in accessibility labels, help text,
  window titles, notification actions, or unified logging.

## Surface-specific focus contract

| Surface | Initial focus | Dismissal/return |
| --- | --- | --- |
| Onboarding step | Step heading, then first incomplete control | Preserve step and return to invoking app when window closes |
| Today/Settings route | Destination heading; attention routes may focus the issue | Return to sidebar item or prior app |
| Validation failure | First invalid control or linked error summary | Preserve draft |
| App chooser | Native chooser focus | Return to Choose Application/Reselect |
| Preview | App picker, then Run Preview | Return to Ready; never launch an app |
| Blocked-launch feedback | No focus; Passive | Current app keeps focus |
| Automatic thoughts-ready feedback | No focus; Passive | Current app keeps focus |
| Saved Thoughts review | Heading, then first note action | Return to invoking menu/window control |
| Note capture | Editor | Return to invoking control; preserve draft after failure |
| Gentle attention | Passive unless user opens details | Restore prior app; Show App intentionally activates target |
| Firm countdown | Stop Force Quit | Restore prior app/control |
| Recovery | Recovery heading, then Retry | Continue to setup or routed main window |

## Localization

- All user-facing UI, error, and notification strings must be externalized
  before release.
- Dates, times, weekdays, lists, and plurals use locale-aware formatters.
- Do not concatenate sentence fragments around app names or counts.
- Test right-to-left layout, long app names, missing developer names, and 2×
  pseudo-localized strings.
- Accessible names remain meaningful when visual labels truncate.

## Automated evidence required

- Stable identifiers cover onboarding roots and steps, app rows, schedule
  controls, state output, readiness issues, note controls, closing rows,
  countdown safety actions, recovery actions, and route destinations.
- Unit tests cover state precedence, exact status/copy selection, disabled
  reasons, countdown milestones, process scope, fail-open unresolved apps, and
  privacy-safe notification/automatic-thought output.
- UI tests cover keyboard traversal, default/cancel actions, focus entry and
  restoration where observable, no focus movement during countdown updates,
  minimum window size, long strings, and the pre-activation menu-bar item.
- Accessibility-tree snapshots or assertions verify names, roles, values,
  descriptions, enabled states, and hidden decorative imagery.

Automation must not claim VoiceOver, Voice Control, Switch Control, Zoom,
contrast, multi-display, or save-dialog conformance.

## Manual release gate

Record OS and Xcode versions, hardware/display arrangement, appearance and
assistive settings, tested flow, result, and defects. Complete onboarding,
menu, Today, Schedule, Work Apps, Closing, Saved Thoughts, Settings, recovery,
Gentle/Firm closing, blocked launch, and today-only changes with:

- VoiceOver
- Full Keyboard Access
- Voice Control
- Switch Control
- Zoom at 200% and 400%
- Light and dark appearance
- Increase Contrast
- Differentiate Without Color
- Reduce Motion
- Reduce Transparency
- Largest supported text setting
- Keyboard-only use with a representative third-party save dialog
- Screen lock/session inactivity, Spaces, full-screen apps, and multiple
  displays

No unresolved keyboard, focus, name, role, value, announcement, contrast,
clipping, timing, privacy, or target-size barrier may remain before dogfood
approval.
