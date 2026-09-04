# Homeward Distribution

## Current build

The automated verification pipeline produces an arm64, macOS 15 Release app
with an ad-hoc local signature and Hardened Runtime. This is suitable for local
verification only.

`scripts/package-local-candidate.sh` packages that verified app into a local
DMG and emits a checksum, provenance manifest, and required dSYM archive. CI
retains these files as unreleased evidence tied to the source commit; access is
governed by GitHub artifact permissions.

Verification records the complete signed app tree, app-binary UUID, and dSYM
tree in a strict JSON evidence file. Packaging revalidates those values and the
code signature before producing artifacts.

## Public release prerequisites

- Developer ID Application certificate and private key.
- Notarization credentials.
- Final name/trademark decision.
- Approved privacy terms and license/EULA.
- Completed manual accessibility and system-lifecycle checks.
- Seven-day safety gate and two-week behavioral dogfood.

## Intended release flow

1. Verify a clean tagged source revision.
2. Archive an arm64 Release build.
3. Sign nested code inside-out with Developer ID and Hardened Runtime.
4. Verify the entitlement allowlist and absence of App Sandbox and
   `get-task-allow`.
5. Package, notarize, staple, and Gatekeeper-check a DMG.
6. Test the quarantined DMG after copying Homeward to `/Applications`,
   including an offline first launch.
7. Publish the exact DMG and checksum in `firaskafri/homeward`.
8. Supply the checksum-verified artifact to the existing personal-site release
   without committing the DMG binary.
9. Verify that both downloads return identical bytes.

Automatic updates are out of scope. MVP updates are manual
download-and-replace operations.
