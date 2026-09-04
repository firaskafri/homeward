#!/bin/bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
derived_data="$repository_root/.build/xcode"
app="$derived_data/Build/Products/Release/Homeward.app"
dist="$repository_root/dist"
verification_marker="$repository_root/.build/verified-release.env"

cd "$repository_root"

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

# shellcheck disable=SC1090
source "$verification_marker"
source_sha="$(git rev-parse HEAD)"
binary="$app/Contents/MacOS/Homeward"
plist="$app/Contents/Info.plist"
[[ "$SOURCE_SHA" == "$source_sha" &&
   "$BINARY_SHA" == "$(shasum -a 256 "$binary" | awk '{print $1}')" &&
   "$PLIST_SHA" == "$(shasum -a 256 "$plist" | awk '{print $1}')" ]] || {
  printf 'Release app does not match the latest verified source/build.\n' >&2
  exit 1
}

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
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
ARCHITECTURE="$architecture" \
BUILD="$build" \
BUNDLE_IDENTIFIER="$bundle_identifier" \
CHECKSUM="$checksum" \
MINIMUM_SYSTEM_VERSION="$minimum_system_version" \
SIGNATURE="$signature" \
SIZE="$size" \
SOURCE_SHA="$source_sha" \
SWIFT_VERSION="$swift_version" \
VERSION="$version" \
XCODE_VERSION="$xcode_version" \
/usr/bin/python3 - "$output_root/${artifact_name}.manifest.json" <<'PY'
import json
import os
import sys

manifest = {
    "artifact": os.environ["ARTIFACT"],
    "architecture": os.environ["ARCHITECTURE"],
    "build": os.environ["BUILD"],
    "bundleIdentifier": os.environ["BUNDLE_IDENTIFIER"],
    "license": "All rights reserved",
    "minimumSystemVersion": os.environ["MINIMUM_SYSTEM_VERSION"],
    "sha256": os.environ["CHECKSUM"],
    "signature": os.environ["SIGNATURE"],
    "size": int(os.environ["SIZE"]),
    "sourceSHA": os.environ["SOURCE_SHA"],
    "swift": os.environ["SWIFT_VERSION"],
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

dsym="$derived_data/Build/Products/Release/Homeward.app.dSYM"
[[ -d "$dsym" ]] || {
  printf 'Release dSYM is missing: %s\n' "$dsym" >&2
  exit 1
}
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

printf 'Created %s\n' "$dist/${artifact_name}.dmg"
printf 'SHA-256 %s\n' "$checksum"
