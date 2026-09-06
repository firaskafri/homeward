# Homeward A-to-Z Release Gate

## Status and use

This document defines the release gate. Automated coverage is listed in
`TESTING.md`; current readiness and remaining manual evidence are listed in
`STATUS.md`.

Complete this gate for every public release. Evidence from an earlier version,
build, source revision, app-tree hash, or DMG cannot certify a later candidate.
Passing the gate supports a documented release decision; it is not a claim
that Homeward is 100% bug-free.

## Three non-substitutable evidence lanes

1. **Shell-hosted journeys** run production Homeward feature and view sources
   in `HomewardTestShell.app` with isolated storage and typed deterministic
   substitutes for macOS-owned services.
2. **Exact Release lifecycle** exercises the candidate Release app with normal
   multiple-instance protection and the real workspace monitor, planner,
   safety panel, and lifecycle controller. System services remain isolated,
   and destructive control is limited to the adjacent `HomewardFixture.app`.
   Its evidence identifies the source SHA and app-tree hash being exercised.
3. **Real-platform manual evidence** covers behavior that hosted automation
   cannot certify: Notification Center, Start at Login, session and power
   transitions, real application/save-dialog interaction, assistive
   technologies, display behavior, signing, notarization, Gatekeeper, and
   clean installation.

No lane substitutes for another. In particular, UI automation does not certify
VoiceOver or real Notification Center behavior, and a successful notarization
does not certify product behavior.

## Candidate identity and evidence records

Maintain two signed release records. Each record includes the release version
and build, operator, UTC time, macOS/Xcode/hardware details, checklist result,
linked logs or screenshots, unresolved defects and accepted risk, and the
coverage-contract revision used.

### Pre-package sign-off

Record the exact clean source SHA and verified Release app-tree SHA-256 from
UI-enabled verification. Sign off only after the source checks, shell-hosted
journeys, applicable exact Release lifecycle checks, manual macOS checks, and
required dogfood have passed for that candidate.

Any source, dependency, project, test, script, product, UX, or app-bundle
change invalidates this sign-off. Rebuild, recompute the app-tree hash, rerun
affected evidence, and sign again.

### Post-package sign-off

Record the final stapled DMG SHA-256 and the accepted notarization submission
ID from its retained notarytool JSON. Sign off only after signature,
notarization, stapling, Gatekeeper, quarantine, clean-account installation,
online launch, offline launch, and installed-app smoke checks use those exact
DMG bytes.

Any DMG regeneration, restapling, replacement, or byte change invalidates this
sign-off, even when the filename and version are unchanged.

## A-to-Z checklist

Use **Pass**, **Fail**, **Blocked**, or **Not applicable** for each item. A
Not-applicable result requires a written reason. Failures and blockers prevent
publication unless the release owner records an explicit, bounded risk
acceptance that does not waive a safety, privacy, signing, or accessibility
release requirement.

### A — Approve the coverage contract

- Review this checklist, `TESTING.md`, `ACCESSIBILITY.md`, `TRACEABILITY.md`,
  and the user-facing product/UX specifications.
- For every product or UX change, update the coverage contract before testing:
  changed journeys, states, copy and consequences, accessibility expectations,
  fixtures, automated assertions, and manual scenarios.
- Record why a scenario was added, changed, or removed. A release cannot rely
  on stale coverage simply because the old checks still pass.

### B — Baseline the candidate

- Choose the release version/build and a clean, pushed source revision.
- Record the source SHA, toolchain, supported macOS version, and Apple Silicon
  hardware used.
- Confirm release notes, privacy terms, license/EULA, support, update, removal,
  and data-deletion guidance are approved.

### C — Check source integrity

- Confirm local HEAD, the remote branch, and the signed annotated release tag
  resolve to the same source SHA.
- Confirm the tree is clean and no generated or untracked input can alter the
  candidate.

### D — Run shell-hosted verification

- Run
  `RUN_UI_TESTS=1 RUN_JOURNEY_E2E=1 RUN_RELEASE_E2E=1 ./scripts/verify.sh`
  from the clean revision in an unlocked signed-in macOS session.
- Preserve the complete result and exact UI-enabled verification evidence.
- Do not use `RUN_UI_TESTS=0` to certify a release.

### E — Review automated-journey limits

- Confirm destructive automation used only `HomewardFixture.app`.
- Confirm preview/UI identities cannot match installed applications.
- Treat real platform, assistive-technology, and exact Release behavior as
  still unproven until their separate evidence passes.

### F — Freeze the verified app

- Record the verification evidence's source SHA, version/build, app-tree hash,
  binary UUID, and dSYM-tree hash.
- Confirm arm64, macOS 15 minimum, menu-bar accessory configuration,
  production multiple-instance protection, and fixture exclusion.

### G — Exercise the exact Release lifecycle

- Launch only the app matching the recorded source SHA/app-tree hash.
- Require the fixture-only automated environment, normal multiple-instance
  protection, and the exact adjacent `HomewardFixture.app`.
- Cover Gentle needs-attention actions, Firm’s complete grace period, Stop
  Force Quit, and blocked relaunch process-session isolation. Hosted fixture
  tests separately prove successful normal-quit behavior.
- Do not count shell-hosted UI journeys as equivalent evidence.

### H — Verify notifications on macOS

- Test first authorization, denial, later enablement, warning delivery,
  generic privacy-safe content, actions, stale actions, cleanup after policy
  changes/reset, and behavior when authorization is unavailable.
- Confirm notifications remain optional and closing behavior continues
  without permission.

### I — Verify Start at Login

- Test the app inside and outside `/Applications`, approval-required,
  enabled, disabled, and recovery guidance states.
