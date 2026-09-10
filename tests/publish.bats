#!/usr/bin/env bats
#
# Publishing: the tag and its push, the GitHub release, --dry-run and --local.

load helpers/common

setup() {
  setup_fixture
  tag_version v1.0.0
  given_issue 1 "Export the orders as CSV"
  commit_change "feat: export the orders as CSV (#1)"
  push_fixture
}

@test "a release pushes an annotated version tag on HEAD, then creates the GitHub release from it" {
  run_release

  assert_success
  assert_line "Tag v1.1.0 created on $(git rev-parse --short HEAD)."
  assert_line "Tag v1.1.0 pushed to origin."
  assert_line "Released v1.1.0"
  assert_line "https://github.com/fixture-owner/fixture-repo/releases/tag/v1.1.0"
  assert_local_tag v1.1.0 HEAD
  assert_equal "$(git cat-file -t v1.1.0)" tag
  assert_remote_tag v1.1.0

  run gh_calls
  assert_line --index 0 "auth status"
  assert_line --index 1 "repo view --json nameWithOwner --jq .nameWithOwner"
  assert_line --regexp '^release create v1\.1\.0 --repo fixture-owner/fixture-repo --title v1\.1\.0 --notes-file .+ --verify-tag$'

  run cat "$(published_notes_file v1.1.0)"
  assert_output "$(printf '### Features\n\n- Export the orders as CSV (#1)\n')"
}

@test "--dry-run pushes no tag and creates no release" {
  run_release --dry-run

  assert_success
  assert_line "[dry-run] git tag -a v1.1.0 -m v1.1.0 HEAD"
  assert_line "[dry-run] git push origin v1.1.0"
  assert_line "[dry-run] no tag was pushed, so no release was created"
  refute_local_tag v1.1.0
  refute_remote_tag v1.1.0
  assert_no_release_created
}

@test "--local creates the tag but neither pushes it nor creates the release" {
  run_release --local

  assert_success
  assert_line "[local] not pushed to origin"
  assert_line "[local] the tag stays on this machine, so no release was created"
  assert_local_tag v1.1.0 HEAD
  refute_remote_tag v1.1.0
  assert_no_release_created
}

@test "a rejected push deletes the local tag and creates no release" {
  printf '#!/bin/sh\necho "push rejected by the test" >&2\nexit 1\n' >"${ORIGIN}/hooks/pre-receive"
  chmod +x "${ORIGIN}/hooks/pre-receive"

  run_release

  assert_failure 1
  assert_output --partial "pushing v1.1.0 failed — the local tag has been deleted, nothing was released"
  refute_local_tag v1.1.0
  refute_remote_tag v1.1.0
  assert_no_release_created
}

@test "tags only origin holds are fetched before the version is computed" {
  git tag -d v1.0.0 >/dev/null

  run_release --dry-run

  assert_success
  assert_line "Version         : 1.0.0 -> 1.1.0"
}

@test "an origin that can't be fetched only warns" {
  git remote set-url origin "${BATS_TEST_TMPDIR}/no-such-origin.git"

  run_release --dry-run

  assert_success
  assert_output --partial "could not fetch tags from origin"
  assert_line "Version         : 1.0.0 -> 1.1.0"
}

@test "the fake gh refuses to publish a tag origin doesn't hold (--verify-tag)" {
  printf 'notes\n' >"${BATS_TEST_TMPDIR}/notes.md"

  run gh release create v9.9.9 --repo "$FIXTURE_REPO_NAME" --title v9.9.9 \
    --notes-file "${BATS_TEST_TMPDIR}/notes.md" --verify-tag

  assert_failure 1
  assert_output "tag v9.9.9 doesn't exist in the repo fixture-owner/fixture-repo, aborting due to --verify-tag flag"
}
