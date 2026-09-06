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

The skipped UI, journey, and Release lifecycle suites remain release
blockers; this option must not be used to certify a release.

Concurrent local verification runs must use distinct DerivedData directories,
for example `HOMEWARD_DERIVED_DATA_PATH=.build/xcode-agent-1
./scripts/verify.sh`.

## Release-gate evidence model

The A-to-Z gate separates three kinds of evidence that must not be treated as
interchangeable:

- **Shell-hosted journeys** run production Homeward model and view sources in
  `HomewardTestShell.app` with isolated storage and typed deterministic
  platform substitutes.
- **Exact Release lifecycle** exercises the built Release `Homeward.app` with
  normal multiple-instance protection and the real workspace monitor,
  enforcement planner, safety panel, and lifecycle controller. Catalog,
  notification, login-item, and installation services remain isolated, and
  lifecycle control is restricted to the adjacent `HomewardFixture.app`.
- **Real-platform manual evidence** covers Notification Center, Start at Login,
  power/session/display behavior, real save-dialog interaction, assistive
  technologies, signing, notarization, Gatekeeper, and clean installation.

All three lanes are required for every public release. See
`RELEASE-CHECKLIST.md` for the complete contract and evidence identities.

## Automated layers

- `swift test`: deterministic schedule, validation, notes, persistence, and
  enforcement-planning tests.
- `HomewardAppTests`: app composition and fixture-backed public macOS
  lifecycle tests.
- `HomewardUITests`: first-launch and completed-setup reopening, delayed
  startup and Retry, configuration-versus-notes recovery, outside-Applications
  Start at Login gating, moved-app restart guidance, login approval and enabled
  states, compact schedule disclosure reachability, schedule editing,
  overnight labels, onboarding schedule progression, and representative
  long-English Work Apps reachability.
- `HomewardJourneyUITests`: Release-built `HomewardTestShell.app` journeys
  through onboarding, preview choices, management navigation, recovery,
  end-work, and return-to-weekly-schedule consequences using isolated
  deterministic platform substitutes.
- `HomewardReleaseE2ETests`: the exact Release `Homeward.app` and adjacent
  `HomewardFixture.app` through Gentle, Firm, Stop, and blocked-relaunch
  lifecycle paths with production timing and multiple-instance protection.
- `xcodebuild analyze`: static analysis under the production project settings.
- Release build inspection: arm64 architecture, menu-bar accessory property,
  and fixture exclusion.

Every unit-test file, suite/type, and test case documents:

1. Name
2. Description
3. Assumptions
4. Expectations

`scripts/check-test-docs.swift` enforces that structure.

`scripts/release_coverage_contract.json` maps every active traceability
requirement to automated or manual evidence. `scripts/validate_release_coverage.py`
rejects missing, duplicate, orphaned, or still-planned automated evidence.
Release result bundles are checked against the contract's exact required test
identifiers before verification evidence is written.

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
user-selected app behavior except for the non-overridable protected-app
denylist, which includes Homeward, critical macOS processes, and Cursor. The
Slack-only requirement applies to manual and agent-driven validation.

The UI suite uses one named `IsolatedApplicationFixture.Scenario` mechanism.
Each scenario creates unique temporary storage, copies only its declared
configuration or notes resources, and supplies one
`HOMEWARD_UI_TEST_SCENARIO` value. The completed and long-content resources use
preview-only application identities that cannot match real running
applications. UI launches also set `HOMEWARD_UI_TESTING=1`, which restricts
lifecycle control to the adjacent `HomewardFixture.app` identity and replaces
notification, login-item, catalog, installation-location, and delayed-startup
dependencies with scenario-owned adapters. Reopen coverage resolves the
adjacent build-products `Homeward.app`, verifies that exact standardized path
and `com.firaskafri.homeward` identity against the running UI-test process,
then opens the verified path. It never performs bundle-identifier-only lookup.
Hosted native tests set `HOMEWARD_TESTING=1` and use isolated temporary
storage, so the test host cannot load or enforce the user’s real policy.
Test invocations disable the bundle’s multiple-instance lock to prevent stale
LaunchServices registrations from another DerivedData directory blocking the
isolated host; Release verification still requires the lock.

## Automated evidence boundary

The deterministic suite covers startup mutation gating and delayed Retry;
configuration and notes recovery separation; stale/current notification action
routing and shared confirmation intent; Saved Thoughts concealment, session
transitions, completion Restore, and recovery; Firm Stop ordering and
presentation precedence; installation-location gating; and representative
long-application-name reachability. Isolated UI scenarios additionally cover
compact schedule summaries, one-day-at-a-time editing, mode/reset behavior,
overnight destination labels, onboarding Save & Continue, Start-at-Login
approval, enabled-confirmation, and moved-app restart states.

The long-English UI scenario proves that the Work Apps row and chooser remain
reachable with a representative long application name. The schedule scenario
proves structural reachability at the minimum window width. Automation does
not certify visual quality at every resize point, system text-size settings,
other long-copy surfaces, or assistive-technology navigation modes.

## Manual gates

These cannot be certified by unattended automation:

- Real Notification Center authorization, presentation, and action delivery.
- Real Start at Login approval, logout/login, and restart.
- Sleep/wake, screen lock, Fast User Switching, Spaces, and multiple displays.
- Countdown visibility and focus interaction with real save dialogs and
  third-party applications.
- VoiceOver, Voice Control, Switch Control, Full Keyboard Access, Zoom,
  contrast, and reduced motion/transparency.
- Compact resizing and largest supported macOS text settings beyond the
  deterministic long-English reachability scenario.
- Developer ID signing, notarization, Gatekeeper, and clean-machine install.
- Seven-day safety and two-week behavioral dogfood.

For real-application evidence, verify immediately beforehand that the
standardized path is exactly `/Applications/Slack.app` and the bundle
identifier is exactly `com.tinyspeck.slackmacgap`. Stop if either check fails
or Slack is unavailable; do not substitute another application. Automated
destructive tests remain fixture-only, and Cursor
(`com.todesktop.230313mzl4w4u92`) is never a test target.

Manual records must identify the tested source SHA and verified app-tree hash
before packaging, or the final stapled DMG SHA-256 and accepted notarization
submission ID after packaging. A passing result for different bytes is not
release evidence.

Passing these gates is evidence for a release decision, not a claim that the
application is 100% bug-free. Product or UX changes must update the coverage
contract—journeys, states, copy/consequences, accessibility expectations,
fixtures, automated assertions, and manual scenarios—and rerun all affected
evidence before sign-off.
