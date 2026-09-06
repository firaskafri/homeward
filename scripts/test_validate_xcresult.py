"""1 - Name: Homeward XCTest evidence validator tests.
2 - Description: Exercises strict expected-test, pass, skip, failure, duplicate, and count validation without launching applications.
3 - Assumptions: Synthetic documents use the stable fields consumed from xcresulttool test-results output.
4 - Expectations: Only an exact, complete, all-passing required test inventory is accepted.
"""

import unittest

from scripts.validate_xcresult import (
    ResultValidationError,
    validate_result_documents,
)


class XCTestResultValidationTests(unittest.TestCase):
    """1 - Name: XCTest result validation suite.
    2 - Description: Mutates a minimal passing result to exercise every fail-closed invariant.
    3 - Assumptions: Two stable test identifiers represent a required E2E layer.
    4 - Expectations: Missing, unexpected, skipped, failed, duplicate, or miscounted cases are rejected.
    """

    def setUp(self) -> None:
        self.expected = {"Suite/testA()", "Suite/testB()"}
        self.summary = {
            "result": "Passed",
            "failedTests": 0,
            "skippedTests": 0,
            "totalTestCount": 2,
        }
        self.tests = {
            "testNodes": [
                {
                    "nodeType": "Test Suite",
                    "children": [
                        {
                            "nodeType": "Test Case",
                            "nodeIdentifier": "Suite/testA()",
                            "result": "Passed",
                        },
                        {
                            "nodeType": "Test Case",
                            "nodeIdentifier": "Suite/testB()",
                            "result": "Passed",
                        },
                    ],
                }
            ]
        }

    def test_exact_passing_inventory_succeeds(self):
        """1 - Name: Exact passing inventory.
        2 - Description: Validates a result containing every required test exactly once.
        3 - Assumptions: Summary and test-tree counts describe the same run.
        4 - Expectations: Validation completes without an exception.
        """
        validate_result_documents(
            self.summary,
            self.tests,
            self.expected,
        )

    def test_missing_test_fails_closed(self):
        """1 - Name: Missing required test.
        2 - Description: Removes one required case while leaving the expected contract unchanged.
        3 - Assumptions: A green subset cannot authorize a release.
        4 - Expectations: Validation reports an inventory mismatch.
        """
        self.tests["testNodes"][0]["children"].pop()
        with self.assertRaisesRegex(
            ResultValidationError,
            "inventory mismatch",
        ):
            validate_result_documents(
                self.summary,
                self.tests,
                self.expected,
            )

    def test_skipped_summary_fails_closed(self):
        """1 - Name: Skipped test result.
        2 - Description: Marks the summary as containing one skipped test.
        3 - Assumptions: Required release tests may not be skipped.
        4 - Expectations: Validation rejects the result before accepting its test tree.
        """
        self.summary["skippedTests"] = 1
        with self.assertRaisesRegex(
            ResultValidationError,
            "skipped",
        ):
            validate_result_documents(
                self.summary,
                self.tests,
                self.expected,
            )

    def test_failed_case_fails_closed(self):
        """1 - Name: Failed required test.
        2 - Description: Marks one required test case failed despite an otherwise matching inventory.
        3 - Assumptions: Per-case results are authoritative even if summary data is malformed.
        4 - Expectations: Validation names the non-passing required case.
        """
        self.tests["testNodes"][0]["children"][1]["result"] = "Failed"
        with self.assertRaisesRegex(
            ResultValidationError,
            "did not pass",
        ):
            validate_result_documents(
                self.summary,
                self.tests,
                self.expected,
            )

    def test_duplicate_case_fails_closed(self):
        """1 - Name: Duplicate required test.
        2 - Description: Appends a second result node for an already-recorded case.
        3 - Assumptions: Retries or duplicate reporting cannot silently satisfy the exact inventory.
        4 - Expectations: Validation rejects the duplicate identifier.
        """
        duplicate = dict(self.tests["testNodes"][0]["children"][0])
        self.tests["testNodes"][0]["children"].append(duplicate)
        with self.assertRaisesRegex(
            ResultValidationError,
            "Duplicate XCTest result",
        ):
            validate_result_documents(
                self.summary,
                self.tests,
                self.expected,
            )


if __name__ == "__main__":
    unittest.main()
