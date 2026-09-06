"""1 - Name: Local candidate manifest schema test file.
2 - Description: Verifies package identity and three-layer UI evidence construction.
3 - Assumptions: Synthetic metadata never packages, signs, notarizes, or publishes artifacts.
4 - Expectations: Enabled layers bind canonical artifacts; disabled, malformed, stale, or inconsistent evidence fails closed.
"""

import unittest

from scripts.local_candidate_manifest import (
    EXPECTED_KEYS,
    SCHEMA_VERSION,
    build_manifest,
)


class LocalCandidateManifestTests(unittest.TestCase):
    """1 - Name: Local candidate manifest suite.
    2 - Description: Exercises schema output, UI-layer invariants, and UUID binding.
    3 - Assumptions: Environment values have the same shapes as verified package inputs.
    4 - Expectations: Local provenance remains explicit, canonical, and internally consistent across enabled and disabled layers.
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
            "COVERAGE_CONTRACT_SHA256": "e" * 64,
            "DSYM_TREE_SHA": "c" * 64,
            "DSYM_UUID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
            "JOURNEY_E2E_ENABLED": "true",
            "JOURNEY_RESULT_SHA256": "f" * 64,
            "MINIMUM_SYSTEM_VERSION": "15.0",
            "RELEASE_E2E_CONFIGURATION": "Release",
            "RELEASE_E2E_ENABLED": "true",
            "RELEASE_E2E_SCHEME": "HomewardReleaseE2E",
            "RELEASE_RESULT_SHA256": "1" * 64,
            "SIGNATURE_MODE": "ad-hoc",
            "SIZE": "4096",
            "SOURCE_SHA": "d" * 40,
            "SWIFT_VERSION": "Swift version fixture",
            "UI_TESTS_ENABLED": "true",
            "UI_RESULT_SHA256": "3" * 64,
            "VERSION": "0.1.0",
            "XCTESTRUN_SHA256": "2" * 64,
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
        self.assertIs(manifest["uiTestsEnabled"], True)
        self.assertEqual(manifest["uiResultSHA256"], "3" * 64)
        self.assertIs(manifest["journeyE2EEnabled"], True)
        self.assertIs(manifest["releaseE2EEnabled"], True)
        self.assertEqual(manifest["releaseE2EConfiguration"], "Release")
        self.assertEqual(
            manifest["releaseE2EScheme"],
            "HomewardReleaseE2E",
        )

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

    def test_manifest_records_all_ui_layers_disabled(self):
        """1 - Name: Disabled UI layers recording.
        2 - Description: Builds a local manifest with every UI evidence layer explicitly disabled.
        3 - Assumptions: Disabled layers have empty environment values that represent JSON null artifact metadata.
        4 - Expectations: All booleans remain false and all UI artifact, configuration, and scheme fields remain null.
        """
        self.environment.update(
            {
                "UI_TESTS_ENABLED": "false",
                "UI_RESULT_SHA256": "",
                "JOURNEY_E2E_ENABLED": "false",
                "RELEASE_E2E_ENABLED": "false",
                "COVERAGE_CONTRACT_SHA256": "",
                "JOURNEY_RESULT_SHA256": "",
                "RELEASE_RESULT_SHA256": "",
                "XCTESTRUN_SHA256": "",
                "RELEASE_E2E_CONFIGURATION": "",
                "RELEASE_E2E_SCHEME": "",
            }
        )

        manifest = build_manifest(self.environment)

        self.assertIs(manifest["uiTestsEnabled"], False)
        self.assertIs(manifest["journeyE2EEnabled"], False)
        self.assertIs(manifest["releaseE2EEnabled"], False)
        for key in (
            "coverageContractSHA256",
            "uiResultSHA256",
            "journeyResultSHA256",
            "releaseResultSHA256",
            "xctestrunSHA256",
            "releaseE2EConfiguration",
            "releaseE2EScheme",
        ):
            self.assertIsNone(manifest[key])

    def test_manifest_rejects_malformed_boolean_environment(self):
        """1 - Name: Malformed boolean environment rejection.
        2 - Description: Supplies a truthy-looking value outside the canonical true and false strings.
        3 - Assumptions: Shell packaging passes validated lowercase boolean assignments.
        4 - Expectations: Construction rejects the malformed value instead of silently recording false.
        """
        self.environment["JOURNEY_E2E_ENABLED"] = "1"

        with self.assertRaisesRegex(
            ValueError,
            "Invalid boolean environment field: JOURNEY_E2E_ENABLED",
        ):
            build_manifest(self.environment)

    def test_manifest_rejects_wrong_release_configuration(self):
        """1 - Name: Wrong release configuration rejection.
        2 - Description: Supplies valid release E2E artifacts produced under a noncanonical build configuration.
        3 - Assumptions: Public-equivalent release E2E evidence must use the Release configuration.
        4 - Expectations: Manifest construction rejects Debug even when every hash is canonical.
        """
        self.environment["RELEASE_E2E_CONFIGURATION"] = "Debug"

        with self.assertRaisesRegex(
            ValueError,
            "Release E2E configuration must be canonical Release",
        ):
            build_manifest(self.environment)

    def test_manifest_rejects_malformed_ui_artifact_hash(self):
        """1 - Name: Malformed UI artifact hash rejection.
        2 - Description: Supplies a noncanonical journey result hash while that evidence layer is enabled.
        3 - Assumptions: Enabled result identities are lowercase SHA-256 values.
        4 - Expectations: Manifest construction fails before malformed UI provenance can be written.
        """
        self.environment["JOURNEY_RESULT_SHA256"] = "not-a-sha256"

        with self.assertRaisesRegex(
            ValueError,
            "Invalid enabled evidence hash: journeyResultSHA256",
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
