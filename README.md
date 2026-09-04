# Homeward

Homeward is a native macOS menu-bar app that closes selected work applications
when a scheduled work window ends and closes them again if they are reopened
while work is unavailable.

Homeward is a commitment aid, not a security boundary. It manages GUI
applications only and does not inspect documents, windows, browser history,
terminal commands, or AI conversations.

## Status

The MVP implementation and automated local verification pipeline are present.
Developer ID signing, notarization, public distribution, full manual
accessibility/system validation, and dogfood gates remain pending.

See [`docs/STATUS.md`](docs/STATUS.md) for the current evidence boundary,
[`docs/DECISIONS.md`](docs/DECISIONS.md) for the implementation baseline, and
[`docs/TRACEABILITY.md`](docs/TRACEABILITY.md) for requirement coverage. The
original planning PRD is owner-local and is not part of this repository.

## Requirements

- macOS 15 or later
- Apple Silicon
- Xcode 16.4 or later / Swift 6
- [XcodeGen 2.46.0](https://github.com/yonaskolb/XcodeGen/releases/tag/2.46.0)

## Build

```sh
xcodegen generate
xcodebuild \
  -project Homeward.xcodeproj \
  -scheme Homeward \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Verify

```sh
./scripts/verify.sh
```

The verification entry point regenerates the Xcode project, checks mandatory
test documentation, runs pure-core tests, native app and UI tests, static
analysis, and an arm64 Release build.

To produce an unreleased, ad-hoc-signed development DMG and provenance
manifest after verification:

```sh
RUN_UI_TESTS=0 ./scripts/package-local-candidate.sh
```

That artifact is test evidence, not a distributable release. It remains
development-only.

Public distribution uses the separate fail-closed Developer ID workflow:

```sh
./scripts/package-public-release.sh --check \
  --identity "Developer ID Application: Firas Al Kafri (752LD44EEA)" \
  --team-id 752LD44EEA \
  --notary-profile "<keychain-profile>"
```

See [`docs/DISTRIBUTION.md`](docs/DISTRIBUTION.md) for the exact tagged release
procedure and artifact set, and [`docs/STATUS.md`](docs/STATUS.md) for the
dated release-readiness snapshot.

## Architecture

- `Sources/HomewardCore`: Foundation-only schedule, configuration, persistence,
  note, and enforcement planning logic.
- `HomewardApp`: SwiftUI/AppKit application, macOS adapters, and presentation.
- `HomewardAppTests`: app-layer and fixture-backed lifecycle tests.
- `HomewardUITests`: accessibility-driven first-launch tests.
- `TestFixtures/HomewardFixture`: disposable lifecycle target used only by
  tests.

The app is unsandboxed because App Sandbox does not permit the required
cross-application lifecycle management. It uses public macOS APIs and does not
request Accessibility, Screen Recording, Automation, administrator, or
privileged-helper access.

## License

Copyright © 2026 Firas Kafri. All rights reserved. No license to copy, modify,
or distribute this source is granted pending legal review.
