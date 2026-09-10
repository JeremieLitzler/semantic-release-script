#!/usr/bin/env bats
#
# Replay: rebuilding past releases over explicit commit ranges with --since
# and --to.

load helpers/common

setup() {
  setup_fixture
  build_reference_dataset
  given_reference_issues
  push_fixture
}

@test "--to releases an older commit and tags it there, not on HEAD" {
  run_release --to "${REFERENCE_COMMITS[8]}"

  assert_success
  assert_line "Target ref      : ${REFERENCE_COMMITS[8]} (tag will be created there, not on HEAD)"
  assert_line "Commits scanned : 9"
  assert_line "Version         : 0.0.0 -> 0.0.1"
  assert_local_tag v0.0.1 "${REFERENCE_COMMITS[8]}"
  assert_remote_tag v0.0.1
}

@test "replaying the dataset oldest first chains the versions and the changelog" {
  local changelog="${BATS_TEST_TMPDIR}/CHANGELOG.md"

  run_release --to "${REFERENCE_COMMITS[8]}" --changelog "$changelog"
  assert_success
  assert_line "Version         : 0.0.0 -> 0.0.1"

  # Once a version tag exists, the baseline is the nearest version tag of --to.
  run_release --to "${REFERENCE_COMMITS[12]}" --changelog "$changelog"
  assert_success
  assert_line "Commit range    : v0.0.1..${REFERENCE_COMMITS[12]} (last tag: v0.0.1)"
  assert_line "Version         : 0.0.1 -> 0.1.0"

  run_release --to "${REFERENCE_COMMITS[14]}" --changelog "$changelog"
  assert_success
  assert_line "Version         : 0.1.0 -> 1.0.0"

  assert_local_tag v0.0.1 "${REFERENCE_COMMITS[8]}"
  assert_local_tag v0.1.0 "${REFERENCE_COMMITS[12]}"
  assert_local_tag v1.0.0 "${REFERENCE_COMMITS[14]}"
  assert_golden "$(published_notes_file v0.0.1)" replay-v0.0.1-notes.md
  assert_golden "$(published_notes_file v0.1.0)" replay-v0.1.0-notes.md
  assert_golden "$(published_notes_file v1.0.0)" replay-v1.0.0-notes.md
  # Today --changelog writes the headings without the notes (#36): pinned until
  # it is fixed.
  normalise_changelog_dates "$changelog"
  assert_golden "$changelog" replay-changelog.md
}

@test "--since a commit that isn't a version tag takes the baseline from its nearest version tag" {
  tag_version v0.0.1 "${REFERENCE_COMMITS[8]}"
  push_fixture

  run_release --since "${REFERENCE_COMMITS[10]}" --to "${REFERENCE_COMMITS[12]}" \
    --notes "${BATS_TEST_TMPDIR}/notes.md"

  assert_success
  assert_line "Commits scanned : 2"
  assert_line "Version         : 0.0.1 -> 0.1.0"
  assert_local_tag v0.1.0 "${REFERENCE_COMMITS[12]}"
  run cat "${BATS_TEST_TMPDIR}/notes.md"
  assert_line --partial "feat(search): remember the last query (#9999)"
  assert_line --partial "feat: dark mode for the dashboard"
  refute_line --partial "${MONTHLY_INVOICES_TITLE}"
}

@test "--since a commit with no version tag behind it takes 0.0.0 as the baseline" {
  run_release --dry-run --since "${REFERENCE_COMMITS[5]}" --to "${REFERENCE_COMMITS[8]}"

  assert_success
  assert_line "Commits scanned : 3"
  assert_line "Version         : 0.0.0 -> 0.0.1"
}

@test "an unknown --to ref fails" {
  run_release --dry-run --to no-such-ref

  assert_failure 1
  assert_output --partial "unknown ref: no-such-ref"
}

@test "an unknown --since ref fails" {
  run_release --dry-run --since no-such-ref

  assert_failure 1
  assert_output --partial "unknown ref: no-such-ref"
}
