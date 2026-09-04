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
evidence="$(homeward_read_release_evidence "$verification_marker" 0)"
IFS=$'\t' read -r verified_source_sha verified_app_tree_sha \
  verified_binary_uuid verified_dsym_tree_sha verified_version \
  verified_build verified_ui_tests <<<"$evidence"
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
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app"
homeward_verify_dsym "$binary" "$dsym"

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
xcode_version="$(xcodebuild -version | tr '\n' ' ' | sed 's/ $//')"
swift_version="$(swift --version 2>&1 | sed -n '1p')"

ARTIFACT="${artifact_name}.dmg" \
APP_TREE_SHA="$verified_app_tree_sha" \
ARCHITECTURE="$architecture" \
BINARY_UUID="$verified_binary_uuid" \
BUILD="$build" \
BUNDLE_IDENTIFIER="$bundle_identifier" \
CHECKSUM="$checksum" \
MINIMUM_SYSTEM_VERSION="$minimum_system_version" \
DSYM_TREE_SHA="$verified_dsym_tree_sha" \
SIGNATURE="$signature" \
SIZE="$size" \
SOURCE_SHA="$source_sha" \
SWIFT_VERSION="$swift_version" \
UI_TESTS_ENABLED="$verified_ui_tests" \
VERSION="$version" \
XCODE_VERSION="$xcode_version" \
/usr/bin/python3 - "$output_root/${artifact_name}.manifest.json" <<'PY'
import json
import os
import sys

manifest = {
    "artifact": os.environ["ARTIFACT"],
    "appTreeSHA256": os.environ["APP_TREE_SHA"],
    "architecture": os.environ["ARCHITECTURE"],
    "binaryUUID": os.environ["BINARY_UUID"],
    "build": os.environ["BUILD"],
    "dSYMTreeSHA256": os.environ["DSYM_TREE_SHA"],
    "bundleIdentifier": os.environ["BUNDLE_IDENTIFIER"],
    "license": "All rights reserved",
    "minimumSystemVersion": os.environ["MINIMUM_SYSTEM_VERSION"],
    "sha256": os.environ["CHECKSUM"],
    "signature": os.environ["SIGNATURE"],
    "size": int(os.environ["SIZE"]),
    "sourceSHA": os.environ["SOURCE_SHA"],
    "swift": os.environ["SWIFT_VERSION"],
    "uiTestsEnabled": os.environ["UI_TESTS_ENABLED"] == "true",
    "version": os.environ["VERSION"],
    "xcode": os.environ["XCODE_VERSION"],
}
with open(sys.argv[1], "w", encoding="utf-8") as output:
    json.dump(manifest, output, indent=2, sort_keys=True)
    output.write("\n")
PY

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
