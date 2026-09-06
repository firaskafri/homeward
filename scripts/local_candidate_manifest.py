#!/usr/bin/env python3
"""Build and validate Homeward local-candidate provenance manifests.

The schema binds package identity to three nested UI verification layers:
general UI tests, journey E2E, and release-configuration E2E. Local candidates
may explicitly record a disabled layer, but enabled layers require canonical
result hashes and release E2E additionally requires the fixed scheme and
configuration. Disabled layers must not retain stale artifact metadata.
"""

import json
import os
import re
import sys
from typing import Mapping, Optional


SCHEMA_VERSION = 2
EXPECTED_KEYS = {
    "appTreeSHA256",
    "architecture",
    "artifact",
    "binaryUUID",
    "build",
    "bundleIdentifier",
    "coverageContractSHA256",
    "dSYMTreeSHA256",
    "dSYMUUID",
    "journeyE2EEnabled",
    "journeyResultSHA256",
    "license",
    "minimumSystemVersion",
    "notarized",
    "releaseE2EConfiguration",
    "releaseE2EEnabled",
    "releaseE2EScheme",
    "releaseResultSHA256",
    "schemaVersion",
    "sha256",
    "signatureMode",
    "size",
    "sourceSHA",
    "swift",
    "uiTestsEnabled",
    "uiResultSHA256",
    "version",
    "xcode",
    "xctestrunSHA256",
}
UUID_PATTERN = re.compile(
    r"[0-9A-F]{8}(?:-[0-9A-F]{4}){3}-[0-9A-F]{12}"
)
SHA256_PATTERN = re.compile(r"[0-9a-f]{64}")


def parse_boolean(environment: Mapping[str, str], name: str) -> bool:
    value = environment[name]
    if value not in {"true", "false"}:
        raise ValueError(f"Invalid boolean environment field: {name}")
    return value == "true"


def parse_optional_value(
    environment: Mapping[str, str],
    name: str,
) -> Optional[str]:
    return environment[name] or None


def build_manifest(environment: Mapping[str, str]) -> dict:
    manifest = {
        "appTreeSHA256": environment["APP_TREE_SHA"],
        "architecture": environment["ARCHITECTURE"],
        "artifact": environment["ARTIFACT"],
        "binaryUUID": environment["BINARY_UUID"],
        "build": environment["BUILD"],
        "bundleIdentifier": environment["BUNDLE_IDENTIFIER"],
        "coverageContractSHA256": parse_optional_value(
            environment,
            "COVERAGE_CONTRACT_SHA256",
        ),
        "dSYMTreeSHA256": environment["DSYM_TREE_SHA"],
        "dSYMUUID": environment["DSYM_UUID"],
        "journeyE2EEnabled": parse_boolean(
            environment,
            "JOURNEY_E2E_ENABLED",
        ),
        "journeyResultSHA256": parse_optional_value(
            environment,
            "JOURNEY_RESULT_SHA256",
        ),
        "license": "All rights reserved",
        "minimumSystemVersion": environment["MINIMUM_SYSTEM_VERSION"],
        "notarized": False,
        "releaseE2EConfiguration": parse_optional_value(
            environment,
            "RELEASE_E2E_CONFIGURATION",
        ),
        "releaseE2EEnabled": parse_boolean(
            environment,
            "RELEASE_E2E_ENABLED",
        ),
        "releaseE2EScheme": parse_optional_value(
            environment,
            "RELEASE_E2E_SCHEME",
        ),
        "releaseResultSHA256": parse_optional_value(
            environment,
            "RELEASE_RESULT_SHA256",
        ),
        "schemaVersion": SCHEMA_VERSION,
        "sha256": environment["CHECKSUM"],
        "signatureMode": environment["SIGNATURE_MODE"],
        "size": int(environment["SIZE"]),
        "sourceSHA": environment["SOURCE_SHA"],
        "swift": environment["SWIFT_VERSION"],
        "uiTestsEnabled": parse_boolean(environment, "UI_TESTS_ENABLED"),
        "uiResultSHA256": parse_optional_value(
            environment,
            "UI_RESULT_SHA256",
        ),
        "version": environment["VERSION"],
        "xcode": environment["XCODE_VERSION"],
        "xctestrunSHA256": parse_optional_value(
            environment,
            "XCTESTRUN_SHA256",
        ),
    }
    validate_manifest(manifest)
    return manifest


