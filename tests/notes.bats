#!/usr/bin/env bats
#
# The release notes: sections, issue titles, the pull request and missing
# number fallbacks, and dedupe by issue.

load helpers/common

setup() {
  setup_fixture
}

@test "the reference dataset's release carries the reference notes" {
  build_reference_dataset
  given_reference_issues
  push_fixture

  run_release

  assert_success
  assert_golden "$(published_notes_file v1.0.0)" reference-notes.md
}

@test "empty sections are left out" {
  tag_version v1.0.0
  given_issue 4 "The cart total goes out of sync"
  commit_change "fix: keep the cart total in sync (#4)"
  push_fixture

  run_release

  assert_success
  run cat "$(published_notes_file v1.0.1)"
  assert_output "$(printf '### Bug fixes\n\n- The cart total goes out of sync (#4)\n')"
}

@test "a referenced number is looked up on this repository's issues" {
  tag_version v1.0.0
  given_issue 1 "Export the orders as CSV"
  commit_change "feat: export the orders as CSV (#1)"
  commit_change "docs: explain the export (#9999)"
  push_fixture

  run_release --dry-run

  assert_success
  run gh_calls
  assert_line "api repos/fixture-owner/fixture-repo/issues/1 --jq if has(\"pull_request\") then empty else .title end"
  assert_line "api repos/fixture-owner/fixture-repo/issues/9999 --jq if has(\"pull_request\") then empty else .title end"
}

@test "a commit without an issue reference needs no lookup" {
  tag_version v1.0.0
  commit_change "feat: dark mode for the dashboard"
  push_fixture

  run_release --dry-run

  assert_success
  refute_gh_call "api "
}
