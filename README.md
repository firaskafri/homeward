# Homeward

Homeward is a native macOS menu-bar app that closes selected work applications
when a scheduled work window ends and closes them again if they are reopened
while work is unavailable.

Homeward is a commitment aid, not a security boundary. It manages GUI
applications only and does not inspect documents, windows, browser history,
terminal commands, or AI conversations.

## Status

Local MVP development is authorized after the Phase 0 gates in the canonical
product requirements document. Developer ID signing, notarization, public
distribution, full manual accessibility review, and dogfood gates remain
pending.

Canonical PRD:

`/Users/firaskafri/.openclaw/workspace/projects/homeward/PRD.md`

## Requirements

- macOS 15 or later
- Apple Silicon
- Xcode 16.4 or later / Swift 6
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.46 or later

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

To produce a non-public, ad-hoc-signed DMG and provenance manifest after
verification:

```sh
RUN_UI_TESTS=0 ./scripts/package-local-candidate.sh
```

That artifact is for local testing only; public distribution still requires
Developer ID signing and notarization.

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
