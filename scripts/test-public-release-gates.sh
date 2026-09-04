#!/bin/bash

set -euo pipefail

# Test suite intention:
# - Exercise public-release policy gates without signing or notarizing anything.
# - Assume local Git file remotes are available and no signing key is present.
# - Cover clean/pushed source, exact signed tags, credential names, and identity
#   inventory matching, including exact failure diagnostics for dirty, unpushed,
#   lightweight, unsigned, malformed identity, malformed team, and missing
#   profile edge cases.

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/public-release-gates.sh
source "$repository_root/scripts/public-release-gates.sh"
# shellcheck source=scripts/release-evidence.sh
source "$repository_root/scripts/release-evidence.sh"

temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/homeward-release-gates.XXXXXX")"
trap 'rm -rf "$temporary_root"' EXIT
test_output="$temporary_root/test-output"
tests_run=0

pass() {
  tests_run=$((tests_run + 1))
  printf 'ok %d - %s\n' "$tests_run" "$1"
}

fail() {
  printf 'not ok %d - %s\n' "$((tests_run + 1))" "$1" >&2
  [[ ! -s "$test_output" ]] || cat "$test_output" >&2
  exit 1
}

assert_passes() {
  local name="$1"
  shift
  : >"$test_output"
  if "$@" >"$test_output" 2>&1; then
    pass "$name"
  else
    fail "$name"
  fi
}

assert_fails() {
  local name="$1"
  local expected_diagnostic="$2"
  shift 2
  : >"$test_output"
  if "$@" >"$test_output" 2>&1; then
    fail "$name"
  elif /usr/bin/grep -Fqx -- "$expected_diagnostic" "$test_output"; then
    pass "$name"
  else
    printf 'Expected diagnostic: %s\n' "$expected_diagnostic" >>"$test_output"
    fail "$name"
  fi
}

remote="$temporary_root/remote.git"
worktree="$temporary_root/worktree"
git init -q --bare "$remote"
git init -q -b main "$worktree"
git -C "$worktree" config user.name "Homeward Release Tests"
git -C "$worktree" config user.email "release-tests@example.invalid"
printf 'fixture\n' >"$worktree/tracked.txt"
git -C "$worktree" add tracked.txt
git -C "$worktree" -c commit.gpgSign=false commit -q -m "Initial fixture"
git -C "$worktree" remote add origin "$remote"
git -C "$worktree" push -q -u origin main

# 1 - Clean pushed source succeeds
# 2 - Confirms the source gates accept an unchanged remote-backed commit.
# 3 - Assumes the temporary repository has a configured origin/main upstream.
# 4 - Expects both clean-tree and pushed-HEAD checks to pass.
test_clean_pushed_source_succeeds() {
  homeward_require_clean_tree "$worktree" &&
    homeward_require_pushed_head "$worktree"
}
assert_passes \
  "clean pushed source succeeds" \
  test_clean_pushed_source_succeeds

# 1 - Dirty source fails closed
# 2 - Confirms tracked modifications block public release preparation.
# 3 - Assumes the repository was clean before this test modifies one file.
# 4 - Expects the clean-tree gate to reject the worktree.
test_dirty_source_fails_closed() {
  printf 'dirty\n' >>"$worktree/tracked.txt"
  if homeward_require_clean_tree "$worktree"; then
    return 0
  fi
  git -C "$worktree" restore tracked.txt
  return 1
}
assert_fails \
  "dirty source fails closed" \
  "Public release requires a clean working tree." \
  test_dirty_source_fails_closed
git -C "$worktree" restore tracked.txt

