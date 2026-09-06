#!/usr/bin/env python3
"""Validate Homeward's release coverage contract against TRACEABILITY.md.

The validator treats the traceability table as the requirement inventory and
the JSON document as the evidence mapping. It rejects schema drift, incomplete
or duplicate inventories, unknown evidence identifiers, and release evidence
assigned to requirements explicitly deferred beyond version 0.1.0.
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any, Mapping


SCHEMA_VERSION = 1
TRACEABILITY_SOURCE = "docs/TRACEABILITY.md"
LAYERS = (
    "core",
    "hosted",
    "ui",
    "journey",
    "releaseLifecycle",
    "manual",
)
TOP_LEVEL_KEYS = {
    "schemaVersion",
    "traceabilitySource",
    "requiredTests",
    "evidenceCatalog",
    "requirements",
}
REQUIRED_TEST_LAYERS = {"ui", "journey", "releaseLifecycle"}
EVIDENCE_KEYS = {"id", "layer", "state", "source"}
REQUIREMENT_KEYS = {
    "id",
    "traceabilityStatus",
    "releaseDisposition",
    "evidence",
    "gaps",
}
REQUIREMENT_ID_PATTERN = re.compile(r"[A-Z][A-Z0-9]*-[0-9]{3}")
EVIDENCE_ID_PATTERN = re.compile(
    r"(?:core|hosted|ui|journey|releaseLifecycle|manual)"
    r"\.[a-z][a-z0-9]*(?:-[a-z0-9]+)*"
)
TRACEABILITY_ROW_PATTERN = re.compile(
    r"^\|\s*([A-Z][A-Z0-9]*-[0-9]{3})\s*\|.*\|\s*(.*?)\s*\|\s*$"
)


class ContractValidationError(ValueError):
    """Raised when the release coverage contract fails closed."""


def load_json(path: Path) -> dict[str, Any]:
    """Load JSON while rejecting duplicate object keys."""

    def unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise ContractValidationError(
                    f"Duplicate JSON object key: {key}"
                )
            result[key] = value
        return result

    try:
        with path.open(encoding="utf-8") as source:
            document = json.load(source, object_pairs_hook=unique_object)
    except (OSError, json.JSONDecodeError) as error:
        raise ContractValidationError(
            f"Unable to load JSON contract: {error}"
        ) from error
    if not isinstance(document, dict):
        raise ContractValidationError("Contract root must be an object")
    return document


def parse_traceability(path: Path) -> dict[str, str]:
    """Return the ordered requirement-to-status inventory from Markdown."""

    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as error:
        raise ContractValidationError(
            f"Unable to read traceability source: {error}"
        ) from error

    requirements: dict[str, str] = {}
    for line in lines:
        match = TRACEABILITY_ROW_PATTERN.match(line)
        if match is None:
            continue
        requirement_id, status = match.groups()
        if requirement_id in requirements:
            raise ContractValidationError(
                f"Duplicate traceability requirement ID: {requirement_id}"
            )
        requirements[requirement_id] = status
    if not requirements:
        raise ContractValidationError(
            "Traceability source contains no requirement rows"
        )
    return requirements


def _require_exact_keys(
    value: Any,
    expected: set[str],
    context: str,
) -> Mapping[str, Any]:
    if not isinstance(value, dict):
        raise ContractValidationError(f"{context} must be an object")
    actual = set(value)
    if actual != expected:
        missing = sorted(expected - actual)
        unexpected = sorted(actual - expected)
        raise ContractValidationError(
            f"{context} schema mismatch; "
            f"missing={missing}, unexpected={unexpected}"
        )
    return value


def _require_string(value: Any, context: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ContractValidationError(
            f"{context} must be a non-empty string"
        )
    return value


def _require_string_list(value: Any, context: str) -> list[str]:
    if not isinstance(value, list):
        raise ContractValidationError(f"{context} must be an array")
    if any(not isinstance(item, str) or not item.strip() for item in value):
        raise ContractValidationError(
            f"{context} must contain only non-empty strings"
        )
    if len(value) != len(set(value)):
        raise ContractValidationError(
            f"{context} must not contain duplicates"
        )
    return value


def _validate_evidence_catalog(
    entries: Any,
) -> dict[str, Mapping[str, Any]]:
    if not isinstance(entries, list) or not entries:
        raise ContractValidationError(
            "evidenceCatalog must be a non-empty array"
        )

    catalog: dict[str, Mapping[str, Any]] = {}
    for index, raw_entry in enumerate(entries):
        context = f"evidenceCatalog[{index}]"
        entry = _require_exact_keys(raw_entry, EVIDENCE_KEYS, context)
        evidence_id = _require_string(entry["id"], f"{context}.id")
        if EVIDENCE_ID_PATTERN.fullmatch(evidence_id) is None:
            raise ContractValidationError(
                f"Invalid evidence ID: {evidence_id}"
            )
        if evidence_id in catalog:
            raise ContractValidationError(
                f"Duplicate evidence ID: {evidence_id}"
            )
        layer = entry["layer"]
        if layer not in LAYERS:
            raise ContractValidationError(
                f"Invalid evidence layer for {evidence_id}: {layer}"
            )
        if not evidence_id.startswith(f"{layer}."):
            raise ContractValidationError(
                f"Evidence ID layer mismatch: {evidence_id}"
            )
        if entry["state"] not in {"available", "planned"}:
            raise ContractValidationError(
                f"Invalid evidence state for {evidence_id}"
            )
        if (
            layer in {"journey", "releaseLifecycle"}
            and entry["state"] != "available"
        ):
            raise ContractValidationError(
                f"Required automated evidence is not available: {evidence_id}"
            )
        _require_string(entry["source"], f"{context}.source")
        catalog[evidence_id] = entry
    return catalog


def validate_contract(
    contract: Mapping[str, Any],
    expected_requirements: Mapping[str, str],
) -> None:
    """Validate schema, complete coverage, and evidence semantics."""

    contract = _require_exact_keys(
        contract,
        TOP_LEVEL_KEYS,
        "contract",
    )
    if type(contract["schemaVersion"]) is not int:
        raise ContractValidationError("schemaVersion must be an integer")
    if contract["schemaVersion"] != SCHEMA_VERSION:
        raise ContractValidationError(
            f"schemaVersion must be {SCHEMA_VERSION}"
        )
    if contract["traceabilitySource"] != TRACEABILITY_SOURCE:
        raise ContractValidationError(
            f"traceabilitySource must be {TRACEABILITY_SOURCE}"
        )
    required_tests = _require_exact_keys(
        contract["requiredTests"],
        REQUIRED_TEST_LAYERS,
        "requiredTests",
    )
    for layer in sorted(REQUIRED_TEST_LAYERS):
        tests = _require_string_list(
            required_tests[layer],
            f"requiredTests.{layer}",
        )
        if not tests:
            raise ContractValidationError(
                f"requiredTests.{layer} must not be empty"
            )
        if tests != sorted(tests):
            raise ContractValidationError(
                f"requiredTests.{layer} must be sorted"
            )

    catalog = _validate_evidence_catalog(contract["evidenceCatalog"])
    raw_requirements = contract["requirements"]
    if not isinstance(raw_requirements, list) or not raw_requirements:
        raise ContractValidationError(
            "requirements must be a non-empty array"
        )

    requirements: dict[str, Mapping[str, Any]] = {}
    referenced_evidence: set[str] = set()
    for index, raw_requirement in enumerate(raw_requirements):
        context = f"requirements[{index}]"
        requirement = _require_exact_keys(
            raw_requirement,
            REQUIREMENT_KEYS,
            context,
        )
        requirement_id = _require_string(
            requirement["id"],
            f"{context}.id",
        )
        if REQUIREMENT_ID_PATTERN.fullmatch(requirement_id) is None:
            raise ContractValidationError(
                f"Invalid requirement ID: {requirement_id}"
            )
        if requirement_id in requirements:
            raise ContractValidationError(
                f"Duplicate requirement ID: {requirement_id}"
            )
        requirements[requirement_id] = requirement

        status = _require_string(
            requirement["traceabilityStatus"],
            f"{requirement_id}.traceabilityStatus",
        )
        expected_status = expected_requirements.get(requirement_id)
        if expected_status is not None and status != expected_status:
            raise ContractValidationError(
                f"Traceability status mismatch for {requirement_id}"
            )
        evidence = _require_string_list(
            requirement["evidence"],
            f"{requirement_id}.evidence",
        )
        _require_string_list(
            requirement["gaps"],
            f"{requirement_id}.gaps",
        )
        disposition = requirement["releaseDisposition"]
        is_deferred = status.startswith("Deferred")
        if is_deferred:
            if disposition != "excluded":
                raise ContractValidationError(
                    f"Deferred requirement must be excluded: {requirement_id}"
                )
            if evidence:
                raise ContractValidationError(
                    f"Deferred requirement must not claim evidence: "
                    f"{requirement_id}"
                )
        else:
            if disposition != "required":
                raise ContractValidationError(
                    f"Active requirement must be required: {requirement_id}"
                )
            if not evidence:
                raise ContractValidationError(
                    f"Active requirement is missing evidence: {requirement_id}"
                )

        for evidence_id in evidence:
            if evidence_id not in catalog:
                raise ContractValidationError(
                    f"Unexpected test ID for {requirement_id}: {evidence_id}"
                )
            referenced_evidence.add(evidence_id)

    expected_ids = set(expected_requirements)
    actual_ids = set(requirements)
    missing = sorted(expected_ids - actual_ids)
    unexpected = sorted(actual_ids - expected_ids)
    if missing or unexpected:
        raise ContractValidationError(
            "Requirement inventory mismatch; "
            f"missing={missing}, unexpected={unexpected}"
        )

    unreferenced = sorted(set(catalog) - referenced_evidence)
    if unreferenced:
        raise ContractValidationError(
            f"Unreferenced expected test IDs: {unreferenced}"
        )


def validate_repository_contract(repository_root: Path) -> None:
    """Validate the checked-in contract against the checked-in inventory."""

    contract_path = repository_root / "scripts/release_coverage_contract.json"
    traceability_path = repository_root / TRACEABILITY_SOURCE
    contract = load_json(contract_path)
    expected_requirements = parse_traceability(traceability_path)
    validate_contract(contract, expected_requirements)
    source_by_layer = {
        "ui": repository_root / "HomewardUITests/HomewardUITests.swift",
        "journey": (
            repository_root
            / "HomewardJourneyUITests/HomewardJourneyUITests.swift"
        ),
        "releaseLifecycle": (
            repository_root
            / "HomewardReleaseE2ETests/ReleaseLifecycleE2ETests.swift"
        ),
    }
    for layer, source_path in source_by_layer.items():
        try:
            source = source_path.read_text(encoding="utf-8")
        except OSError as error:
            raise ContractValidationError(
                f"Unable to read {layer} test source: {error}"
            ) from error
        for identifier in contract["requiredTests"][layer]:
            method = identifier.rsplit("/", maxsplit=1)[-1].removesuffix("()")
            if re.search(rf"\bfunc\s+{re.escape(method)}\s*\(", source) is None:
                raise ContractValidationError(
                    f"Required {layer} test is missing: {identifier}"
                )
    for evidence in contract["evidenceCatalog"]:
        if evidence["state"] != "available":
            continue
        for reference in evidence["source"].split("; "):
            path_text, separator, symbol = reference.partition("::")
            source_path = repository_root / path_text
            if not source_path.is_file():
                raise ContractValidationError(
                    f"Evidence source is missing: {path_text}"
                )
            if separator and symbol not in source_path.read_text(
                encoding="utf-8"
            ):
                raise ContractValidationError(
                    f"Evidence symbol is missing: {reference}"
                )


def main() -> None:
    """Validate the repository contract or exit with a concise error."""

    repository_root = Path(__file__).resolve().parent.parent
    try:
        validate_repository_contract(repository_root)
    except ContractValidationError as error:
        raise SystemExit(f"release coverage contract invalid: {error}") from error
    print("release coverage contract valid")


if __name__ == "__main__":
    main()