- Verify real logout/login and restart launch behavior and confirm the shown
  status matches macOS.

### J — Verify schedule and clock transitions

- Exercise scheduled, available-all-day, blocked-all-day, and overnight days;
  boundaries and week rollover; today-only changes and expiry; manual clock
  changes; time-zone and daylight-saving changes; sleep across a boundary;
  and wake reconciliation.

### K — Verify Gentle behavior

- With a representative running app, confirm normal quit, needs-attention,
  Show App, Leave Open This Time, the optional extension, relaunch handling,
  and save-dialog focus behavior.
- Confirm Gentle never force-quits.

### L — Verify Firm safety

- Confirm normal quit precedes the full grace period, the countdown remains
  visible, Stop Force Quit is always operable, pause/resume starts a new full
  grace period, and failure remains visible without hidden retries.
- Verify no force occurs while safety UI is hidden/occluded or the user
  session is locked/inactive.

### M — Verify blocked relaunches

- Relaunch the selected app during blocked time and verify passive,
  privacy-safe, deduplicated feedback and the configured Gentle/Firm behavior.
- Check that process identity prevents a stale deadline or PID reuse from
  targeting a new process.

### N — Verify the only permitted real-app target

- Immediately before any manual or agent-driven real-app lifecycle check,
  standardize the path and verify it is exactly `/Applications/Slack.app`;
  read its bundle identifier and verify it is exactly
  `com.tinyspeck.slackmacgap`.
- Stop if either value differs or Slack is unavailable. Do not substitute
  another app. Never select or control Cursor
  (`com.todesktop.230313mzl4w4u92`).
- Automated destructive coverage remains fixture-only; this Slack allowance
  applies only to manual or agent-driven validation.

### O — Verify session and power lifecycle

- Exercise sleep/wake, screen lock/unlock, Fast User Switching, logout,
  shutdown/restart, inactive sessions, and transitions while a warning,
  Gentle flow, Firm countdown, or Saved Thoughts state is active.

### P — Verify windows, focus, and displays

- Exercise Spaces, full-screen apps, one and multiple displays, display
  disconnect/reconnect, compact resizing, minimum window width, menu-bar
  movement, and real third-party save dialogs.
- Confirm passive surfaces do not steal focus, invoked surfaces focus and
  restore predictably, and safety UI remains reachable.

### Q — Verify keyboard and assistive technologies

- Complete onboarding, menu, Today, Schedule, Work Apps, Closing, Saved
  Thoughts, Settings, recovery, Gentle/Firm, blocked launch, and today-only
  journeys with VoiceOver, Full Keyboard Access, Voice Control, and Switch
  Control.
- Record names, roles, values, focus order/restoration, announcements,
  disabled reasons, keyboard traps, default/cancel behavior, and Stop Force
  Quit access.

### R — Verify visual accessibility

- Check light/dark appearance, Increase Contrast, Differentiate Without Color,
  Reduce Motion, Reduce Transparency, Zoom at 200% and 400%, largest supported
  macOS text, representative long English content, clipping/reflow, target
  size, and visible focus.
- Record hardware, display arrangement, and exact macOS settings.

### S — Verify storage, recovery, and privacy

- Exercise configuration and notes corruption/recovery separately, atomic
  save failure, reset, removal, and local data deletion.
- Confirm notification, accessibility, window, and unified-log output does not
  reveal saved thoughts, drafts, paths, URLs, commands, window titles, or app
  identity beyond the documented boundary.

### T — Complete safety dogfood

- Record seven crash-free days with no destructive lifecycle safety incident.
- A source/app change affecting lifecycle, persistence, timing, safety, or
  recovery restarts the applicable safety interval.

### U — Complete behavioral dogfood

- Record two full workweeks covering the configured schedule, Gentle/Firm
  behavior, relaunches, sleep/wake, normal work interruptions, notes, and
  recovery.
- Record defects and disposition; elapsed time alone is not a pass.

### V — Sign the pre-package record

- Bind approval to the exact clean source SHA and verified Release app-tree
  SHA-256.
- Confirm all required pre-package evidence is complete and no later change
  has invalidated it.

### W — Build and inspect the public artifact

- Run the public release preflight, then package with the exact identity, Team
  ID, and named notarization profile in `DISTRIBUTION.md`.
- Verify inside-out Developer ID signing, Hardened Runtime, secure timestamps,
  the empty entitlement allowlist, bundle identity, architecture/minimum OS,
  dSYM UUID, fixture exclusion, and signed read-only DMG contents.

### X — Notarize and freeze the DMG

- Require an `Accepted` notarytool result, retain its JSON and submission ID,
  staple and validate the DMG, and pass Gatekeeper assessment.
- Compute the final SHA-256 and size only after stapling. Preserve the DMG,
  checksum, provenance, dSYM zip, and notarization JSON together.

### Y — Install the exact packaged bytes

- Transfer the checksum-verified DMG through a quarantine-preserving download
  path to a clean supported-macOS account or machine.
- Verify first open through Gatekeeper, drag-install to `/Applications`,
  online launch, offline launch, version/build, menu-bar behavior, setup,
  normal quit/reopen, and a representative non-destructive smoke journey.
- Confirm the tested DMG SHA-256 and notarization submission ID match the
  frozen artifact. Do not rebuild or restaple after this evidence.

### Z — Sign off and publish

- Bind post-package approval to the final stapled DMG SHA-256 and accepted
  notarization submission ID.
- Publish those exact bytes and checksum to GitHub Releases and the
  personal-site mirror; verify both downloads reproduce the approved hash.
- Archive both sign-offs and all evidence. State known limitations and release
  risk accurately; never describe the gate as proof of a 100%-bug-free app.
