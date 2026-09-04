#!/bin/bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
derived_data="${HOMEWARD_DERIVED_DATA_PATH:-$repository_root/.build/xcode}"
source_app="$derived_data/Build/Products/Release/Homeward.app"
source_dsym="$derived_data/Build/Products/Release/Homeward.app.dSYM"
verification_marker="${HOMEWARD_VERIFICATION_MARKER:-$derived_data/verified-release.json}"
expected_bundle_identifier="com.firaskafri.homeward"
mode="release"
identity=""
team_id=""
notary_profile=""

usage() {
  cat <<'EOF'
Usage:
  package-public-release.sh [--check] \
    --identity "Developer ID Application: Name (TEAMID)" \
    --team-id TEAMID \
    --notary-profile KEYCHAIN_PROFILE

--check validates every prerequisite without signing, packaging, or submitting.
The identity, Team ID, and profile are names only; credentials stay in Keychain.
EOF
}

while (($#)); do
  case "$1" in
    --check)
      mode="check"
      shift
      ;;
    --identity)
      [[ $# -ge 2 ]] || {
        usage >&2
        exit 2
      }
      identity="$2"
      shift 2
      ;;
    --team-id)
      [[ $# -ge 2 ]] || {
        usage >&2
        exit 2
      }
      team_id="$2"
      shift 2
      ;;
    --notary-profile)
      [[ $# -ge 2 ]] || {
        usage >&2
        exit 2
      }
      notary_profile="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

cd "$repository_root"
# shellcheck source=scripts/public-release-gates.sh
source "$repository_root/scripts/public-release-gates.sh"
# shellcheck source=scripts/release-evidence.sh
source "$repository_root/scripts/release-evidence.sh"

required_commands=(
  awk
  codesign
  ditto
  dwarfdump
  file
  find
  git
  grep
  hdiutil
  lipo
  ln
  mkdir
  mktemp
  mv
  python3
  readlink
  rm
  security
  sed
  shasum
  sort
  spctl
  stat
  swift
  tr
  xcodebuild
  xcrun
)
for command in "${required_commands[@]}"; do
  command -v "$command" >/dev/null || {
    printf 'Required release tool is unavailable: %s\n' "$command" >&2
    exit 1
  }
done
[[ -x /usr/libexec/PlistBuddy ]] || {
  printf 'Required release tool is unavailable: %s\n' \
    /usr/libexec/PlistBuddy >&2
  exit 1
}

homeward_require_release_identity "$identity" "$team_id"
homeward_require_notary_profile "$notary_profile"
homeward_require_clean_tree "$repository_root"

[[ -d "$source_app" ]] || {
  printf 'Verified arm64 Release app is missing: %s\n' "$source_app" >&2
  exit 1
}
[[ -d "$source_dsym" ]] || {
  printf 'Release dSYM is missing: %s\n' "$source_dsym" >&2
  exit 1
}
[[ -f "$verification_marker" ]] || {
  printf 'Verification evidence is missing: %s\n' "$verification_marker" >&2
  exit 1
}

source_binary="$source_app/Contents/MacOS/Homeward"
source_plist="$source_app/Contents/Info.plist"
[[ -f "$source_binary" && -f "$source_plist" ]] || {
  printf 'Release app is incomplete.\n' >&2
  exit 1
}

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$source_plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$source_plist")"
bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$source_plist")"
minimum_system_version="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$source_plist")"
architecture="$(/usr/bin/lipo -archs "$source_binary")"
source_sha="$(git rev-parse HEAD)"
release_tag="v$version"

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ &&
   "$build" =~ ^[1-9][0-9]*$ ]] || {
  printf 'Release app version metadata is invalid.\n' >&2
  exit 1
}
[[ "$bundle_identifier" == "$expected_bundle_identifier" ]] || {
  printf 'Unexpected bundle identifier: %s\n' "$bundle_identifier" >&2
  exit 1
}
[[ "$architecture" == "arm64" ]] || {
  printf 'Public release binary must be arm64-only; found %s.\n' "$architecture" >&2
  exit 1
}
[[ "$minimum_system_version" == "15.0" ]] || {
  printf 'Public release requires LSMinimumSystemVersion 15.0; found %s.\n' \
    "$minimum_system_version" >&2
  exit 1
}
binary_build_metadata="$(/usr/bin/xcrun vtool -show-build "$source_binary")"
/usr/bin/grep -Eq 'platform[[:space:]]+MACOS' <<<"$binary_build_metadata" || {
  printf 'Release binary does not declare the macOS platform.\n' >&2
  exit 1
}
/usr/bin/grep -Eq 'minos[[:space:]]+15\.0(\.0)?$' <<<"$binary_build_metadata" || {
  printf 'Release binary does not declare macOS 15.0 as its minimum OS.\n' >&2
  exit 1
}
if /usr/bin/find "$source_app" -iname '*fixture*' -print -quit |
  /usr/bin/grep -q .; then
  printf 'Fixture content was found in the Release app.\n' >&2
  exit 1
