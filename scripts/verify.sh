#!/bin/bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
derived_data="${HOMEWARD_DERIVED_DATA_PATH:-$repository_root/.build/xcode}"
project="$repository_root/Homeward.xcodeproj"
destination="platform=macOS,arch=arm64"
verification_marker="${HOMEWARD_VERIFICATION_MARKER:-$derived_data/verified-release.json}"
native_test_storage="$derived_data/native-test-storage"
run_ui_tests="${RUN_UI_TESTS:-1}"
run_journey_e2e="${RUN_JOURNEY_E2E:-$run_ui_tests}"
run_release_e2e="${RUN_RELEASE_E2E:-$run_ui_tests}"
result_directory="$derived_data/TestResults"
ui_result="$result_directory/HomewardUI.xcresult"
journey_result="$result_directory/HomewardJourneyE2E.xcresult"
release_e2e_result="$result_directory/HomewardReleaseE2E.xcresult"

cd "$repository_root"
rm -f "$verification_marker"
rm -rf "$native_test_storage"
rm -rf "$result_directory"
mkdir -p "$result_directory"
# shellcheck source=scripts/release-evidence.sh
source "$repository_root/scripts/release-evidence.sh"

[[ "$run_ui_tests" == "0" || "$run_ui_tests" == "1" ]] || {
  printf 'RUN_UI_TESTS must be 0 or 1.\n' >&2
  exit 1
}
[[ "$run_journey_e2e" == "0" || "$run_journey_e2e" == "1" ]] || {
  printf 'RUN_JOURNEY_E2E must be 0 or 1.\n' >&2
  exit 1
}
[[ "$run_release_e2e" == "0" || "$run_release_e2e" == "1" ]] || {
  printf 'RUN_RELEASE_E2E must be 0 or 1.\n' >&2
  exit 1
}
[[ "$run_journey_e2e" == "0" || "$run_ui_tests" == "1" ]] || {
  printf 'RUN_JOURNEY_E2E=1 requires RUN_UI_TESTS=1.\n' >&2
  exit 1
}
[[ "$run_release_e2e" == "0"
   || ( "$run_ui_tests" == "1" && "$run_journey_e2e" == "1" ) ]] || {
  printf 'RUN_RELEASE_E2E=1 requires UI and journey E2E tests.\n' >&2
  exit 1
}

[[ "$(uname -m)" == "arm64" ]] || {
  printf 'Homeward verification requires an Apple Silicon host.\n' >&2
  exit 1
}

stop_repository_processes() {
  local test_name="$1"
  local pattern="$repository_root/.*/${test_name}.app/Contents/MacOS/${test_name}"
  local process_ids
  process_ids="$(pgrep -f "$pattern" || true)"
  if [[ -n "$process_ids" ]]; then
    printf 'Stopping stale %s test instance(s): %s\n' \
      "$test_name" "$process_ids"
    while IFS= read -r process_id; do
      if ! kill "$process_id" 2>/dev/null; then
        continue
      fi
      for _ in {1..50}; do
        kill -0 "$process_id" 2>/dev/null || break
        sleep 0.1
      done
      if kill -0 "$process_id" 2>/dev/null; then
        printf '%s test instance did not terminate: %s\n' \
          "$test_name" "$process_id" >&2
        return 1
      fi
    done <<<"$process_ids"
  fi
}

stop_repository_test_instances() {
  stop_repository_processes "Homeward"
  if pgrep -x Homeward >/dev/null; then
    printf 'Quit any installed Homeward app before running native tests.\n' >&2
    exit 1
  fi

  local test_name
  for test_name in HomewardTestShell HomewardFixture; do
    stop_repository_processes "$test_name"
    if pgrep -x "$test_name" >/dev/null; then
      printf 'Unexpected %s instance is running outside this repository.\n' \
        "$test_name" >&2
      exit 1
    fi
  done
}

cleanup_verification() {
  local status=$?
  rm -rf "$native_test_storage"
  stop_repository_processes "Homeward" || true
  stop_repository_processes "HomewardTestShell" || true
  stop_repository_processes "HomewardFixture" || true
  return "$status"
}

trap cleanup_verification EXIT

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
PYTHONDONTWRITEBYTECODE=1 \
  /usr/bin/python3 -m unittest \
    scripts/test_local_candidate_manifest.py \
    scripts/test_validate_release_coverage.py \
    scripts/test_validate_xcresult.py \
    scripts/test_validate_xctestrun.py
/usr/bin/python3 scripts/validate_release_coverage.py
./scripts/test-public-release-gates.sh
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

if [[ "$run_ui_tests" == "1" ]]; then
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
    -resultBundlePath "$ui_result" \
    test
  /usr/bin/python3 \
    "$repository_root/scripts/validate_xcresult.py" \
    "$repository_root/scripts/release_coverage_contract.json" \
    ui \
    "$ui_result"
else
  printf 'Skipping UI automation because RUN_UI_TESTS=%s.\n' \
    "$run_ui_tests"
fi

if [[ "$run_journey_e2e" == "1" ]]; then
  stop_repository_test_instances
  xcodebuild \
    -project "$project" \
    -scheme HomewardJourneyE2E \
    -configuration Release \
    -destination "$destination" \
    -derivedDataPath "$derived_data" \
    -parallel-testing-enabled NO \
    -resultBundlePath "$journey_result" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY=- \
    DEVELOPMENT_TEAM= \
    test
  /usr/bin/python3 \
    "$repository_root/scripts/validate_xcresult.py" \
    "$repository_root/scripts/release_coverage_contract.json" \
    journey \
    "$journey_result"
