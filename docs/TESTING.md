# Homeward Testing

Run all automated checks with:

```sh
./scripts/verify.sh
```

UI automation requires an unlocked session without another system
authentication prompt. When that external prerequisite is unavailable, run
the remaining gate explicitly with:

```sh
RUN_UI_TESTS=0 ./scripts/verify.sh
```

The skipped UI test remains a manual blocker; this option must not be used to
certify a release.

## Automated layers

- `swift test`: deterministic schedule, validation, notes, persistence, and
  enforcement-planning tests.
- `HomewardAppTests`: app composition and fixture-backed public macOS
  lifecycle tests.
- `HomewardUITests`: first-launch accessibility reachability.
- `xcodebuild analyze`: static analysis under the production project settings.
- Release build inspection: arm64 architecture, menu-bar accessory property,
  and fixture exclusion.

Every unit-test file, suite/type, and test case documents:

1. Name
2. Description
3. Assumptions
4. Expectations

`scripts/check-test-docs.swift` enforces that structure.

## Fixture safety

Destructive lifecycle tests target only `HomewardFixture.app`, built from
`TestFixtures/HomewardFixture` with bundle identifier
`com.firaskafri.homeward.fixture`. Tests verify both the exact build-products
path and bundle identifier before force termination. Real user applications
must never be force-terminated by automated tests.

## Manual gates

These cannot be certified by unattended automation:

- Notification authorization and actions.
- Start-at-login approval, logout/login, and restart.
- Sleep/wake, screen lock, Fast User Switching, and Spaces.
- Countdown visibility and focus interaction with real save dialogs.
- VoiceOver, Voice Control, Full Keyboard Access, Zoom, contrast, and reduced
  motion/transparency.
- Developer ID signing, notarization, Gatekeeper, and clean-machine install.
- Seven-day safety and two-week behavioral dogfood.