fi
homeward_verify_dsym "$source_binary" "$source_dsym"

evidence="$(homeward_read_release_evidence "$verification_marker" 1)"
IFS=$'\t' read -r verified_source_sha verified_app_tree_sha \
  verified_binary_uuid verified_dsym_tree_sha verified_version \
  verified_build verified_ui_tests <<<"$evidence"
[[ "$verified_source_sha" == "$source_sha" &&
   "$verified_app_tree_sha" == "$(homeward_tree_sha256 "$source_app")" &&
   "$verified_binary_uuid" == "$(homeward_macho_uuid "$source_binary")" &&
   "$verified_dsym_tree_sha" == "$(homeward_tree_sha256 "$source_dsym")" &&
   "$verified_version" == "$version" &&
   "$verified_build" == "$build" &&
   "$verified_ui_tests" == "true" ]] || {
  printf 'Release app and dSYM do not match UI-enabled verification evidence.\n' >&2
  exit 1
}

homeward_require_pushed_head "$repository_root"
homeward_require_signed_release_tag "$repository_root" "$release_tag"

identity_inventory="$(/usr/bin/security find-identity -v -p codesigning)"
homeward_require_identity_inventory "$identity" "$team_id" "$identity_inventory"
certificate_sha1="$(
  awk -v expected="\"$identity\"" '
    index($0, expected) { print $2 }
  ' <<<"$identity_inventory"
)"
[[ "$certificate_sha1" =~ ^[0-9A-F]{40}$ ]] || {
  printf 'Could not extract the expected certificate fingerprint.\n' >&2
  exit 1
}

notary_history="$(mktemp "${TMPDIR:-/tmp}/homeward-notary-history.XXXXXX")"
trap 'rm -f "$notary_history"' EXIT
if ! /usr/bin/xcrun notarytool history \
  --keychain-profile "$notary_profile" \
  --output-format json >"$notary_history"; then
  printf 'The named notarytool Keychain profile is unavailable or invalid: %s\n' \
    "$notary_profile" >&2
  exit 1
fi
/usr/bin/python3 - "$notary_history" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    value = json.load(source)
if not isinstance(value, dict):
    raise SystemExit("notarytool history did not return a JSON object")
PY
rm -f "$notary_history"
trap - EXIT

if [[ "$mode" == "check" ]]; then
  printf 'Public release preflight passed for %s (%s), source %s.\n' \
    "$release_tag" "$build" "$source_sha"
  exit 0
fi

artifact_name="Homeward-${version}-arm64"
dist="$repository_root/dist"
dmg_name="${artifact_name}.dmg"
checksum_name="${dmg_name}.sha256"
manifest_name="${artifact_name}.manifest.json"
dsym_name="${artifact_name}.dSYM.zip"
notarization_name="${artifact_name}.notarization.json"
for output in \
  "$dist/$dmg_name" \
  "$dist/$checksum_name" \
  "$dist/$manifest_name" \
  "$dist/$dsym_name" \
  "$dist/$notarization_name"; do
  [[ ! -e "$output" ]] || {
    printf 'Refusing to overwrite existing release output: %s\n' "$output" >&2
    exit 1
  }