# 1 - Unpushed HEAD fails closed
# 2 - Confirms a local commit absent from the upstream cannot be released.
# 3 - Assumes origin/main still points at the initial fixture commit.
# 4 - Expects the pushed-HEAD gate to reject the newer local commit.
test_unpushed_head_fails_closed() {
  homeward_require_pushed_head "$worktree"
}
printf 'second\n' >>"$worktree/tracked.txt"
git -C "$worktree" add tracked.txt
git -C "$worktree" -c commit.gpgSign=false commit -q -m "Unpushed fixture"
assert_fails \
  "unpushed HEAD fails closed" \
  "Public release requires HEAD to match the pushed upstream." \
  test_unpushed_head_fails_closed
git -C "$worktree" push -q

# 1 - Lightweight release tag fails closed
# 2 - Confirms a tag reference without an annotated tag object is insufficient.
# 3 - Assumes v0.1.0 points directly to the current commit.
# 4 - Expects the signed annotated tag gate to reject the lightweight tag.
test_lightweight_tag_fails_closed() {
  homeward_require_signed_release_tag "$worktree" "v0.1.0"
}
git -C "$worktree" tag v0.1.0
assert_fails \
  "lightweight release tag fails closed" \
  "Public release requires the annotated tag v0.1.0." \
  test_lightweight_tag_fails_closed
git -C "$worktree" tag -d v0.1.0 >/dev/null

# 1 - Unsigned annotated release tag fails closed
# 2 - Confirms annotation alone cannot replace cryptographic tag verification.
# 3 - Assumes the temporary tag is deliberately created without a signature.
# 4 - Expects git verify-tag to reject v0.1.0.
test_unsigned_annotated_tag_fails_closed() {
  homeward_require_signed_release_tag "$worktree" "v0.1.0"
}
git -C "$worktree" -c tag.gpgSign=false tag -a v0.1.0 -m "Unsigned fixture"
assert_fails \
  "unsigned annotated release tag fails closed" \
  "Tag v0.1.0 does not have a valid Git signature." \
  test_unsigned_annotated_tag_fails_closed

expected_identity="Developer ID Application: Example Developer (ABCDE12345)"
valid_inventory="  1) 0123456789ABCDEF0123456789ABCDEF01234567 \"$expected_identity\""

# 1 - Exact Developer ID inventory match succeeds
# 2 - Confirms one exact certificate name for the requested team is accepted.
# 3 - Assumes security output uses its standard quoted identity format.
# 4 - Expects identity inventory validation to pass exactly once.
test_exact_identity_match_succeeds() {
  homeward_require_identity_inventory \
    "$expected_identity" \
    "ABCDE12345" \
    "$valid_inventory"
}
assert_passes \
  "exact Developer ID inventory match succeeds" \
  test_exact_identity_match_succeeds

# 1 - Development identity fails closed
# 2 - Confirms an Apple Development certificate cannot satisfy release signing.
# 3 - Assumes the inventory contains no Developer ID Application certificate.
# 4 - Expects exact identity inventory validation to reject it.
test_development_identity_fails_closed() {
  local development_inventory
  development_inventory='  1) 0123456789ABCDEF0123456789ABCDEF01234567 "Apple Development: Example Developer (ABCDE12345)"'
  homeward_require_identity_inventory \
    "$expected_identity" \
    "ABCDE12345" \
    "$development_inventory"
}
assert_fails \
  "development identity fails closed" \
  "Expected exactly one usable codesigning identity named '$expected_identity'; found 0." \
  test_development_identity_fails_closed

# 1 - Name: Malformed identity fails closed
# 2 - Description: Confirms a non-matching Developer ID identity is rejected.
# 3 - Assumptions: The Team ID is valid so the identity gate is reached.
# 4 - Expectations: The exact identity diagnostic names the requested Team ID.
test_malformed_identity_fails_closed() {
  homeward_require_release_identity \
    "Developer ID Application: Example Developer (BADTEAM)" \
    "ABCDE12345"
}
assert_fails \
  "malformed identity fails closed" \
  "Identity must be an exact Developer ID Application identity for Team ID ABCDE12345." \
  test_malformed_identity_fails_closed

