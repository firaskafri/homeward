#!/bin/bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
derived_data="${HOMEWARD_DERIVED_DATA_PATH:-$repository_root/.build/xcode}"
project="$repository_root/Homeward.xcodeproj"
destination="platform=macOS,arch=arm64"
verification_marker="${HOMEWARD_VERIFICATION_MARKER:-$derived_data/verified-release.json}"
native_test_storage="$derived_data/native-test-storage"

cd "$repository_root"
rm -f "$verification_marker"
rm -rf "$native_test_storage"
trap 'rm -rf "$native_test_storage"' EXIT
source "$repository_root/scripts/release-evidence.sh"

[[ "$(uname -m)" == "arm64" ]] || {
  printf 'Homeward verification requires an Apple Silicon host.\n' >&2
  exit 1
}

stop_repository_test_instances() {
  local pattern="$repository_root/.*/Homeward.app/Contents/MacOS/Homeward"
  local process_ids
  process_ids="$(pgrep -f "$pattern" || true)"
  if [[ -n "$process_ids" ]]; then
    printf 'Stopping stale Homeward test instance(s): %s\n' "$process_ids"
    while IFS= read -r process_id; do
      kill "$process_id"
      for _ in {1..50}; do
        kill -0 "$process_id" 2>/dev/null || break
        sleep 0.1
      done
      if kill -0 "$process_id" 2>/dev/null; then
        printf 'Homeward test instance did not terminate: %s\n' \
          "$process_id" >&2
        exit 1
      fi
    done <<<"$process_ids"
  fi
  if pgrep -x Homeward >/dev/null; then
    printf 'Quit any installed Homeward app before running native tests.\n' >&2
    exit 1
  fi
}

command -v xcodegen >/dev/null || {
  printf 'XcodeGen 2.46.0 is required; install the pinned release archive.\n' >&2
  exit 1
}

xcode_version="$(xcodebuild -version | awk 'NR == 1 { print $2 }')"
IFS=. read -r xcode_major xcode_minor _ <<<"$xcode_version"
if (( xcode_major < 16 || (xcode_major == 16 && xcode_minor < 4) )); then
  printf 'Xcode 16.4 or later is required; found %s.\n' \
    "$xcode_version" >&2
  exit 1
fi

required_xcodegen_version="2.46.0"
actual_xcodegen_version="$(xcodegen version | awk '{print $2}')"
if [[ "$actual_xcodegen_version" != "$required_xcodegen_version" ]]; then
  printf 'XcodeGen %s is required; found %s.\n' \
    "$required_xcodegen_version" "$actual_xcodegen_version" >&2
  exit 1
fi

generated_hash() {
  {
    /usr/bin/find "$project" -type f \
      ! -path '*/xcuserdata/*' \
      ! -name '*.xcuserstate' \
      -print
    printf '%s\n' "$repository_root/HomewardApp/Info.plist"
  } |
    LC_ALL=C /usr/bin/sort |
    while IFS= read -r generated_file; do
      shasum -a 256 "$generated_file"
    done |
    shasum -a 256 |
    awk '{print $1}'
}

before_generation="$(generated_hash)"
xcodegen generate
after_generation="$(generated_hash)"
[[ "$before_generation" == "$after_generation" ]] || {
  printf 'Homeward.xcodeproj was stale. Regenerate and review it before verification.\n' >&2
  exit 1
}
swift scripts/render-app-icon.swift --check
stop_repository_test_instances
xcodebuild \
  -project "$project" \
  -scheme Homeward \
  -destination "$destination" \
  -derivedDataPath "$derived_data" \
  clean
swift scripts/check-test-docs.swift
swift test

HOMEWARD_TESTING=1 \
HOMEWARD_STORAGE_DIRECTORY="$native_test_storage" \
xcodebuild \
  -project "$project" \
  -scheme Homeward \
  -destination "$destination" \
  -derivedDataPath "$derived_data" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  INFOPLIST_KEY_LSMultipleInstancesProhibited=NO \
  test

