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

The A-to-Z gate in `RELEASE-CHECKLIST.md` is required for every public
release, not only the first release or a major version. Public packaging
requires evidence from the existing UI suite, shell journeys, and exact
Release fixture lifecycle suite.

## Two artifact-bound sign-offs

Before packaging, record an approval bound to both the clean source SHA and the
UI-enabled verification evidence's Release app-tree SHA-256. The record also
identifies the version/build, coverage-contract revision, operator and time,
macOS/Xcode/hardware, evidence links, and defect or risk disposition. Any
source or app-bundle change invalidates the approval.

After packaging and clean-install validation, record a separate approval bound
to both the final stapled DMG SHA-256 and the accepted notarization submission
ID in the retained notarytool JSON. DMG regeneration, restapling, or any byte
change invalidates this approval. A matching filename or version is not
sufficient.

The first sign-off authorizes packaging of the identified app candidate. The
second authorizes publication of the identified DMG bytes. Neither is a claim
that Homeward is 100% bug-free.

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

1. Complete and record the A-to-Z source, shell-hosted, exact Release
   lifecycle, real-platform macOS, accessibility, safety, dogfood, legal, and
   privacy gates listed in `RELEASE-CHECKLIST.md` and `STATUS.md`.
2. Commit the intended source, push the branch, and run UI-enabled verification
   on that exact clean commit:

   ```sh
   git push origin main
   RUN_UI_TESTS=1 RUN_JOURNEY_E2E=1 RUN_RELEASE_E2E=1 \
     ./scripts/verify.sh
   ```

   On a clean source tree, evidence schema 3 records successful UI, journey,
   and exact Release lifecycle layers; their result hashes; the coverage
   contract and xctestrun hashes; source SHA; version/build; app-tree hash;
   binary UUID; and dSYM-tree hash. Dirty-tree verification emits no release
   evidence, and evidence with any required UI layer disabled is rejected by
   the public path.
   Complete the pre-package sign-off against this exact source SHA and app-tree
   hash before continuing.
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
7. Perform the documented quarantine-preserving clean-account install,
   Gatekeeper first open, online launch, offline launch, and installed-app
   smoke checks against the final DMG. Record the post-package sign-off against
   its exact SHA-256 and accepted notarization submission ID, then publish
   those exact checksum-verified bytes to GitHub Releases and the personal-site
   mirror. Verify both published downloads reproduce the approved hash.
   Publication remains a separate manual action.

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
