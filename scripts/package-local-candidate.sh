#!/bin/bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
derived_data="$repository_root/.build/xcode"
app="$derived_data/Build/Products/Release/Homeward.app"
dist="$repository_root/dist"

cd "$repository_root"

if [[ "${ALLOW_DIRTY:-0}" != "1" ]] && [[ -n "$(git status --porcelain)" ]]; then
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

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
source_sha="$(git rev-parse HEAD)"
artifact_name="Homeward-${version}-build.${build}-local-arm64"
staging="$(mktemp -d "${TMPDIR:-/tmp}/homeward-release.XXXXXX")"
temporary_dmg="${TMPDIR:-/tmp}/${artifact_name}.$$.dmg"
trap 'rm -rf "$staging"; rm -f "$temporary_dmg"' EXIT

mkdir -p "$dist"
/usr/bin/ditto "$app" "$staging/Homeward.app"
ln -s /Applications "$staging/Applications"

/usr/bin/hdiutil create \
  -quiet \
  -fs HFS+ \
  -format UDZO \
  -volname Homeward \
  -srcfolder "$staging" \
  "$temporary_dmg"
mv "$temporary_dmg" "$dist/${artifact_name}.dmg"

checksum="$(shasum -a 256 "$dist/${artifact_name}.dmg" | awk '{print $1}')"
size="$(stat -f '%z' "$dist/${artifact_name}.dmg")"
signature="$(/usr/bin/codesign --display --verbose=1 "$app" 2>&1 |
  awk -F= '/^Signature=/{print $2}')"
xcode_version="$(xcodebuild -version | tr '\n' ' ' | sed 's/ $//')"
swift_version="$(swift --version 2>&1 | sed -n '1p')"

cat >"$dist/${artifact_name}.manifest.json" <<EOF
{
  "artifact": "${artifact_name}.dmg",
  "build": "${build}",
  "bundleIdentifier": "com.firaskafri.homeward",
  "minimumSystemVersion": "15.0",
  "architecture": "arm64",
  "sha256": "${checksum}",
  "signature": "${signature}",
  "size": ${size},
  "sourceSHA": "${source_sha}",
  "swift": "${swift_version}",
  "version": "${version}",
  "xcode": "${xcode_version}"
}
EOF

shasum -a 256 "$dist/${artifact_name}.dmg" \
  >"$dist/${artifact_name}.dmg.sha256"

if [[ -d "$derived_data/Build/Products/Release/Homeward.app.dSYM" ]]; then
  /usr/bin/ditto \
    -c -k --keepParent \
    "$derived_data/Build/Products/Release/Homeward.app.dSYM" \
    "$dist/${artifact_name}.dSYM.zip"
fi

printf 'Created %s\n' "$dist/${artifact_name}.dmg"
printf 'SHA-256 %s\n' "$checksum"
