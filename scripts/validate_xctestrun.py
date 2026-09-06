#!/usr/bin/env python3
"""Validate Homeward's Release E2E xctestrun routing before execution."""

import plistlib
import sys
from pathlib import Path
from typing import Any


class XCTestRunValidationError(ValueError):
    """Raised when xctestrun routing can target an unexpected product."""


def validate_document(document: dict[str, Any]) -> None:
    """Require one Release E2E target hosted against the exact Homeward app."""

    targets = [
        value
        for key, value in document.items()
        if key != "__xctestrun_metadata__" and isinstance(value, dict)
    ]
    if len(targets) != 1:
        raise XCTestRunValidationError(
            f"Expected one xctestrun target; found {len(targets)}"
        )
    target = targets[0]
    expected = {
        "BlueprintName": "HomewardReleaseE2ETests",
        "UITargetAppPath": "__TESTROOT__/Release/Homeward.app",
        "TestHostPath":
            "__TESTROOT__/Release/HomewardReleaseE2ETests-Runner.app",
        "TestBundlePath":
            "__TESTHOST__/Contents/PlugIns/HomewardReleaseE2ETests.xctest",
    }
    for key, value in expected.items():
        if target.get(key) != value:
            raise XCTestRunValidationError(
                f"Unexpected {key}: {target.get(key)!r}"
            )


def validate_xctestrun(path: Path) -> None:
    """Load and validate one xctestrun property list."""

    try:
        with path.open("rb") as source:
            document = plistlib.load(source)
    except (OSError, plistlib.InvalidFileException) as error:
        raise XCTestRunValidationError(
            f"Unable to load xctestrun: {error}"
        ) from error
    if not isinstance(document, dict):
        raise XCTestRunValidationError("xctestrun root must be a dictionary")
    validate_document(document)


def main() -> None:
    """Validate the single command-line xctestrun path."""

    if len(sys.argv) != 2:
        raise SystemExit("usage: validate_xctestrun.py XCTESTRUN")
    try:
        validate_xctestrun(Path(sys.argv[1]))
    except XCTestRunValidationError as error:
        raise SystemExit(f"invalid xctestrun: {error}") from error
    print("Release xctestrun routing valid")


if __name__ == "__main__":
    main()
