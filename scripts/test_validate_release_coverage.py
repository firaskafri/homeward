"""1 - Name: Homeward release coverage contract validator tests.
2 - Description: Verifies the checked-in contract and every fail-closed rule for its schema, requirement inventory, dispositions, and evidence references.
3 - Assumptions: TRACEABILITY.md is the authoritative requirement inventory, deferred rows begin with Deferred, and tests only read repository files or mutate in-memory copies.
4 - Expectations: The real contract validates while malformed, incomplete, duplicated, unsupported, or misleading coverage declarations are rejected deterministically.
"""

from __future__ import annotations

import copy
import unittest
from pathlib import Path

from scripts.validate_release_coverage import (
    ContractValidationError,
    load_json,
    parse_traceability,
    validate_contract,
)


class ReleaseCoverageContractTests(unittest.TestCase):
    """1 - Name: Release coverage contract validation suite.
    2 - Description: Exercises the complete repository contract plus isolated mutations for strict schema, inventory, evidence, and deferred-release semantics.
    3 - Assumptions: Test mutations start from the valid checked-in JSON so each failure isolates one contract invariant without running Homeward or any Swift test target.
    4 - Expectations: All 77 traceability rows are represented exactly once, active rows name known evidence, and deferred rows stay explicitly excluded without evidence claims.
    """

    @classmethod
    def setUpClass(cls) -> None:
        cls.repository_root = Path(__file__).resolve().parent.parent
        cls.contract_path = (
            cls.repository_root / "scripts/release_coverage_contract.json"
        )
        cls.traceability_path = (
            cls.repository_root / "docs/TRACEABILITY.md"
        )
        cls.contract = load_json(cls.contract_path)
        cls.expected_requirements = parse_traceability(
            cls.traceability_path
        )

    def mutable_contract(self) -> dict:
        return copy.deepcopy(self.contract)

    def requirement(self, contract: dict, requirement_id: str) -> dict:
        return next(
            requirement
            for requirement in contract["requirements"]
            if requirement["id"] == requirement_id
        )

    def test_checked_in_contract_covers_complete_inventory(self):
        """1 - Name: Complete checked-in contract validation.
        2 - Description: Validates the real JSON contract against every requirement row parsed from TRACEABILITY.md.
        3 - Assumptions: The traceability table and contract are read from their canonical repository locations.
        4 - Expectations: The strict validator accepts the schema, all 77 unique IDs, dispositions, evidence mappings, and expected test IDs.
        """
        self.assertEqual(len(self.expected_requirements), 77)
        validate_contract(self.contract, self.expected_requirements)

    def test_schema_rejects_missing_top_level_field(self):
        """1 - Name: Strict top-level schema rejection.
        2 - Description: Removes the evidence catalog from an otherwise valid contract.
        3 - Assumptions: Unknown or absent top-level fields indicate incompatible contract schema drift.
        4 - Expectations: Validation fails with a schema mismatch before coverage can be accepted.
        """
        contract = self.mutable_contract()
        del contract["evidenceCatalog"]

        with self.assertRaisesRegex(
            ContractValidationError,
            "contract schema mismatch",
        ):
            validate_contract(contract, self.expected_requirements)

    def test_duplicate_requirement_id_is_rejected(self):
        """1 - Name: Duplicate requirement ID rejection.
        2 - Description: Appends a second copy of one valid requirement mapping.
        3 - Assumptions: One requirement may have many evidence references but exactly one contract row.
        4 - Expectations: Validation names the duplicate ID instead of silently overriding either mapping.
        """
        contract = self.mutable_contract()
        contract["requirements"].append(
            copy.deepcopy(contract["requirements"][0])
        )

        with self.assertRaisesRegex(
            ContractValidationError,
            "Duplicate requirement ID: PRD-001",
        ):
            validate_contract(contract, self.expected_requirements)

    def test_missing_requirement_id_is_rejected(self):
        """1 - Name: Missing requirement ID rejection.
        2 - Description: Removes one active row while leaving the traceability inventory unchanged.
        3 - Assumptions: Every Markdown requirement, regardless of implementation status, belongs in the JSON contract.
        4 - Expectations: Validation reports an inventory mismatch containing the omitted requirement ID.
        """
        contract = self.mutable_contract()
        contract["requirements"] = [
            requirement
            for requirement in contract["requirements"]
            if requirement["id"] != "STA-001"
        ]

        with self.assertRaisesRegex(
            ContractValidationError,
            r"Requirement inventory mismatch.*STA-001",
        ):
            validate_contract(contract, self.expected_requirements)

    def test_active_requirement_without_evidence_is_rejected(self):
        """1 - Name: Missing active evidence rejection.
        2 - Description: Clears the evidence list for a release-required startup requirement.
        3 - Assumptions: Planned journey or manual IDs are valid mappings when automated evidence does not yet exist.
        4 - Expectations: An active row cannot pass with an empty evidence list.
        """
        contract = self.mutable_contract()
        self.requirement(contract, "STA-001")["evidence"] = []

        with self.assertRaisesRegex(
            ContractValidationError,
            "Active requirement is missing evidence: STA-001",
        ):
            validate_contract(contract, self.expected_requirements)

    def test_deferred_requirement_must_be_excluded(self):
        """1 - Name: Deferred disposition enforcement.
        2 - Description: Marks a post-0.1.0 detailed-notification requirement as release-required.
        3 - Assumptions: A Deferred traceability status is authoritative for the 0.1.0 release boundary.
        4 - Expectations: Validation requires the excluded disposition and rejects accidental scope expansion.
        """
        contract = self.mutable_contract()
        self.requirement(
            contract,
            "NOT-004",
        )["releaseDisposition"] = "required"

        with self.assertRaisesRegex(
            ContractValidationError,
            "Deferred requirement must be excluded: NOT-004",
        ):
            validate_contract(contract, self.expected_requirements)

    def test_deferred_requirement_cannot_claim_evidence(self):
        """1 - Name: Deferred evidence claim rejection.
        2 - Description: Assigns an existing automated test ID to an explicitly excluded localization requirement.
        3 - Assumptions: Deferred rows remain documented but are not release-coverage claims for version 0.1.0.
        4 - Expectations: Validation rejects evidence on an excluded row even when the test ID itself exists.
        """
        contract = self.mutable_contract()
        self.requirement(contract, "LOC-001")["evidence"] = [
            "core.domain-validation"
        ]

        with self.assertRaisesRegex(
            ContractValidationError,
            "Deferred requirement must not claim evidence: LOC-001",
        ):
            validate_contract(contract, self.expected_requirements)

    def test_unknown_expected_test_id_is_rejected(self):
        """1 - Name: Unknown expected test ID rejection.
        2 - Description: Replaces valid startup evidence with an identifier absent from the evidence catalog.
        3 - Assumptions: Requirement rows may reference only explicitly declared, layer-qualified evidence IDs.
        4 - Expectations: Validation reports the unexpected test ID and the affected requirement.
        """
        contract = self.mutable_contract()
        self.requirement(contract, "STA-001")["evidence"] = [
            "hosted.nonexistent-test"
        ]

        with self.assertRaisesRegex(
            ContractValidationError,
            "Unexpected test ID for STA-001: hosted.nonexistent-test",
        ):
            validate_contract(contract, self.expected_requirements)

    def test_unreferenced_expected_test_id_is_rejected(self):
        """1 - Name: Unreferenced expected test ID rejection.
        2 - Description: Adds a well-formed planned journey ID that no requirement expects.
        3 - Assumptions: The evidence catalog is an exact registry rather than a speculative backlog.
        4 - Expectations: Validation rejects orphaned catalog IDs so every expected test remains requirement-driven.
        """
        contract = self.mutable_contract()
        contract["evidenceCatalog"].append(
            {
                "id": "journey.orphaned-test",
                "layer": "journey",
                "state": "available",
                "source": "Executable orphan that must be rejected",
            }
        )

        with self.assertRaisesRegex(
            ContractValidationError,
            "Unreferenced expected test IDs:.*journey.orphaned-test",
        ):
            validate_contract(contract, self.expected_requirements)

    def test_planned_automated_evidence_is_rejected(self):
        """1 - Name: Planned automated evidence rejection.
        2 - Description: Downgrades a required journey from available to planned.
        3 - Assumptions: Manual checks may await operator execution, but required automated suites must exist before the contract is accepted.
        4 - Expectations: Validation rejects a journey or Release lifecycle placeholder that has no executable implementation.
        """
        contract = self.mutable_contract()
        journey = next(
            evidence
            for evidence in contract["evidenceCatalog"]
            if evidence["id"] == "journey.navigation"
        )
        journey["state"] = "planned"

        with self.assertRaisesRegex(
            ContractValidationError,
            "Required automated evidence is not available",
        ):
            validate_contract(contract, self.expected_requirements)


if __name__ == "__main__":
    unittest.main()
