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

homeward_verify_tree_evidence() {
  local path="$1"
  local expected_hash="$2"
  local label="$3"
  [[ -d "$path" ]] || {
    printf '%s is missing: %s\n' "$label" "$path" >&2
    return 1
  }
  [[ "$(homeward_tree_sha256 "$path")" == "$expected_hash" ]] || {
    printf '%s does not match verification evidence.\n' "$label" >&2
    return 1
  }
}

homeward_verify_file_evidence() {
  local path="$1"
  local expected_hash="$2"
  local label="$3"
  [[ -f "$path" ]] || {
    printf '%s is missing: %s\n' "$label" "$path" >&2
    return 1
  }
  [[ "$(shasum -a 256 "$path" | awk '{print $1}')" == "$expected_hash" ]] || {
    printf '%s does not match verification evidence.\n' "$label" >&2
    return 1
  }
}

homeward_read_release_evidence() {
  local marker="$1"
  local require_public_ui_evidence="$2"

  /usr/bin/python3 - "$marker" "$require_public_ui_evidence" <<'PY'
import json
import re
import shlex
import sys


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate release evidence field: {key}")
        result[key] = value
    return result


try:
    with open(sys.argv[1], encoding="utf-8") as source:
        evidence = json.load(source, object_pairs_hook=unique_object)
except (OSError, json.JSONDecodeError, ValueError) as error:
    raise SystemExit(f"Invalid verified release evidence JSON: {error}")

expected_keys = {
    "appTreeSHA256",
    "binaryUUID",
    "build",
    "coverageContractSHA256",
    "dSYMTreeSHA256",
    "journeyE2EEnabled",
    "journeyResultSHA256",
    "releaseE2EConfiguration",
    "releaseE2EEnabled",
    "releaseE2EScheme",
    "releaseResultSHA256",
    "schemaVersion",
    "sourceSHA",
    "uiTestsEnabled",
    "uiResultSHA256",
    "version",
    "xctestrunSHA256",
}
if (
    not isinstance(evidence, dict)
    or set(evidence) != expected_keys
    or type(evidence["schemaVersion"]) is not int
    or evidence["schemaVersion"] != 3
):
    raise SystemExit("Invalid verified release evidence schema")
boolean_keys = {
    "uiTestsEnabled",
    "journeyE2EEnabled",
    "releaseE2EEnabled",
}
for key in boolean_keys:
    if not isinstance(evidence[key], bool):
        raise SystemExit(f"Invalid boolean release evidence field: {key}")
if evidence["journeyE2EEnabled"] and not evidence["uiTestsEnabled"]:
    raise SystemExit("Journey E2E evidence requires UI-test evidence")
if evidence["releaseE2EEnabled"] and not (
    evidence["uiTestsEnabled"] and evidence["journeyE2EEnabled"]
):
    raise SystemExit("Release E2E evidence requires UI and journey evidence")
if sys.argv[2] not in {"0", "1"}:
    raise SystemExit("Public UI evidence requirement must be 0 or 1")
if sys.argv[2] == "1" and not all(evidence[key] for key in boolean_keys):
    raise SystemExit("Public release requires all UI evidence layers")

string_keys = {
    "appTreeSHA256",
    "binaryUUID",
    "build",
    "dSYMTreeSHA256",
    "sourceSHA",
    "version",
}
for key in string_keys:
    if not isinstance(evidence[key], str) or any(
        character in evidence[key] for character in "\0\r\n"
    ):
        raise SystemExit(f"Invalid verified release evidence field: {key}")

sha256_pattern = re.compile(r"[0-9a-f]{64}")
if not sha256_pattern.fullmatch(evidence["appTreeSHA256"]):
    raise SystemExit("Invalid app tree hash")
if not sha256_pattern.fullmatch(evidence["dSYMTreeSHA256"]):
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


def validate_optional_hash(name, enabled):
    value = evidence[name]
    if enabled:
        if not isinstance(value, str) or not sha256_pattern.fullmatch(value):
            raise SystemExit(f"Invalid enabled release evidence hash: {name}")
    elif value is not None:
        raise SystemExit(f"Disabled release evidence hash must be null: {name}")


validate_optional_hash(
    "coverageContractSHA256",
    evidence["uiTestsEnabled"],
)
validate_optional_hash(
    "uiResultSHA256",
    evidence["uiTestsEnabled"],
)
validate_optional_hash(
    "journeyResultSHA256",
    evidence["journeyE2EEnabled"],
)
for release_hash in ("releaseResultSHA256", "xctestrunSHA256"):
    validate_optional_hash(release_hash, evidence["releaseE2EEnabled"])

if evidence["releaseE2EEnabled"]:
    if evidence["releaseE2EConfiguration"] != "Release":
        raise SystemExit(
            "Release E2E configuration must be canonical Release"
        )
    if evidence["releaseE2EScheme"] != "HomewardReleaseE2E":
        raise SystemExit(
            "Release E2E scheme must be canonical HomewardReleaseE2E"
        )
elif (
    evidence["releaseE2EConfiguration"] is not None
    or evidence["releaseE2EScheme"] is not None
):
    raise SystemExit("Disabled release E2E configuration and scheme must be null")

assignments = {
    "verified_source_sha": evidence["sourceSHA"],
    "verified_app_tree_sha": evidence["appTreeSHA256"],
    "verified_binary_uuid": evidence["binaryUUID"],
    "verified_dsym_tree_sha": evidence["dSYMTreeSHA256"],
    "verified_version": evidence["version"],
    "verified_build": evidence["build"],
    "verified_ui_tests": str(evidence["uiTestsEnabled"]).lower(),
    "verified_ui_result_sha256": evidence["uiResultSHA256"] or "",
    "verified_journey_e2e": str(evidence["journeyE2EEnabled"]).lower(),
    "verified_release_e2e": str(evidence["releaseE2EEnabled"]).lower(),
    "verified_release_e2e_configuration": (
        evidence["releaseE2EConfiguration"] or ""
    ),
    "verified_release_e2e_scheme": evidence["releaseE2EScheme"] or "",
    "verified_coverage_contract_sha256": (
        evidence["coverageContractSHA256"] or ""
    ),
    "verified_journey_result_sha256": (
        evidence["journeyResultSHA256"] or ""
    ),
    "verified_release_result_sha256": (
        evidence["releaseResultSHA256"] or ""
    ),
    "verified_xctestrun_sha256": evidence["xctestrunSHA256"] or "",
}
for name, value in assignments.items():
    print(f"{name}={shlex.quote(value)}")
PY
}
