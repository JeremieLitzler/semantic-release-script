#!/usr/bin/env bats
#
# The options and the preflight checks: --notes, --changelog, --help, bad
# arguments, and what release.sh needs from its environment.

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

  assert_failure 1
  assert_output --partial "Usage: release.sh [options]"
  assert_output --partial "unknown option: --bogus"
}

@test "--level only accepts major, minor or patch" {
  run_release --level huge

  assert_failure 1
  assert_output --partial "--level must be one of: major, minor, patch"
}

@test "the options taking a value fail without one" {
  local option
  for option in --since --to --notes --changelog; do
    run_release "$option"
    assert_failure 1
    assert_output --partial "${option} needs a"
  done
}

@test "a gh that isn't logged in stops the release before anything" {
  given_gh_logged_out

  run_release

  assert_failure 1
  assert_output --partial "gh is not logged in — run: gh auth login"
  refute_local_tag v1.1.0
  assert_no_release_created
}

@test "outside a git repository the release fails" {
  mkdir "${BATS_TEST_TMPDIR}/not-a-repo"
  cd "${BATS_TEST_TMPDIR}/not-a-repo"

  run_release --dry-run

  assert_failure 1
  assert_output --partial "not inside a git repository"
}

@test "a branch other than main only warns" {
  git switch -q -c release/2026-09-10

  run_release --dry-run

  assert_success
  assert_output --partial "you are on 'release/2026-09-10', not 'main'"
}

@test "a dirty working tree only warns" {
  printf 'uncommitted\n' >>CHANGES.md

  run_release --dry-run

  assert_success
  assert_output --partial "the working tree is not clean; the tag will only contain committed work"
}
