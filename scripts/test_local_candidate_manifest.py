"""1 - Name: Local candidate manifest test file.
2 - Description: Verifies explicit provenance schema construction and identity validation.
3 - Assumptions: Tests use synthetic metadata and never package, sign, notarize, or publish artifacts.
4 - Expectations: Every required identity field is bound and inconsistent binary evidence fails closed.
"""

import unittest

from scripts.local_candidate_manifest import (
    EXPECTED_KEYS,
    SCHEMA_VERSION,
    build_manifest,
)


class LocalCandidateManifestTests(unittest.TestCase):
    """1 - Name: Local candidate manifest suite.
    2 - Description: Exercises canonical schema output and cross-artifact UUID binding.
    3 - Assumptions: Environment values have the same shapes as verified package inputs.
    4 - Expectations: Local provenance remains explicit, complete, and internally consistent.
    """

    def setUp(self):
        self.environment = {
            "APP_TREE_SHA": "a" * 64,
            "ARCHITECTURE": "arm64",
            "ARTIFACT": "Homeward-0.1.0-build.1-local-arm64.dmg",
            "BINARY_UUID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
            "BUILD": "1",
            "BUNDLE_IDENTIFIER": "com.firaskafri.homeward",
            "CHECKSUM": "b" * 64,
            "DSYM_TREE_SHA": "c" * 64,
            "DSYM_UUID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
            "MINIMUM_SYSTEM_VERSION": "15.0",
            "SIGNATURE_MODE": "ad-hoc",
            "SIZE": "4096",
            "SOURCE_SHA": "d" * 40,
            "SWIFT_VERSION": "Swift version fixture",
            "UI_TESTS_ENABLED": "true",
            "VERSION": "0.1.0",
            "XCODE_VERSION": "Xcode fixture",
        }

    def test_manifest_binds_complete_local_identity(self):
        """1 - Name: Complete local identity binding.
        2 - Description: Builds a manifest from every verified app and final DMG identity input.
        3 - Assumptions: Synthetic hashes, UUIDs, versions, architecture, and size use canonical formats.
        4 - Expectations: The exact schema includes source, app, platform, signature, notarization, debug, hash, and size fields.
        """
        manifest = build_manifest(self.environment)

        self.assertEqual(set(manifest), EXPECTED_KEYS)
        self.assertEqual(manifest["schemaVersion"], SCHEMA_VERSION)
        self.assertEqual(manifest["sourceSHA"], "d" * 40)
        self.assertEqual(manifest["version"], "0.1.0")
        self.assertEqual(manifest["build"], "1")
        self.assertEqual(manifest["architecture"], "arm64")
        self.assertEqual(manifest["minimumSystemVersion"], "15.0")
        self.assertEqual(manifest["signatureMode"], "ad-hoc")
        self.assertIs(manifest["notarized"], False)
        self.assertEqual(
            manifest["binaryUUID"],
            manifest["dSYMUUID"],
        )
        self.assertEqual(manifest["sha256"], "b" * 64)
        self.assertEqual(manifest["size"], 4096)

    def test_manifest_rejects_mismatched_debug_identity(self):
        """1 - Name: Mismatched debug identity rejection.
        2 - Description: Supplies a validly formatted dSYM UUID that differs from the packaged app binary.
        3 - Assumptions: Matching UUIDs are required even when all individual fields are syntactically valid.
        4 - Expectations: Manifest construction fails before inconsistent provenance can be written.
        """
        self.environment["DSYM_UUID"] = (
            "11111111-2222-3333-4444-555555555555"
        )

        with self.assertRaisesRegex(
            ValueError,
            "Binary and dSYM UUIDs must match",
        ):
            build_manifest(self.environment)

    def test_manifest_rejects_nonfinal_dmg_evidence(self):
        """1 - Name: Invalid final DMG evidence rejection.
        2 - Description: Supplies an invalid final image hash and then a nonpositive byte size.
        3 - Assumptions: Hash and size are computed only after the DMG is finalized.
        4 - Expectations: Either malformed identity fails closed instead of producing a provenance record.
        """
        self.environment["CHECKSUM"] = "not-a-sha256"
        with self.assertRaisesRegex(ValueError, "Invalid hash field: sha256"):
            build_manifest(self.environment)

        self.environment["CHECKSUM"] = "b" * 64
        self.environment["SIZE"] = "0"
        with self.assertRaisesRegex(
            ValueError,
            "Final DMG size must be positive",
        ):
            build_manifest(self.environment)


if __name__ == "__main__":
    unittest.main()
