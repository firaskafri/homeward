# Homeward Distribution

## Artifact boundaries

`scripts/package-local-candidate.sh` is development-only. It produces an
ad-hoc-signed local DMG for build evidence and never produces a public
artifact, even when UI tests ran. Its strict provenance schema binds the
verified source SHA, app version/build, architecture, minimum macOS version,
ad-hoc signature mode, `notarized: false`, matching binary/dSYM UUIDs, and the
final DMG SHA-256 and byte size.

`scripts/package-public-release.sh` is the separate fail-closed Developer ID
path. Its `--check` mode is read-only: it does not copy, sign, package, submit,
staple, or publish anything. The release mode creates local files in `dist/`;
it does not commit, push, create a tag, or create a GitHub release.

## One-time credential setup

Install a `Developer ID Application` certificate and its private key in the
login Keychain. Store notarization credentials under a named profile without
putting issuer IDs, key IDs, private keys, or passwords in the repository:

```sh
xcrun notarytool store-credentials "<keychain-profile>"
```

Only the Developer ID identity name, ten-character Team ID, and Keychain
profile name are passed to the release script. The script relies on Keychain
for all secrets and never enables shell tracing.

## Exact operator flow

1. Complete and record the manual accessibility, lifecycle, safety, dogfood,
   legal, and privacy gates listed in `STATUS.md`.
2. Commit the intended source, push the branch, and run UI-enabled verification
   on that exact clean commit:

   ```sh
   git push origin main
   RUN_UI_TESTS=1 ./scripts/verify.sh
   ```

   On a clean source tree, evidence schema 2 records `uiTestsEnabled: true`,
   source SHA, version, build, app-tree hash, binary UUID, and dSYM-tree hash.
   Dirty-tree verification emits no release evidence, and evidence generated
   with `RUN_UI_TESTS=0` is rejected by the public path.
3. Create and push the exact signed annotated version tag. For 0.1.0:

   ```sh
   git tag -s -a v0.1.0 -m "Homeward 0.1.0"
   git push origin v0.1.0
   ```

4. Run the read-only preflight, substituting the actual profile name:

   ```sh
   ./scripts/package-public-release.sh --check \
     --identity "Developer ID Application: Firas Al Kafri (752LD44EEA)" \
     --team-id 752LD44EEA \
     --notary-profile "<keychain-profile>"
   ```

   Preflight requires a clean tree, remote branch and remote tag matching
   local HEAD, a valid Git signature on the annotated tag, exact UI-enabled
   evidence, the exact Developer ID identity and Team ID, and a working named
   notarytool profile.
5. Run the same command without `--check`. The script:
   - copies the verified arm64 Release app into temporary staging;
   - enumerates and signs actual nested Mach-O code and nested code bundles
     inside-out, then signs the app with Hardened Runtime and a secure
     timestamp; signing never uses `--deep`;
   - verifies every signature plus exact certificate, Team ID, bundle ID,
     Runtime, an empty entitlement allowlist (therefore no App Sandbox or
     `get-task-allow`), arm64/macOS 15 metadata, matching dSYM UUID, and no test
     fixtures;
   - creates a compressed read-only, versioned DMG containing an
     `/Applications` symlink and signs that DMG;
   - submits that final outer DMG with
     `xcrun notarytool submit --wait --output-format json`, retains the JSON
     result, and requires `Accepted`;
   - staples and validates the DMG, then assesses the disk image with
     `spctl --type open --context context:primary-signature`;
   - computes size and SHA-256 only after stapling.
6. Preserve all five outputs together: the canonical
   `Homeward-<version>-arm64.dmg`, its `.dmg.sha256`, provenance manifest,
   matching dSYM zip, and notarization JSON. The filename omits build metadata;
   the manifest records the source/tag, version/build, architecture/minimum OS,
   toolchain, certificate, Team ID, CDHash, notarization ID/status, final
   size/hash, and binary/dSYM UUIDs.
7. Perform the documented quarantined clean-account and offline launch checks,
   then publish the exact checksum-verified bytes to GitHub Releases and the
   personal-site mirror. Publication remains a separate manual action.

## Privacy manifest applicability

Apple's mandatory privacy-manifest and required-reason enforcement is stated
as an App Store Connect submission requirement. Homeward 0.1.0 is a direct
Developer ID download, and Apple's notarization procedure does not make a
privacy manifest an upload gate. The app has no third-party SDK dependencies,
and the 0.1.0 source audit found no direct use of Apple's listed required-reason
API families. An empty or speculative `PrivacyInfo.xcprivacy` would therefore
be inaccurate and is not added.

This does not waive privacy obligations. Public privacy claims must accurately
describe Homeward's data handling, and any future use of a required-reason API,
third-party SDK, or App Store submission requires a fresh audit and a truthful
manifest where applicable.

Automatic updates are out of scope. MVP updates are manual
download-and-replace operations.
