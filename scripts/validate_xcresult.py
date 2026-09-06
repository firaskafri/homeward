#!/usr/bin/env python3
"""Validate one Homeward XCTest result against the release coverage contract."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path
from typing import Any


class ResultValidationError(ValueError):
    """Raised when XCTest evidence is incomplete or inconsistent."""


def load_expected_tests(contract_path: Path, layer: str) -> set[str]:
    """Load the exact required test identifiers for one E2E layer."""

    try:
        with contract_path.open(encoding="utf-8") as source:
            contract = json.load(source)
        tests = contract["requiredTests"][layer]
    except (OSError, KeyError, TypeError, json.JSONDecodeError) as error:
        raise ResultValidationError(
            f"Unable to load expected {layer} tests: {error}"
        ) from error
    if (
        not isinstance(tests, list)
        or not tests
        or any(not isinstance(test, str) or not test for test in tests)
        or len(tests) != len(set(tests))
    ):
        raise ResultValidationError(
            f"Invalid required test list for {layer}"
        )
    return set(tests)


def validate_result_documents(
    summary: dict[str, Any],
    tests: dict[str, Any],
    expected_tests: set[str],
) -> None:
    """Require a normally completed, exact, all-passing XCTest set."""

    if summary.get("result") != "Passed":
        raise ResultValidationError("XCTest result did not pass")
    if summary.get("failedTests") != 0:
        raise ResultValidationError("XCTest result contains failures")
    if summary.get("skippedTests") != 0:
        raise ResultValidationError("XCTest result contains skipped tests")

    actual: dict[str, str] = {}

    def visit(node: Any) -> None:
        if isinstance(node, dict):
            if node.get("nodeType") == "Test Case":
                identifier = node.get("nodeIdentifier")
                result = node.get("result")
                if not isinstance(identifier, str) or not identifier:
                    raise ResultValidationError(
                        "XCTest case has no identifier"
                    )
                if identifier in actual:
                    raise ResultValidationError(
                        f"Duplicate XCTest result: {identifier}"
                    )
                if not isinstance(result, str):
                    raise ResultValidationError(
                        f"XCTest case has no result: {identifier}"
                    )
                actual[identifier] = result
            for child in node.get("children", []):
                visit(child)
        elif isinstance(node, list):
            for child in node:
                visit(child)

    visit(tests.get("testNodes", []))
    actual_tests = set(actual)
    if actual_tests != expected_tests:
        missing = sorted(expected_tests - actual_tests)
        unexpected = sorted(actual_tests - expected_tests)
        raise ResultValidationError(
            "XCTest inventory mismatch; "
            f"missing={missing}, unexpected={unexpected}"
        )
    failures = sorted(
        identifier
        for identifier, result in actual.items()
        if result != "Passed"
    )
    if failures:
        raise ResultValidationError(
            f"Required XCTest cases did not pass: {failures}"
        )
    if summary.get("totalTestCount") != len(expected_tests):
        raise ResultValidationError(
            "XCTest summary count does not match required inventory"
        )


def xcresult_document(result_path: Path, kind: str) -> dict[str, Any]:
    """Read one JSON document from Apple's xcresulttool."""

    command = [
        "/usr/bin/xcrun",
        "xcresulttool",
        "get",
        "test-results",
        kind,
        "--path",
        str(result_path),
        "--compact",
    ]
    try:
        completed = subprocess.run(
            command,
            check=True,
            capture_output=True,
            text=True,
        )
        document = json.loads(completed.stdout)
    except subprocess.CalledProcessError as error:
        detail = error.stderr.strip() or error.stdout.strip() or str(error)
        raise ResultValidationError(
            f"Unable to read XCTest {kind}: {detail}"
        ) from error
    except OSError as error:
        raise ResultValidationError(
            f"Unable to run xcresulttool for {kind}: {error}"
        ) from error
    except json.JSONDecodeError as error:
        raise ResultValidationError(
            f"Unable to decode XCTest {kind}: {error}"
        ) from error
    if not isinstance(document, dict):
        raise ResultValidationError(
            f"XCTest {kind} document must be an object"
        )
    return document


def validate_xcresult(
    contract_path: Path,
    layer: str,
    result_path: Path,
) -> None:
    """Validate a result bundle against one contract layer."""

    if layer not in {"ui", "journey", "releaseLifecycle"}:
        raise ResultValidationError(f"Unsupported E2E layer: {layer}")
    if not result_path.is_dir():
        raise ResultValidationError(
            f"XCTest result bundle is missing: {result_path}"
        )
    expected = load_expected_tests(contract_path, layer)
    validate_result_documents(
        xcresult_document(result_path, "summary"),
        xcresult_document(result_path, "tests"),
        expected,
    )


def main() -> None:
    """Validate command-line contract, layer, and result arguments."""

    if len(sys.argv) != 4:
        raise SystemExit(
            "usage: validate_xcresult.py CONTRACT "
            "{ui|journey|releaseLifecycle} RESULT"
        )
    try:
        validate_xcresult(
            Path(sys.argv[1]),
            sys.argv[2],
            Path(sys.argv[3]),
        )
    except ResultValidationError as error:
        raise SystemExit(f"invalid XCTest evidence: {error}") from error
    print(f"{sys.argv[2]} XCTest evidence valid")


if __name__ == "__main__":
    main()
