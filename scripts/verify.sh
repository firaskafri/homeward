#!/bin/bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
derived_data="$repository_root/.build/xcode"
project="$repository_root/Homeward.xcodeproj"
destination="platform=macOS,arch=arm64"

cd "$repository_root"

command -v xcodegen >/dev/null || {
  printf 'xcodegen is required. Install it with: brew install xcodegen\n' >&2
  exit 1
}

required_xcodegen_version="2.46.0"
actual_xcodegen_version="$(xcodegen version | awk '{print $2}')"
IFS=. read -r actual_major actual_minor actual_patch <<<"$actual_xcodegen_version"
if (( actual_major < 2 || (actual_major == 2 && actual_minor < 46) )); then
  printf 'XcodeGen %s is required; found %s.\n' \
    "$required_xcodegen_version" "$actual_xcodegen_version" >&2
  exit 1
fi

project_file="$project/project.pbxproj"
before_generation="$(shasum -a 256 "$project_file" | awk '{print $1}')"
xcodegen generate
after_generation="$(shasum -a 256 "$project_file" | awk '{print $1}')"
[[ "$before_generation" == "$after_generation" ]] || {
  printf 'Homeward.xcodeproj was stale. Regenerate and review it before verification.\n' >&2
  exit 1
}
xcodebuild \
  -project "$project" \
  -scheme Homeward \
  -destination "$destination" \
  -derivedDataPath "$derived_data" \
  clean
swift scripts/check-test-docs.swift
swift test

xcodebuild \
  -project "$project" \
  -scheme Homeward \
  -destination "$destination" \
  -derivedDataPath "$derived_data" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  test

if [[ "${RUN_UI_TESTS:-1}" == "1" ]]; then
  xcodebuild \
    -project "$project" \
    -scheme HomewardUI \
    -destination "$destination" \
    -derivedDataPath "$derived_data" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY=- \
    DEVELOPMENT_TEAM= \
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

[[ -d "$app" ]] || {
  printf 'Release app was not produced: %s\n' "$app" >&2
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
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")" == "0.1.0" ]] || {
  printf 'Release app version is incorrect.\n' >&2
  exit 1
}
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")" == "1" ]] || {
  printf 'Release build number is incorrect.\n' >&2
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

printf 'Homeward verification passed.\n'