# 1 - Name: Malformed Team ID fails closed
# 2 - Description: Confirms a Team ID outside the exact format is rejected.
# 3 - Assumptions: Team ID syntax is checked before identity matching.
# 4 - Expectations: The exact ten-character Team ID diagnostic is emitted.
test_malformed_team_id_fails_closed() {
  homeward_require_release_identity "$expected_identity" "bad"
}
assert_fails \
  "malformed Team ID fails closed" \
  "Team ID must be exactly 10 uppercase letters or digits." \
  test_malformed_team_id_fails_closed

# 1 - Name: Missing notary profile fails closed
# 2 - Description: Confirms profile validation is independent from identity.
# 3 - Assumptions: An empty value represents an omitted Keychain profile name.
# 4 - Expectations: The exact single-line profile diagnostic is emitted.
test_missing_notary_profile_fails_closed() {
  homeward_require_notary_profile ""
}
assert_fails \
  "missing notary profile fails closed" \
  "A single-line notarytool Keychain profile name is required." \
  test_missing_notary_profile_fails_closed

non_ui_evidence="$temporary_root/non-ui-evidence.json"
ui_evidence="$temporary_root/ui-evidence.json"
cat >"$non_ui_evidence" <<'JSON'
{
  "appTreeSHA256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "binaryUUID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
  "build": "1",
  "dSYMTreeSHA256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  "schemaVersion": 2,
  "sourceSHA": "cccccccccccccccccccccccccccccccccccccccc",
  "uiTestsEnabled": false,
  "version": "0.1.0"
}
JSON
cat >"$ui_evidence" <<'JSON'
{
  "appTreeSHA256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "binaryUUID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
  "build": "1",
  "dSYMTreeSHA256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  "schemaVersion": 2,
  "sourceSHA": "cccccccccccccccccccccccccccccccccccccccc",
  "uiTestsEnabled": true,
  "version": "0.1.0"
}
JSON

# 1 - UI-disabled evidence fails closed
# 2 - Confirms a successful non-UI verification cannot authorize publication.
# 3 - Assumes every other schema-2 evidence field is valid.
# 4 - Expects the public evidence parser to reject uiTestsEnabled false.
test_ui_disabled_evidence_fails_closed() {
  homeward_read_release_evidence "$non_ui_evidence" 1
}
assert_fails \
  "UI-disabled evidence fails closed" \
  "Public release requires UI-enabled verification evidence" \
  test_ui_disabled_evidence_fails_closed

# 1 - Name: UI-disabled local evidence succeeds
# 2 - Description: Confirms non-UI evidence is valid for local packaging.
# 3 - Assumptions: Every other schema-2 evidence field is valid.
# 4 - Expectations: The validated record ends in the false UI-test value.
test_ui_disabled_local_evidence_succeeds() {
  local result
  result="$(homeward_read_release_evidence "$non_ui_evidence" 0)"
  [[ "$result" == $'cccccccccccccccccccccccccccccccccccccccc\taaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\tAAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE\tbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\t0.1.0\t1\tfalse' ]]
}
assert_passes \
  "UI-disabled local evidence succeeds" \
  test_ui_disabled_local_evidence_succeeds

# 1 - Valid UI-enabled evidence succeeds
# 2 - Confirms strict schema-2 evidence can pass the public evidence parser.
# 3 - Assumes hashes, UUID, source, version, and build use canonical formats.
# 4 - Expects one tab-delimited evidence record after validation.
test_valid_ui_evidence_succeeds() {
  local result
  result="$(homeward_read_release_evidence "$ui_evidence" 1)"
  [[ "$result" == $'cccccccccccccccccccccccccccccccccccccccc\taaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\tAAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE\tbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\t0.1.0\t1\ttrue' ]]
}
assert_passes \
  "valid UI-enabled evidence succeeds" \
  test_valid_ui_evidence_succeeds

printf '1..%d\n' "$tests_run"