done

staging="$(mktemp -d "${TMPDIR:-/tmp}/homeward-public-release.XXXXXX")"
image_root="$staging/image"
output_root="$staging/output"
staged_app="$image_root/Homeward.app"
staged_binary="$staged_app/Contents/MacOS/Homeward"
temporary_dmg="$output_root/$dmg_name"
entitlements_file="$staging/entitlements.plist"
trap 'rm -rf "$staging"' EXIT
mkdir -p "$image_root" "$output_root"
/usr/bin/ditto "$source_app" "$staged_app"
[[ "$(homeward_tree_sha256 "$staged_app")" == "$verified_app_tree_sha" ]] || {
  printf 'Staged app differs from the verified Release app.\n' >&2
  exit 1
}
ln -s /Applications "$image_root/Applications"

declare -a nested_macho=()
while IFS= read -r -d '' candidate; do
  [[ "$candidate" == "$staged_binary" ]] && continue
  if /usr/bin/file -b "$candidate" | /usr/bin/grep -q '^Mach-O '; then
    nested_macho+=("$candidate")
  fi
done < <(/usr/bin/find "$staged_app" -type f -print0)

declare -a nested_bundles=()
while IFS= read -r -d '' candidate; do
  nested_bundles+=("$candidate")
done < <(
  /usr/bin/find "$staged_app" -depth -type d \
    \( -name '*.app' -o -name '*.appex' -o -name '*.xpc' -o -name '*.framework' \) \
    ! -path "$staged_app" -print0
)

for candidate in "${nested_macho[@]}"; do
  /usr/bin/codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$identity" \
    "$candidate"
done
for candidate in "${nested_bundles[@]}"; do
  /usr/bin/codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$identity" \
    "$candidate"
done
/usr/bin/codesign \
  --force \
  --options runtime \
  --timestamp \
  --sign "$identity" \
  "$staged_app"

verify_signed_code() {
  local target="$1"
  local require_bundle_id="${2:-}"
  local details
  local authority
  local signed_team

  /usr/bin/codesign --verify --strict --verbose=2 "$target"
  details="$(/usr/bin/codesign --display --verbose=4 "$target" 2>&1)"
  authority="$(awk -F= '/^Authority=/{ print $2; exit }' <<<"$details")"
  signed_team="$(awk -F= '/^TeamIdentifier=/{ print $2; exit }' <<<"$details")"
  [[ "$authority" == "$identity" ]] || {
    printf 'Unexpected signing authority for %s: %s\n' "$target" "$authority" >&2
    return 1
  }
  [[ "$signed_team" == "$team_id" ]] || {
    printf 'Unexpected signing team for %s: %s\n' "$target" "$signed_team" >&2
    return 1
  }
  /usr/bin/grep -q 'flags=.*runtime' <<<"$details" || {
    printf 'Hardened Runtime is missing from %s.\n' "$target" >&2
    return 1
  }
  /usr/bin/grep -Eq '^Timestamp=.+$' <<<"$details" || {
    printf 'Secure timestamp is missing from %s.\n' "$target" >&2
    return 1
  }
  if [[ -n "$require_bundle_id" ]]; then
    /usr/bin/grep -Fxq "Identifier=$require_bundle_id" <<<"$details" || {
      printf 'Signed bundle identifier is incorrect for %s.\n' "$target" >&2
      return 1
    }
  fi

  : >"$entitlements_file"
  /usr/bin/codesign --display --entitlements :- "$target" \
    >"$entitlements_file" 2>/dev/null || true
  /usr/bin/python3 - "$entitlements_file" "$target" <<'PY'
import plistlib
import sys

path, target = sys.argv[1:]
with open(path, "rb") as source:
    payload = source.read()
if not payload:
    raise SystemExit(0)
try:
    entitlements = plistlib.loads(payload)
except Exception as error:
    raise SystemExit(f"Could not parse entitlements for {target}: {error}")
if not isinstance(entitlements, dict):
    raise SystemExit(f"Entitlements for {target} are not a dictionary")
allowed = set()
unexpected = sorted(set(entitlements) - allowed)
if unexpected:
    raise SystemExit(
        f"Unexpected entitlement(s) for {target}: {', '.join(unexpected)}"
    )
PY
}

