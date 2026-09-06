#!/bin/bash

set -euo pipefail

# Development evidence only. This script never performs Developer ID signing
# or notarization; use package-public-release.sh for public artifacts.

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
derived_data="${HOMEWARD_DERIVED_DATA_PATH:-$repository_root/.build/xcode}"
app="$derived_data/Build/Products/Release/Homeward.app"
dist="$repository_root/dist"
verification_marker="${HOMEWARD_VERIFICATION_MARKER:-$derived_data/verified-release.json}"

cd "$repository_root"
# shellcheck source=scripts/release-evidence.sh
source "$repository_root/scripts/release-evidence.sh"

if [[ -n "$(git status --porcelain)" ]]; then
  printf 'Release-candidate packaging requires a clean working tree.\n' >&2
  exit 1
fi

if [[ "${SKIP_VERIFY:-0}" != "1" ]]; then
  RUN_UI_TESTS="${RUN_UI_TESTS:-0}" ./scripts/verify.sh
fi

[[ -d "$app" ]] || {
  printf 'Verified Release app is missing: %s\n' "$app" >&2
  exit 1
}
[[ -f "$verification_marker" ]] || {
  printf 'Verified release marker is missing. Run scripts/verify.sh first.\n' >&2
  exit 1
}

binary="$app/Contents/MacOS/Homeward"
plist="$app/Contents/Info.plist"
dsym="$derived_data/Build/Products/Release/Homeward.app.dSYM"
[[ -d "$dsym" ]] || {
  printf 'Release dSYM is missing: %s\n' "$dsym" >&2
  exit 1
}
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
verified_source_sha=""
verified_app_tree_sha=""
verified_binary_uuid=""
verified_dsym_tree_sha=""
verified_version=""
verified_build=""
verified_ui_tests=""
verified_ui_result_sha256=""
verified_journey_e2e=""
verified_release_e2e=""
verified_release_e2e_configuration=""
verified_release_e2e_scheme=""
verified_coverage_contract_sha256=""
verified_journey_result_sha256=""
verified_release_result_sha256=""
verified_xctestrun_sha256=""
evidence_assignments="$(
  homeward_read_release_evidence "$verification_marker" 0
)"
eval "$evidence_assignments"
source_sha="$(git rev-parse HEAD)"
[[ "$verified_source_sha" == "$source_sha" &&
   "$verified_app_tree_sha" == "$(homeward_tree_sha256 "$app")" &&
   "$verified_binary_uuid" == "$(homeward_macho_uuid "$binary")" &&
   "$verified_dsym_tree_sha" == "$(homeward_tree_sha256 "$dsym")" &&
   "$verified_version" == "$version" &&
   "$verified_build" == "$build" ]] || {
  printf 'Release app does not match the latest verified source/build.\n' >&2
  exit 1
}
result_directory="$derived_data/TestResults"
if [[ "$verified_ui_tests" == "true" ]]; then
  [[ "$verified_coverage_contract_sha256" == "$(
    shasum -a 256 "$repository_root/scripts/release_coverage_contract.json" |
      awk '{print $1}'
  )" ]] || {
    printf 'Release coverage contract does not match verification evidence.\n' >&2
    exit 1
  }
  homeward_verify_tree_evidence \
    "$result_directory/HomewardUI.xcresult" \
    "$verified_ui_result_sha256" \
    "UI test result"
fi
if [[ "$verified_journey_e2e" == "true" ]]; then
  homeward_verify_tree_evidence \
    "$result_directory/HomewardJourneyE2E.xcresult" \
    "$verified_journey_result_sha256" \
    "Journey E2E result"
fi
if [[ "$verified_release_e2e" == "true" ]]; then
  homeward_verify_tree_evidence \
    "$result_directory/HomewardReleaseE2E.xcresult" \
    "$verified_release_result_sha256" \
    "Release E2E result"
  shopt -s nullglob
  release_xctestrun_candidates=(
    "$derived_data"/Build/Products/HomewardReleaseE2E_*.xctestrun
  )
  shopt -u nullglob
  [[ "${#release_xctestrun_candidates[@]}" == "1" ]] || {
    printf 'Expected exactly one HomewardReleaseE2E xctestrun; found %s.\n' \
      "${#release_xctestrun_candidates[@]}" >&2
    exit 1
  }
  homeward_verify_file_evidence \
    "${release_xctestrun_candidates[0]}" \
    "$verified_xctestrun_sha256" \
    "Release E2E xctestrun"
