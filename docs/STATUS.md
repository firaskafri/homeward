# Homeward Status

## Implemented and automatable

- Native macOS menu-bar app, schedule resolution, app selection, Gentle and
  Firm closing flows, today-only changes, notes, recovery, notifications, and
  Start at Login integration.
- Core, app-layer, fixture-backed lifecycle, isolated production-app UI, and
  test-shell journey suites covering first launch, completed reopen, delayed
  Retry, split recovery, installation/login readiness, product workflows, and
  representative long-content reachability.
- Static analysis, arm64 Release inspection, ad-hoc signing checks, and
  checksum/provenance packaging.
- Fail-closed Developer ID release preflight and packaging automation covering
  clean/pushed/tagged source, UI-enabled evidence, exact signing identity and
  Team ID, named Keychain notarization profile, staged inside-out signing,
  signed DMG notarization, stapling, Gatekeeper, and final provenance outputs.
- GitHub Actions runs the non-interactive automated subset on macOS 15 with
  Xcode 16.4. Local `scripts/verify.sh` includes UI automation by default.

Passing automation demonstrates deterministic logic, fixture lifecycle
behavior, build integrity, and basic UI reachability. It does not certify real
third-party app behavior, assistive-technology usability, login-item behavior,
or distributable signing.

## A-to-Z release-gate status

`RELEASE-CHECKLIST.md` defines the gate required for every public release.
Shell journeys exercise production feature and view sources with typed
deterministic platform substitutes. The exact Release lifecycle suite keeps
normal multiple-instance protection and the real workspace, planner, safety
panel, and fixture-only controller path.

Release approval requires three non-substitutable lanes: implemented
shell-hosted journeys; exact Release lifecycle evidence for the verified
source/app hash; and real-platform manual evidence. Before packaging, sign-off
is bound to the clean source SHA and verified Release app-tree SHA-256. After
packaging and clean-install validation, sign-off is bound to the final stapled
DMG SHA-256 and accepted notarization submission ID.

Passing all recorded checks supports a risk-based release decision. It does
not establish that Homeward is 100% bug-free. Any product or UX change must
update the coverage contract and rerun affected evidence before either
sign-off.

## Required before dogfood

- Real notification permission, presentation, and action checks.
- Real Start at Login approval, logout/login, and restart.
- Sleep/wake, screen lock, Fast User Switching, Spaces, and multiple-display
  checks.
- Representative third-party application and save-dialog behavior.
- VoiceOver, Voice Control, Switch Control, Full Keyboard Access, Zoom, and
  the remaining visual-setting validation documented in `ACCESSIBILITY.md`.
- Compact resizing, other long-copy surfaces, and largest supported macOS
  text-setting checks.

Manual or agent-driven real-application validation is Slack-only. Immediately
before control, verify the standardized path is
`/Applications/Slack.app` and the bundle identifier is
`com.tinyspeck.slackmacgap`; stop without substitution if either differs or
Slack is unavailable. Automated destructive lifecycle coverage remains
fixture-only, and Cursor (`com.todesktop.230313mzl4w4u92`) is never a target.

## Required before public release

- Seven-day safety and two-week behavioral dogfood gates.
- Developer ID signing, notarization, stapling, Gatekeeper, and clean-machine
  installation checks.
- Approved public release metadata, privacy terms, and license/EULA.
- Publication of the exact checksum-verified artifact to GitHub Releases and
  the personal-site mirror.
- Completed pre-package and post-package sign-offs, with all required macOS
  checks in `RELEASE-CHECKLIST.md`, for the exact release candidate.

## Release-readiness snapshot — 2026-09-04

At the time of this snapshot:

- Keychain inspection found only
  `Apple Development: Firas Al Kafri (752LD44EEA)`, not the required
  `Developer ID Application: Firas Al Kafri (752LD44EEA)` identity and private
  key.
- No notarytool Keychain profile name had been supplied or validated.
- No exact signed annotated `v0.1.0` tag had been created.
- No clean, UI-enabled verification evidence had been generated for the
  intended public release revision.
- No Developer ID signing or notarization had been attempted.