for candidate in "${nested_macho[@]}"; do
  verify_signed_code "$candidate"
done
for candidate in "${nested_bundles[@]}"; do
  verify_signed_code "$candidate"
done
verify_signed_code "$staged_app" "$expected_bundle_identifier"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$staged_app"

signed_app_details="$(/usr/bin/codesign --display --verbose=4 "$staged_app" 2>&1)"
cdhash="$(awk -F= '/^CDHash=/{ print $2; exit }' <<<"$signed_app_details")"
[[ "$cdhash" =~ ^[0-9a-fA-F]+$ ]] || {
  printf 'Could not read the signed app CDHash.\n' >&2
  exit 1
}
signed_app_tree_sha="$(homeward_tree_sha256 "$staged_app")"
binary_uuid="$(homeward_macho_uuid "$staged_binary")"
dsym_binary="$source_dsym/Contents/Resources/DWARF/Homeward"
dsym_uuid="$(homeward_macho_uuid "$dsym_binary")"
[[ "$binary_uuid" == "$verified_binary_uuid" &&
   "$dsym_uuid" == "$binary_uuid" ]] || {
  printf 'Signed binary and dSYM UUIDs do not match verified evidence.\n' >&2
  exit 1
}

/usr/bin/hdiutil create \
  -quiet \
  -fs HFS+ \
  -format UDZO \
  -volname "Homeward $version" \
  -srcfolder "$image_root" \
  "$temporary_dmg"
/usr/bin/codesign \
  --force \
  --timestamp \
  --sign "$identity" \
  "$temporary_dmg"
/usr/bin/codesign --verify --strict --verbose=2 "$temporary_dmg"
dmg_signature="$(/usr/bin/codesign --display --verbose=4 "$temporary_dmg" 2>&1)"
/usr/bin/grep -Fxq "Authority=$identity" <<<"$dmg_signature" || {
  printf 'DMG signing authority does not match the requested identity.\n' >&2
  exit 1
}
/usr/bin/grep -Fxq "TeamIdentifier=$team_id" <<<"$dmg_signature" || {
  printf 'DMG signing Team ID does not match the requested team.\n' >&2
  exit 1
}
/usr/bin/grep -Eq '^Timestamp=.+$' <<<"$dmg_signature" || {
  printf 'DMG secure timestamp is missing.\n' >&2
  exit 1
}

mkdir -p "$dist"
notarization_json="$dist/$notarization_name"
if ! /usr/bin/xcrun notarytool submit "$temporary_dmg" \
  --keychain-profile "$notary_profile" \
  --wait \
  --output-format json >"$notarization_json"; then
  printf 'Notarization submission failed; result retained at %s.\n' \
    "$notarization_json" >&2
  exit 1
fi
notarization_result="$(
  /usr/bin/python3 - "$notarization_json" <<'PY'
import json
import re
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    result = json.load(source)
status = result.get("status")
submission_id = result.get("id")
if status != "Accepted":
    raise SystemExit(f"Notarization status is not Accepted: {status!r}")
if not isinstance(submission_id, str) or not re.fullmatch(
    r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}",
    submission_id,
):
    raise SystemExit("Notarization result has no valid submission ID")
print(f"{status}\t{submission_id}")
PY
)" || {
  printf 'Notarization was not accepted; result retained at %s.\n' \
    "$notarization_json" >&2
  exit 1
}
IFS=$'\t' read -r notarization_status notarization_id <<<"$notarization_result"

/usr/bin/xcrun stapler staple "$temporary_dmg"
/usr/bin/xcrun stapler validate "$temporary_dmg"
/usr/sbin/spctl \
  --assess \
  --type open \
  --context context:primary-signature \
  --verbose=4 \
  "$temporary_dmg"

