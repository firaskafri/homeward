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

Concurrent local verification runs must use distinct DerivedData directories,
for example `HOMEWARD_DERIVED_DATA_PATH=.build/xcode-agent-1
./scripts/verify.sh`.

## Automated layers

- `swift test`: deterministic schedule, validation, notes, persistence, and
  enforcement-planning tests.
- `HomewardAppTests`: app composition and fixture-backed public macOS
  lifecycle tests.
- `HomewardUITests`: first-launch and explicit completed-setup accessibility
  reachability.
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

Automated unit, integration, and UI tests must not select, launch, quit, or
otherwise control an installed user application. If manual or agent-driven
validation requires a real application, use only Slack at
`/Applications/Slack.app` with bundle identifier
`com.tinyspeck.slackmacgap`. Confirm both values immediately before the test,
and stop if they do not match. Never use Cursor
(`com.todesktop.230313mzl4w4u92`) or another development tool as a Homeward
test target, and do not substitute another application when Slack is
unavailable.

The lifecycle controller independently enforces the automated boundary
immediately before activation or termination: hosted tests permit only the
adjacent `HomewardFixture.app` identity. Normal app runs retain the product's
user-selected app behavior; the Slack-only requirement applies to manual and
agent-driven validation.

The completed-setup launch test copies the canonical
`TestFixtures/HomewardCompletedSetup/configuration.json` resource into isolated
storage. Its preview-only application identities cannot match real running
applications. UI launches also set `HOMEWARD_UI_TESTING=1`, which replaces
notification, login-item, and catalog integrations with inert test adapters.
Hosted native tests set `HOMEWARD_TESTING=1` and use isolated temporary
storage, so the test host cannot load or enforce the user’s real policy.
Test invocations disable the bundle’s multiple-instance lock to prevent stale
LaunchServices registrations from another DerivedData directory blocking the
isolated host; Release verification still requires the lock.

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