def validate_manifest(manifest: dict) -> None:
    if set(manifest) != EXPECTED_KEYS:
        raise ValueError("Invalid local candidate manifest schema")
    if manifest["schemaVersion"] != SCHEMA_VERSION:
        raise ValueError("Invalid local candidate manifest schema version")
    if manifest["signatureMode"] != "ad-hoc":
        raise ValueError("Local candidate signature mode must be ad-hoc")
    if manifest["notarized"] is not False:
        raise ValueError("Local candidates must record notarized false")
    if not re.fullmatch(r"[0-9a-f]{40}", manifest["sourceSHA"]):
        raise ValueError("Invalid source SHA")
    for key in ("appTreeSHA256", "dSYMTreeSHA256", "sha256"):
        if not SHA256_PATTERN.fullmatch(manifest[key]):
            raise ValueError(f"Invalid hash field: {key}")
    if not UUID_PATTERN.fullmatch(manifest["binaryUUID"]):
        raise ValueError("Invalid binary UUID")
    if not UUID_PATTERN.fullmatch(manifest["dSYMUUID"]):
        raise ValueError("Invalid dSYM UUID")
    if manifest["binaryUUID"] != manifest["dSYMUUID"]:
        raise ValueError("Binary and dSYM UUIDs must match")
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", manifest["version"]):
        raise ValueError("Invalid app version")
    if not re.fullmatch(r"[1-9][0-9]*", manifest["build"]):
        raise ValueError("Invalid app build")
    if not manifest["architecture"]:
        raise ValueError("Architecture is required")
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+)+", manifest["minimumSystemVersion"]):
        raise ValueError("Invalid minimum macOS version")
    if not isinstance(manifest["size"], int) or manifest["size"] <= 0:
        raise ValueError("Final DMG size must be positive")
    boolean_keys = (
        "uiTestsEnabled",
        "journeyE2EEnabled",
        "releaseE2EEnabled",
    )
    for key in boolean_keys:
        if not isinstance(manifest[key], bool):
            raise ValueError(f"Invalid boolean evidence field: {key}")
    if manifest["journeyE2EEnabled"] and not manifest["uiTestsEnabled"]:
        raise ValueError("Journey E2E evidence requires UI-test evidence")
    if manifest["releaseE2EEnabled"] and not (
        manifest["uiTestsEnabled"] and manifest["journeyE2EEnabled"]
    ):
        raise ValueError("Release E2E evidence requires UI and journey evidence")

    optional_hashes = (
        ("coverageContractSHA256", manifest["uiTestsEnabled"]),
        ("uiResultSHA256", manifest["uiTestsEnabled"]),
        ("journeyResultSHA256", manifest["journeyE2EEnabled"]),
        ("releaseResultSHA256", manifest["releaseE2EEnabled"]),
        ("xctestrunSHA256", manifest["releaseE2EEnabled"]),
    )
    for key, enabled in optional_hashes:
        value = manifest[key]
        if enabled and (
            not isinstance(value, str)
            or not SHA256_PATTERN.fullmatch(value)
        ):
            raise ValueError(f"Invalid enabled evidence hash: {key}")
        if not enabled and value is not None:
            raise ValueError(f"Disabled evidence hash must be null: {key}")

    if manifest["releaseE2EEnabled"]:
        if manifest["releaseE2EConfiguration"] != "Release":
            raise ValueError(
                "Release E2E configuration must be canonical Release"
            )
        if manifest["releaseE2EScheme"] != "HomewardReleaseE2E":
            raise ValueError(
                "Release E2E scheme must be canonical HomewardReleaseE2E"
            )
    elif (
        manifest["releaseE2EConfiguration"] is not None
        or manifest["releaseE2EScheme"] is not None
    ):
        raise ValueError(
            "Disabled release E2E configuration and scheme must be null"
        )


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(
            "usage: local_candidate_manifest.py OUTPUT_MANIFEST"
        )
    manifest = build_manifest(os.environ)
    with open(sys.argv[1], "w", encoding="utf-8") as output:
        json.dump(manifest, output, indent=2, sort_keys=True)
        output.write("\n")


if __name__ == "__main__":
    main()