checksum="$(/usr/bin/shasum -a 256 "$temporary_dmg" | awk '{print $1}')"
size="$(/usr/bin/stat -f '%z' "$temporary_dmg")"
xcode_version="$(/usr/bin/xcodebuild -version | tr '\n' ' ' | sed 's/ $//')"
swift_version="$(/usr/bin/swift --version 2>&1 | sed -n '1p')"
notarytool_version="$(/usr/bin/xcrun notarytool --version)"

ARTIFACT="$dmg_name" \
ARCHITECTURE="$architecture" \
BINARY_UUID="$binary_uuid" \
BUILD="$build" \
BUNDLE_IDENTIFIER="$bundle_identifier" \
CDHASH="$cdhash" \
CERTIFICATE="$identity" \
CERTIFICATE_SHA1="$certificate_sha1" \
CHECKSUM="$checksum" \
DSYM_UUID="$dsym_uuid" \
MINIMUM_SYSTEM_VERSION="$minimum_system_version" \
NOTARIZATION_ID="$notarization_id" \
NOTARIZATION_STATUS="$notarization_status" \
NOTARYTOOL_VERSION="$notarytool_version" \
SIGNED_APP_TREE_SHA="$signed_app_tree_sha" \
SIZE="$size" \
SOURCE_SHA="$source_sha" \
SWIFT_VERSION="$swift_version" \
TAG="$release_tag" \
TEAM_ID="$team_id" \
VERIFIED_APP_TREE_SHA="$verified_app_tree_sha" \
VERIFIED_DSYM_TREE_SHA="$verified_dsym_tree_sha" \
VERSION="$version" \
XCODE_VERSION="$xcode_version" \
/usr/bin/python3 - "$output_root/$manifest_name" <<'PY'
import json
import os
import sys

manifest = {
    "architecture": os.environ["ARCHITECTURE"],
    "artifact": os.environ["ARTIFACT"],
    "binaryUUID": os.environ["BINARY_UUID"],
    "build": os.environ["BUILD"],
    "bundleIdentifier": os.environ["BUNDLE_IDENTIFIER"],
    "certificate": os.environ["CERTIFICATE"],
    "certificateSHA1": os.environ["CERTIFICATE_SHA1"],
    "cdHash": os.environ["CDHASH"],
    "dSYMTreeSHA256": os.environ["VERIFIED_DSYM_TREE_SHA"],
    "dSYMUUID": os.environ["DSYM_UUID"],
    "license": "All rights reserved",
    "minimumSystemVersion": os.environ["MINIMUM_SYSTEM_VERSION"],
    "notarization": {
        "id": os.environ["NOTARIZATION_ID"],
        "status": os.environ["NOTARIZATION_STATUS"],
    },
    "schemaVersion": 1,
    "sha256": os.environ["CHECKSUM"],
    "signedAppTreeSHA256": os.environ["SIGNED_APP_TREE_SHA"],
    "size": int(os.environ["SIZE"]),
    "sourceSHA": os.environ["SOURCE_SHA"],
    "swift": os.environ["SWIFT_VERSION"],
    "tag": os.environ["TAG"],
    "teamID": os.environ["TEAM_ID"],
    "verifiedAppTreeSHA256": os.environ["VERIFIED_APP_TREE_SHA"],
    "version": os.environ["VERSION"],
    "xcode": os.environ["XCODE_VERSION"],
    "notarytool": os.environ["NOTARYTOOL_VERSION"],
}
with open(sys.argv[1], "w", encoding="utf-8") as output:
    json.dump(manifest, output, indent=2, sort_keys=True)
    output.write("\n")
PY

(
  cd "$output_root"
  printf '%s  %s\n' "$checksum" "$dmg_name" >"$checksum_name"
)
/usr/bin/ditto \
  -c -k --keepParent \
  "$source_dsym" \
  "$output_root/$dsym_name"
mv "$temporary_dmg" "$dist/$dmg_name"
mv "$output_root/$checksum_name" "$dist/$checksum_name"
mv "$output_root/$manifest_name" "$dist/$manifest_name"
mv "$output_root/$dsym_name" "$dist/$dsym_name"

printf 'Created notarized public release artifacts for %s at %s.\n' \
  "$release_tag" "$dist"
printf 'SHA-256 %s\n' "$checksum"