else
  printf 'Skipping shell journey automation because RUN_JOURNEY_E2E=%s.\n' \
    "$run_journey_e2e"
  xcodebuild \
    -project "$project" \
    -scheme HomewardJourneyE2E \
    -configuration Release \
    -destination "$destination" \
    -derivedDataPath "$derived_data" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY=- \
    DEVELOPMENT_TEAM= \
    build-for-testing
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
  -scheme HomewardReleaseE2E \
  -configuration Release \
  -destination "$destination" \
  -derivedDataPath "$derived_data" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  build-for-testing

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
release_xctestrun="${release_xctestrun_candidates[0]}"
/usr/bin/python3 \
  "$repository_root/scripts/validate_xctestrun.py" \
  "$release_xctestrun"

if [[ "$run_release_e2e" == "1" ]]; then
  stop_repository_test_instances
  xcodebuild \
    -xctestrun "$release_xctestrun" \
    -destination "$destination" \
    -parallel-testing-enabled NO \
    -resultBundlePath "$release_e2e_result" \
    test-without-building
  /usr/bin/python3 \
    "$repository_root/scripts/validate_xcresult.py" \
    "$repository_root/scripts/release_coverage_contract.json" \
    releaseLifecycle \
    "$release_e2e_result"
else
  printf 'Skipping Release lifecycle automation because RUN_RELEASE_E2E=%s.\n' \
    "$run_release_e2e"
fi
stop_repository_test_instances

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
if /usr/bin/find "$app" \
  \( -iname '*fixture*' -o -iname '*testshell*' \) \
  -print -quit | /usr/bin/grep -q .; then
  printf 'Test fixture or shell content was found in the release app.\n' >&2
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

coverage_contract_sha=""
ui_result_sha=""
journey_result_sha=""
release_result_sha=""
release_xctestrun_sha=""
release_e2e_configuration=""
release_e2e_scheme=""
if [[ "$run_ui_tests" == "1" ]]; then
  coverage_contract_sha="$(
    shasum -a 256 "$repository_root/scripts/release_coverage_contract.json" |
      awk '{print $1}'
  )"
  ui_result_sha="$(homeward_tree_sha256 "$ui_result")"
fi
if [[ "$run_journey_e2e" == "1" ]]; then
  journey_result_sha="$(homeward_tree_sha256 "$journey_result")"
fi
if [[ "$run_release_e2e" == "1" ]]; then
  release_result_sha="$(homeward_tree_sha256 "$release_e2e_result")"
  release_xctestrun_sha="$(
    shasum -a 256 "$release_xctestrun" | awk '{print $1}'
  )"
  release_e2e_configuration="Release"
  release_e2e_scheme="HomewardReleaseE2E"
fi

if [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
  printf '%s\n' \
    'Homeward verification passed; release evidence omitted because the source tree is dirty.'
  exit 0
fi

SOURCE_SHA="$(git rev-parse HEAD)" \
APP_TREE_SHA="$(homeward_tree_sha256 "$app")" \
DSYM_TREE_SHA="$(homeward_tree_sha256 "$dsym")" \
BINARY_UUID="$(homeward_macho_uuid "$binary")" \
VERSION="$version" \
BUILD="$build" \
UI_TESTS_ENABLED="$run_ui_tests" \
UI_RESULT_SHA256="$ui_result_sha" \
JOURNEY_E2E_ENABLED="$run_journey_e2e" \
RELEASE_E2E_ENABLED="$run_release_e2e" \
COVERAGE_CONTRACT_SHA256="$coverage_contract_sha" \
JOURNEY_RESULT_SHA256="$journey_result_sha" \
RELEASE_RESULT_SHA256="$release_result_sha" \
XCTESTRUN_SHA256="$release_xctestrun_sha" \
RELEASE_E2E_CONFIGURATION="$release_e2e_configuration" \
RELEASE_E2E_SCHEME="$release_e2e_scheme" \
/usr/bin/python3 - "$verification_marker" <<'PY'
import json
import os
import sys

def optional(name):
    return os.environ[name] or None

evidence = {
    "appTreeSHA256": os.environ["APP_TREE_SHA"],
    "binaryUUID": os.environ["BINARY_UUID"],
    "build": os.environ["BUILD"],
    "coverageContractSHA256": optional("COVERAGE_CONTRACT_SHA256"),
    "dSYMTreeSHA256": os.environ["DSYM_TREE_SHA"],
    "journeyE2EEnabled": os.environ["JOURNEY_E2E_ENABLED"] == "1",
    "journeyResultSHA256": optional("JOURNEY_RESULT_SHA256"),
    "releaseE2EConfiguration": optional("RELEASE_E2E_CONFIGURATION"),
    "releaseE2EEnabled": os.environ["RELEASE_E2E_ENABLED"] == "1",
    "releaseE2EScheme": optional("RELEASE_E2E_SCHEME"),
    "releaseResultSHA256": optional("RELEASE_RESULT_SHA256"),
    "schemaVersion": 3,
    "sourceSHA": os.environ["SOURCE_SHA"],
    "uiTestsEnabled": os.environ["UI_TESTS_ENABLED"] == "1",
    "uiResultSHA256": optional("UI_RESULT_SHA256"),
    "version": os.environ["VERSION"],
    "xctestrunSHA256": optional("XCTESTRUN_SHA256"),
}
temporary = sys.argv[1] + ".tmp"
with open(temporary, "w", encoding="utf-8") as output:
    json.dump(evidence, output, indent=2, sort_keys=True)
    output.write("\n")
os.replace(temporary, sys.argv[1])
PY

printf 'Homeward verification passed.\n'