fi
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app"
homeward_verify_dsym "$binary" "$dsym"
dsym_binary="$dsym/Contents/Resources/DWARF/Homeward"
dsym_uuid="$(homeward_macho_uuid "$dsym_binary")"

bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")"
minimum_system_version="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist")"
architecture="$(/usr/bin/lipo -archs "$binary")"
architecture_slug="${architecture// /-}"
artifact_name="Homeward-${version}-build.${build}-local-${architecture_slug}"
staging="$(mktemp -d "${TMPDIR:-/tmp}/homeward-release.XXXXXX")"
image_root="$staging/image"
output_root="$staging/output"
temporary_dmg="${TMPDIR:-/tmp}/${artifact_name}.$$.dmg"
trap 'rm -rf "$staging"; rm -f "$temporary_dmg"' EXIT

mkdir -p "$image_root" "$output_root"
/usr/bin/ditto "$app" "$image_root/Homeward.app"
ln -s /Applications "$image_root/Applications"

/usr/bin/hdiutil create \
  -quiet \
  -fs HFS+ \
  -format UDZO \
  -volname Homeward \
  -srcfolder "$image_root" \
  "$temporary_dmg"
mv "$temporary_dmg" "$output_root/${artifact_name}.dmg"

checksum="$(shasum -a 256 "$output_root/${artifact_name}.dmg" | awk '{print $1}')"
size="$(stat -f '%z' "$output_root/${artifact_name}.dmg")"
signature="$(/usr/bin/codesign --display --verbose=1 "$app" 2>&1 |
  awk -F= '/^Signature=/{print $2}')"
[[ "$signature" == "adhoc" ]] || {
  printf 'Local candidate app is not ad-hoc signed.\n' >&2
  exit 1
}
xcode_version="$(xcodebuild -version | tr '\n' ' ' | sed 's/ $//')"
swift_version="$(swift --version 2>&1 | sed -n '1p')"

ARTIFACT="${artifact_name}.dmg" \
APP_TREE_SHA="$verified_app_tree_sha" \
ARCHITECTURE="$architecture" \
BINARY_UUID="$verified_binary_uuid" \
BUILD="$build" \
BUNDLE_IDENTIFIER="$bundle_identifier" \
CHECKSUM="$checksum" \
COVERAGE_CONTRACT_SHA256="$verified_coverage_contract_sha256" \
MINIMUM_SYSTEM_VERSION="$minimum_system_version" \
DSYM_TREE_SHA="$verified_dsym_tree_sha" \
DSYM_UUID="$dsym_uuid" \
JOURNEY_E2E_ENABLED="$verified_journey_e2e" \
JOURNEY_RESULT_SHA256="$verified_journey_result_sha256" \
RELEASE_E2E_CONFIGURATION="$verified_release_e2e_configuration" \
RELEASE_E2E_ENABLED="$verified_release_e2e" \
RELEASE_E2E_SCHEME="$verified_release_e2e_scheme" \
RELEASE_RESULT_SHA256="$verified_release_result_sha256" \
SIGNATURE_MODE="ad-hoc" \
SIZE="$size" \
SOURCE_SHA="$source_sha" \
SWIFT_VERSION="$swift_version" \
UI_TESTS_ENABLED="$verified_ui_tests" \
UI_RESULT_SHA256="$verified_ui_result_sha256" \
VERSION="$version" \
XCTESTRUN_SHA256="$verified_xctestrun_sha256" \
XCODE_VERSION="$xcode_version" \
/usr/bin/python3 \
  "$repository_root/scripts/local_candidate_manifest.py" \
  "$output_root/${artifact_name}.manifest.json"

(
  cd "$output_root"
  shasum -a 256 "${artifact_name}.dmg" \
    >"${artifact_name}.dmg.sha256"
)

/usr/bin/ditto \
  -c -k --keepParent \
  "$dsym" \
  "$output_root/${artifact_name}.dSYM.zip"

mkdir -p "$dist"
rm -f \
  "$dist/${artifact_name}.dmg" \
  "$dist/${artifact_name}.dmg.sha256" \
  "$dist/${artifact_name}.dSYM.zip" \
  "$dist/${artifact_name}.manifest.json"
mv "$output_root"/* "$dist/"

printf 'Created development-only candidate %s\n' "$dist/${artifact_name}.dmg"
printf 'SHA-256 %s\n' "$checksum"
