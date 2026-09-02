# Homeward Feasibility Evidence

## Environment

- Host architecture: Apple Silicon (`arm64`)
- Host OS: macOS 26.6.1
- Xcode: 26.6
- Swift: 6.3.3
- macOS SDK: 26.5
- Deployment target: macOS 15.0
- CI: macOS 15 arm64 with Xcode 16.4

## Automated evidence

- A native SwiftUI/AppKit menu-bar accessory builds for arm64 and macOS 15.
- The first-launch window is reachable through macOS UI automation.
- `NSWorkspace.openApplication` launches the dedicated fixture.
- `NSRunningApplication.terminate()` closes the immediate fixture normally.
- A fixture can reject normal termination and remain alive.
- `NSRunningApplication.forceTerminate()` closes that refusing fixture.
- Core tests validate schedule boundaries, overnight rules, DST,
  today-only availability effects, process identity, Firm cancellation, local
  persistence, recovery candidates, and note validation.
- The app builds without App Sandbox, Accessibility, Screen Recording,
  Automation, system-extension, or privileged-helper entitlements.
- UI automation verifies that the pre-activation Homeward menu-bar item is
  accessibility-visible.

## Evidence still requiring manual execution

- Real notification permission and action behavior.
- `SMAppService.mainApp` registration after installing Homeward in
  `/Applications`.
- Sleep/wake, logout/login, restart, screen lock, and Fast User Switching.
- Countdown visibility across Spaces/full-screen apps and focus interaction
  with a real save dialog.
- Representative third-party applications, including Electron apps and
  browsers.
- Developer ID signing, notarization, stapling, Gatekeeper, and offline first
  launch.

Firm Close is a dogfood candidate only after the manual countdown and session
activity checks pass.
