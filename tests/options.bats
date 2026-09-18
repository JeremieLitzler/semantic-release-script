#!/usr/bin/env bats
#
# The options and the preflight checks: --notes, --changelog, --trunk, --help,
# bad arguments, and what release.sh needs from its environment.

load helpers/common

setup() {
  setup_fixture
  tag_version v1.0.0
  given_issue 1 "Export the orders as CSV"
  commit_change "feat: export the orders as CSV (#1)"
  push_fixture
}

@test "--notes also writes the published notes to a file" {
  run_release --notes "${BATS_TEST_TMPDIR}/notes.md"

  assert_success
  assert_line "Notes also written to ${BATS_TEST_TMPDIR}/notes.md"
  assert_equal "$(cat "${BATS_TEST_TMPDIR}/notes.md")" "$(cat "$(published_notes_file v1.1.0)")"
}

@test "--changelog creates the file and its folders, under a dated heading" {
  local changelog="${BATS_TEST_TMPDIR}/docs/releases/CHANGELOG.md"

  run_release --dry-run --changelog "$changelog"

  assert_success
  assert_line "Changelog updated: ${changelog}"
  normalise_changelog_dates "$changelog"
  # Today --changelog writes the heading without the notes (#36): pinned until
  # it is fixed.
  assert_equal "$(cat "$changelog")" "$(printf '# Changelog\n\n## v1.1.0 (<date>)\n')"
}

@test "--changelog puts the new release on top of the previous ones" {
  local changelog="${BATS_TEST_TMPDIR}/CHANGELOG.md"
  printf '# Changelog\n\n## v1.0.0 (2026-01-01)\n\n### Features\n\n- An older feature\n' >"$changelog"

  run_release --dry-run --changelog "$changelog"

  assert_success
  normalise_changelog_dates "$changelog"
  assert_equal "$(cat "$changelog")" \
    "$(printf '# Changelog\n\n## v1.1.0 (<date>)\n\n## v1.0.0 (<date>)\n\n### Features\n\n- An older feature\n')"
}

@test "--help prints the usage and exits" {
  run bash "$RELEASE_SH" --help

  assert_success
  assert_line --index 0 "release.sh — semantic release from conventional commits."
  assert_output --partial "Usage: release.sh [options]"
  assert_no_release_created
}

@test "an unknown option fails with the usage" {
  run_release --bogus

  assert_failure
  assert_output --partial "Usage: release.sh [options]"
  assert_output --partial "unknown option: --bogus"
}

@test "--level only accepts major, minor or patch" {
  run_release --level huge

  assert_failure
  assert_output --partial "--level must be one of: major, minor, patch"
}

@test "the options taking a value fail without one" {
  local option
  for option in --since --to --notes --changelog --trunk; do
    run_release "$option"
    assert_failure
    assert_output --partial "${option} needs a"
  done
}

@test "a gh that isn't logged in stops the release before anything" {
  given_gh_logged_out

  run_release

  assert_failure
  assert_output --partial "gh is not logged in — run: gh auth login"
  refute_local_tag v1.1.0
  assert_no_release_created
}

@test "outside a git repository the release fails" {
  mkdir "${BATS_TEST_TMPDIR}/not-a-repo"
  cd "${BATS_TEST_TMPDIR}/not-a-repo"

  run_release --dry-run

  assert_failure
  assert_output --partial "not inside a git repository"
}

@test "the trunk is GitHub's default branch, not 'main'" {
  given_default_branch develop
  push_trunk_fixture develop
  git switch -q -c develop

  run_release --dry-run

  assert_success
  refute_output --partial "you are on"
}

@test "a branch that is neither the trunk nor a release branch only warns" {
  given_default_branch develop
  push_trunk_fixture develop

  run_release --dry-run

  assert_success
  assert_output --partial "you are on 'main', not 'develop' or a 'release/*' branch"
}

@test "a release branch cut off the trunk is accepted" {
  git switch -q -c release/2026-09-10

  run_release --dry-run

  assert_success
  refute_output --partial "you are on"
}

@test "a detached HEAD is accepted" {
  git switch -q --detach

  run_release --dry-run

  assert_success
  refute_output --partial "you are on"
}

@test "--trunk names the trunk instead of asking GitHub" {
  given_default_branch main
  push_trunk_fixture develop
  git switch -q -c develop

  run_release --dry-run --trunk develop

  assert_success
  refute_output --partial "you are on"
  refute_gh_call "repo view --json defaultBranchRef"
}

@test "a repository with no default branch fails, pointing at --trunk" {
  given_no_default_branch

  run_release --dry-run

  assert_failure
  assert_output --partial "cannot resolve the trunk — name it with --trunk <name>"
}

@test "a dirty working tree only warns" {
  printf 'uncommitted\n' >>CHANGES.md

  run_release --dry-run

  assert_success
  assert_output --partial "the working tree is not clean; the tag will only contain committed work"
}

@test "a release branch with a commit the trunk doesn't carry is refused" {
  git switch -q -c release/2026-09-18
  commit_change "chore: bump the version in package.json"

  run_release

  assert_failure
  assert_output --partial "origin/main does not contain HEAD"
  assert_output --partial "the tag would sit on a commit the trunk cannot reach"
  # The guard sits before the version, like the shallow and stale-tag ones, so
  # nothing downstream sees a version for a commit that was never tagged.
  refute_output --partial "Version         :"
  refute_local_tag v1.1.0
  refute_remote_tag v1.1.0
  assert_no_release_created
}

@test "a commit on the trunk that origin hasn't seen is refused, and writes no tag" {
  commit_change "fix: keep the cart total in sync"

  run_release --local

  assert_failure
  assert_output --partial "origin/main does not contain HEAD"
  refute_local_tag v1.1.0
}

# --dry-run is the one flag that gets past this guard, and it has to: a
# consumer previewing a pull request's release runs on the PR head, which the
# trunk does not contain and will not until it merges. Nothing is tagged, so
# there is nothing to strand — but the preview still says what a real run
# would do.
@test "--dry-run previews a ref the trunk doesn't carry, and warns instead" {
  git switch -q -c release/2026-09-18
  commit_change "chore: bump the version in package.json"

  run_release --dry-run

  assert_success
  assert_output --partial "origin/main does not contain HEAD"
  assert_output --partial "a real run would refuse to tag there"
  assert_line "Version         : 1.0.0 -> 1.1.0"
  refute_local_tag v1.1.0
}

# A trunk origin holds no branch for is the caller naming one that does not
# exist, which verify_ref already calls a mistake in the command line rather
# than a refusal: code 1, not 3. origin itself is known reachable by now, since
# resolve_baseline just fetched the tags from it.
@test "a trunk origin doesn't hold is an error, repeating what git said" {
  run_release --dry-run --trunk no-such-branch

  assert_failure 1
  assert_output --partial "couldn't find remote ref no-such-branch"
  assert_output --partial "cannot fetch the trunk 'no-such-branch' from origin"
  assert_output --partial "--trunk <name>"
  refute_output --partial "Version         :"
}
