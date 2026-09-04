# Homeward Status

## Implemented and automatable

- Native macOS menu-bar app, schedule resolution, app selection, Gentle and
  Firm closing flows, today-only changes, notes, recovery, notifications, and
  Start at Login integration.
- Core, app-layer, fixture-backed lifecycle, and seven isolated UI scenarios
  covering first launch, completed reopen, delayed Retry, split recovery,
  installation gating, and representative long-name Work Apps reachability.
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

## Required before public release

- Seven-day safety and two-week behavioral dogfood gates.
- Developer ID signing, notarization, stapling, Gatekeeper, and clean-machine
  installation checks.
- Approved public release metadata, privacy terms, and license/EULA.
- Publication of the exact checksum-verified artifact to GitHub Releases and
  the personal-site mirror.

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
