#!/usr/bin/env python3
"""Build and validate Homeward local-candidate provenance manifests."""

import json
import os
import re
import sys
from typing import Mapping


SCHEMA_VERSION = 1
EXPECTED_KEYS = {
    "appTreeSHA256",
    "architecture",
    "artifact",
    "binaryUUID",
    "build",
    "bundleIdentifier",
    "dSYMTreeSHA256",
    "dSYMUUID",
    "license",
    "minimumSystemVersion",
    "notarized",
    "schemaVersion",
    "sha256",
    "signatureMode",
    "size",
    "sourceSHA",
    "swift",
    "uiTestsEnabled",
    "version",
    "xcode",
}
UUID_PATTERN = re.compile(
    r"[0-9A-F]{8}(?:-[0-9A-F]{4}){3}-[0-9A-F]{12}"
)


def build_manifest(environment: Mapping[str, str]) -> dict:
    manifest = {
        "appTreeSHA256": environment["APP_TREE_SHA"],
        "architecture": environment["ARCHITECTURE"],
        "artifact": environment["ARTIFACT"],
        "binaryUUID": environment["BINARY_UUID"],
        "build": environment["BUILD"],
        "bundleIdentifier": environment["BUNDLE_IDENTIFIER"],
        "dSYMTreeSHA256": environment["DSYM_TREE_SHA"],
        "dSYMUUID": environment["DSYM_UUID"],
        "license": "All rights reserved",
        "minimumSystemVersion": environment["MINIMUM_SYSTEM_VERSION"],
        "notarized": False,
        "schemaVersion": SCHEMA_VERSION,
        "sha256": environment["CHECKSUM"],
        "signatureMode": environment["SIGNATURE_MODE"],
        "size": int(environment["SIZE"]),
        "sourceSHA": environment["SOURCE_SHA"],
        "swift": environment["SWIFT_VERSION"],
        "uiTestsEnabled": environment["UI_TESTS_ENABLED"] == "true",
        "version": environment["VERSION"],
        "xcode": environment["XCODE_VERSION"],
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
        if not re.fullmatch(r"[0-9a-f]{64}", manifest[key]):
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
    if not isinstance(manifest["uiTestsEnabled"], bool):
        raise ValueError("Invalid UI-test evidence field")


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