if [[ "${RUN_UI_TESTS:-1}" == "1" ]]; then
  stop_repository_test_instances
  xcodebuild \
    -project "$project" \
    -scheme HomewardUI \
    -destination "$destination" \
    -derivedDataPath "$derived_data" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY=- \
    DEVELOPMENT_TEAM= \
    INFOPLIST_KEY_LSMultipleInstancesProhibited=NO \
    test
else
  printf 'Skipping UI automation because RUN_UI_TESTS=%s.\n' \
    "${RUN_UI_TESTS:-0}"
fi

xcodebuild \
  -project "$project" \
  -scheme Homeward \
  -destination "$destination" \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  analyze

xcodebuild \
  -project "$project" \
  -scheme Homeward \
  -configuration Release \
  -destination "$destination" \
  -derivedDataPath "$derived_data" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  build

app="$derived_data/Build/Products/Release/Homeward.app"
binary="$app/Contents/MacOS/Homeward"
plist="$app/Contents/Info.plist"
app_icon="$app/Contents/Resources/AppIcon.icns"
dsym="$derived_data/Build/Products/Release/Homeward.app.dSYM"

[[ -d "$app" ]] || {
  printf 'Release app was not produced: %s\n' "$app" >&2
  exit 1
}
[[ -s "$app_icon" ]] || {
  printf 'Release app icon was not produced: %s\n' "$app_icon" >&2
  exit 1
}
[[ "$(/usr/bin/lipo -archs "$binary")" == "arm64" ]] || {
  printf 'Release binary is not arm64-only.\n' >&2
  exit 1
}
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$plist")" == "true" ]] || {
  printf 'Release app is not configured as a menu-bar accessory.\n' >&2
  exit 1
}
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMultipleInstancesProhibited' "$plist")" == "true" ]] || {
  printf 'Release app does not prohibit multiple instances.\n' >&2
  exit 1
}
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ &&
   "$build" =~ ^[1-9][0-9]*$ ]] || {
  printf 'Release app version metadata is invalid.\n' >&2
  exit 1
}
if /usr/bin/find "$app" -iname '*fixture*' -print -quit | /usr/bin/grep -q .; then
  printf 'Fixture code was found in the release app.\n' >&2
  exit 1
fi
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app"
signature_details="$(/usr/bin/codesign --display --verbose=4 "$app" 2>&1)"
/usr/bin/grep -q 'flags=.*runtime' <<<"$signature_details"
entitlements="$(/usr/bin/codesign --display --entitlements :- "$app" 2>/dev/null || true)"
if [[ "$entitlements" == *"com.apple.security.app-sandbox"* ||
      "$entitlements" == *"com.apple.security.get-task-allow"* ]]; then
  printf 'Release app contains a forbidden entitlement.\n' >&2
  exit 1
fi
homeward_verify_dsym "$binary" "$dsym"

SOURCE_SHA="$(git rev-parse HEAD)" \
APP_TREE_SHA="$(homeward_tree_sha256 "$app")" \
DSYM_TREE_SHA="$(homeward_tree_sha256 "$dsym")" \
BINARY_UUID="$(homeward_macho_uuid "$binary")" \
VERSION="$version" \
BUILD="$build" \
/usr/bin/python3 - "$verification_marker" <<'PY'
import json
import os
import sys

evidence = {
    "appTreeSHA256": os.environ["APP_TREE_SHA"],
    "binaryUUID": os.environ["BINARY_UUID"],
    "build": os.environ["BUILD"],
    "dSYMTreeSHA256": os.environ["DSYM_TREE_SHA"],
    "schemaVersion": 1,
    "sourceSHA": os.environ["SOURCE_SHA"],
    "version": os.environ["VERSION"],
}
with open(sys.argv[1], "w", encoding="utf-8") as output:
    json.dump(evidence, output, indent=2, sort_keys=True)
    output.write("\n")
PY

printf 'Homeward verification passed.\n'
