# Homeward Status

## Implemented and automatable

- Native macOS menu-bar app, schedule resolution, app selection, Gentle and
  Firm closing flows, today-only changes, notes, recovery, notifications, and
  Start at Login integration.
- Core, app-layer, fixture-backed lifecycle, first-launch UI, and explicit
  completed-setup launch tests.
- Static analysis, arm64 Release inspection, ad-hoc signing checks, and
  checksum/provenance packaging.
- GitHub Actions runs the non-interactive automated subset on macOS 15 with
  Xcode 16.4. Local `scripts/verify.sh` includes UI automation by default.

Passing automation demonstrates deterministic logic, fixture lifecycle
behavior, build integrity, and basic UI reachability. It does not certify real
third-party app behavior, assistive-technology usability, login-item behavior,
or distributable signing.

## Required before dogfood

- Real notification permission and action checks.
- Start-at-login approval, logout/login, restart, sleep/wake, screen lock, Fast
  User Switching, Spaces, and multiple-display checks.
- Representative third-party application and save-dialog behavior.
- Full keyboard and assistive-technology validation documented in
  `ACCESSIBILITY.md`.

## Required before public release

- Seven-day safety and two-week behavioral dogfood gates.
- Developer ID signing, notarization, stapling, Gatekeeper, and clean-machine
  installation checks.
- Approved public release metadata, privacy terms, and license/EULA.
- Publication of the exact checksum-verified artifact to GitHub Releases and
  the personal-site mirror.
