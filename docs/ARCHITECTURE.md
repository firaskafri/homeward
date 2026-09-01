# Homeward Architecture

Homeward separates deterministic policy from macOS side effects.

## HomewardCore

`HomewardCore` imports Foundation only. It owns:

- Weekly schedules and explicit same-day/overnight rules.
- Derived availability, wind-down, and next-transition calculations.
- Today-only overrides.
- Selected-application and running-process identity snapshots.
- Gentle/Firm enforcement planning.
- Versioned configuration, notes, and atomic file storage.

Current state is derived from policy, overrides, the supplied calendar/time
zone, and the current instant. Timers are never authoritative.

## Homeward application

The app target owns:

- `NSWorkspace` lifecycle observation.
- Retained `NSRunningApplication` handles and termination requests.
- `SMAppService.mainApp` state.
- User notifications.
- App discovery and explicit `.app` selection.
- Menu-bar, onboarding, management, closing, and note interfaces.

AppKit objects remain on the main actor. Only immutable, Sendable snapshots
enter `HomewardCore`.

## Enforcement invariants

- Configuration must be valid and onboarding complete.
- The current schedule must be blocked.
- The process must match a current selection and have a stable process-session
  identity.
- Gentle Close never calls force termination.
- Firm Close requests normal quit first and waits a complete 30 seconds.
- Force is cancelled when policy, selection, process identity, session
  activity, or countdown visibility becomes unsafe.
- Stop Force Quit pauses force for the blocked interval without granting app
  availability.
- API return values are request results; process exit is confirmed separately.

## Persistence

Configuration and notes are separate versioned Codable files in
`~/Library/Application Support/Homeward`. Writes use atomic replacement and
owner-only permissions. A previous validated file is retained only as an
explicit recovery candidate; corrupt active configuration never silently
falls back into enforcement.
