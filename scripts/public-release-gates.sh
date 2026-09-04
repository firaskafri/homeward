#!/bin/bash

# Shared fail-closed checks for the public Developer ID release workflow.

homeward_release_error() {
  printf '%s\n' "$1" >&2
  return 1
}

homeward_require_release_identity() {
  local identity="$1"
  local team_id="$2"

  if [[ ! "$team_id" =~ ^[A-Z0-9]{10}$ ]]; then
    homeward_release_error "Team ID must be exactly 10 uppercase letters or digits."
    return 1
  fi
  if [[ "$identity" != Developer\ ID\ Application:\ *\ \("$team_id"\) ]]; then
    homeward_release_error \
      "Identity must be an exact Developer ID Application identity for Team ID $team_id."
    return 1
  fi
}

homeward_require_notary_profile() {
  local notary_profile="$1"

  if [[ -z "$notary_profile" ||
        "$notary_profile" == *$'\n'* ||
        "$notary_profile" == *$'\r'* ]]; then
    homeward_release_error "A single-line notarytool Keychain profile name is required."
    return 1
  fi
}

homeward_require_clean_tree() {
  local repository_root="$1"

  if [[ -n "$(git -C "$repository_root" status --porcelain --untracked-files=all)" ]]; then
    homeward_release_error "Public release requires a clean working tree."
    return 1
  fi
}

homeward_require_pushed_head() {
  local repository_root="$1"
  local branch
  local head_sha
  local merge_ref
  local remote
  local remote_sha

  if ! branch="$(git -C "$repository_root" symbolic-ref --quiet --short HEAD)"; then
    homeward_release_error "Public release requires a checked-out branch."
    return 1
  fi
  if ! remote="$(git -C "$repository_root" config --get "branch.$branch.remote")"; then
    homeward_release_error "Public release branch has no configured remote."
    return 1
  fi
  if ! merge_ref="$(git -C "$repository_root" config --get "branch.$branch.merge")"; then
    homeward_release_error "Public release branch has no configured upstream."
    return 1
  fi
  if [[ "$remote" == "." ]]; then
    homeward_release_error "Public release upstream must be a remote repository."
    return 1
  fi

  head_sha="$(git -C "$repository_root" rev-parse HEAD)"
  if ! remote_sha="$(
    git -C "$repository_root" ls-remote --exit-code "$remote" "$merge_ref" |
      awk 'NR == 1 { value = $1 } END { if (NR == 1) print value; else exit 1 }'
  )"; then
    homeward_release_error \
      "Could not prove that HEAD is present at the configured remote upstream."
    return 1
  fi
  if [[ "$remote_sha" != "$head_sha" ]]; then
    homeward_release_error "Public release requires HEAD to match the pushed upstream."
    return 1
  fi
}

homeward_require_signed_release_tag() {
  local repository_root="$1"
  local expected_tag="$2"
  local branch
  local head_sha
  local local_tag_object
  local remote
  local remote_tag_object
  local remote_tag_records
  local remote_tag_target
  local tag_sha

  if [[ ! "$expected_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    homeward_release_error "Expected release tag is invalid: $expected_tag"
    return 1
  fi
  if [[ "$(git -C "$repository_root" cat-file -t "refs/tags/$expected_tag" 2>/dev/null)" != "tag" ]]; then
    homeward_release_error \
      "Public release requires the annotated tag $expected_tag."
    return 1
  fi

  head_sha="$(git -C "$repository_root" rev-parse HEAD)"
  tag_sha="$(git -C "$repository_root" rev-parse "refs/tags/$expected_tag^{}")"
  if [[ "$tag_sha" != "$head_sha" ]]; then
    homeward_release_error "Tag $expected_tag does not resolve to HEAD."
    return 1
  fi
  if ! git -C "$repository_root" verify-tag "$expected_tag" >/dev/null; then
    homeward_release_error "Tag $expected_tag does not have a valid Git signature."
    return 1
  fi

  if ! branch="$(git -C "$repository_root" symbolic-ref --quiet --short HEAD)"; then
    homeward_release_error "Public release requires a checked-out branch."
    return 1
  fi
  if ! remote="$(git -C "$repository_root" config --get "branch.$branch.remote")"; then
    homeward_release_error "Public release branch has no configured remote."
    return 1
  fi
  local_tag_object="$(git -C "$repository_root" rev-parse "refs/tags/$expected_tag")"
  if ! remote_tag_records="$(
    git -C "$repository_root" ls-remote --tags --exit-code "$remote" \
      "refs/tags/$expected_tag" \
      "refs/tags/$expected_tag^{}"
  )"; then
    homeward_release_error "Tag $expected_tag has not been pushed to $remote."
    return 1
  fi
  remote_tag_object="$(
    awk -v ref="refs/tags/$expected_tag" '$2 == ref { print $1 }' \
      <<<"$remote_tag_records"
  )"
  remote_tag_target="$(
    awk -v ref="refs/tags/$expected_tag^{}" '$2 == ref { print $1 }' \
      <<<"$remote_tag_records"
  )"
  if [[ "$remote_tag_object" != "$local_tag_object" ||
        "$remote_tag_target" != "$head_sha" ]]; then
    homeward_release_error \
      "Remote tag $expected_tag does not exactly match the signed local tag at HEAD."
    return 1
  fi
}

homeward_require_identity_inventory() {
  local identity="$1"
  local team_id="$2"
  local inventory="$3"
  local matches=0
  local line

  homeward_require_release_identity "$identity" "$team_id" ||
    return 1
  while IFS= read -r line; do
    if [[ "$line" == *"\"$identity\""* ]]; then
      ((matches += 1))
    fi
  done <<<"$inventory"

  if [[ "$matches" != "1" ]]; then
    homeward_release_error \
      "Expected exactly one usable codesigning identity named '$identity'; found $matches."
    return 1
  fi
}
