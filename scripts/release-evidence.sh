#!/bin/bash

homeward_tree_sha256() {
  local root="$1"
  (
    cd "$root" || exit 1
    /usr/bin/find . -mindepth 1 -print |
      LC_ALL=C /usr/bin/sort |
      while IFS= read -r relative_path; do
        if [[ -L "$relative_path" ]]; then
          printf 'L %s %s %s\n' \
            "$(/usr/bin/stat -f '%Sp' "$relative_path")" \
            "$relative_path" \
            "$(/usr/bin/readlink "$relative_path")"
        elif [[ -f "$relative_path" ]]; then
          printf 'F %s %s %s\n' \
            "$(/usr/bin/stat -f '%Sp' "$relative_path")" \
            "$(shasum -a 256 "$relative_path" | awk '{print $1}')" \
            "$relative_path"
        elif [[ -d "$relative_path" ]]; then
          printf 'D %s %s\n' \
            "$(/usr/bin/stat -f '%Sp' "$relative_path")" \
            "$relative_path"
        fi
      done
  ) | shasum -a 256 | awk '{print $1}'
}

homeward_macho_uuid() {
  /usr/bin/dwarfdump --uuid "$1" |
    awk 'NR == 1 { print $2 }'
}

homeward_verify_dsym() {
  local binary="$1"
  local dsym="$2"
  local dsym_binary="$dsym/Contents/Resources/DWARF/Homeward"

  [[ -f "$dsym_binary" ]] || {
    printf 'Release dSYM binary is missing: %s\n' "$dsym_binary" >&2
    return 1
  }
  local binary_uuid
  local dsym_uuid
  binary_uuid="$(homeward_macho_uuid "$binary")"
  dsym_uuid="$(homeward_macho_uuid "$dsym_binary")"
  [[ -n "$binary_uuid" && "$binary_uuid" == "$dsym_uuid" ]] || {
    printf 'Release dSYM UUID does not match the app binary.\n' >&2
    return 1
  }
}

homeward_read_release_evidence() {
  local marker="$1"
  local require_ui_tests="$2"

  /usr/bin/python3 - "$marker" "$require_ui_tests" <<'PY'
import json
import re
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    evidence = json.load(source)
expected_keys = {
    "appTreeSHA256",
    "binaryUUID",
    "build",
    "dSYMTreeSHA256",
    "schemaVersion",
    "sourceSHA",
    "uiTestsEnabled",
    "version",
}
if set(evidence) != expected_keys or evidence["schemaVersion"] != 2:
    raise SystemExit("Invalid verified release evidence schema")
if not isinstance(evidence["uiTestsEnabled"], bool):
    raise SystemExit("Invalid UI-test evidence field")
if sys.argv[2] not in {"0", "1"}:
    raise SystemExit("UI-test evidence requirement must be 0 or 1")
if sys.argv[2] == "1" and evidence["uiTestsEnabled"] is not True:
    raise SystemExit("Public release requires UI-enabled verification evidence")
for key in expected_keys - {"schemaVersion", "uiTestsEnabled"}:
    if not isinstance(evidence[key], str) or "\t" in evidence[key]:
        raise SystemExit(f"Invalid verified release evidence field: {key}")
if not re.fullmatch(r"[0-9a-f]{64}", evidence["appTreeSHA256"]):
    raise SystemExit("Invalid app tree hash")
if not re.fullmatch(r"[0-9a-f]{64}", evidence["dSYMTreeSHA256"]):
    raise SystemExit("Invalid dSYM tree hash")
if not re.fullmatch(r"[0-9a-f]{40}", evidence["sourceSHA"]):
    raise SystemExit("Invalid source SHA")
if not re.fullmatch(
    r"[0-9A-F]{8}(?:-[0-9A-F]{4}){3}-[0-9A-F]{12}",
    evidence["binaryUUID"],
):
    raise SystemExit("Invalid binary UUID")
if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", evidence["version"]):
    raise SystemExit("Invalid version")
if not re.fullmatch(r"[1-9][0-9]*", evidence["build"]):
    raise SystemExit("Invalid build")
print(
    "\t".join(
        [
            evidence["sourceSHA"],
            evidence["appTreeSHA256"],
            evidence["binaryUUID"],
            evidence["dSYMTreeSHA256"],
            evidence["version"],
            evidence["build"],
            "true" if evidence["uiTestsEnabled"] else "false",
        ]
    )
)
PY
}
