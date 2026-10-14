#!/usr/bin/env bats
#
# `release.sh --check`: the setup report. It runs every check of the preflight
# and every guard a release would weigh, lists them all with their reason and
# fix, and decides no version.

load helpers/common

setup() {
  setup_fixture
  push_fixture
}

@test "a setup that would release lists every check and exits 0" {
  run_check

  assert_success
  assert_golden_output setup-report-ok.txt
}

@test "a warning is listed but does not change the exit code" {
  git switch -q -c some-feature

  run_check

  assert_success
  assert_golden_output setup-report-warning.txt
}

@test "every failing check is listed, not only the first, and the exit code is 3" {
  given_gh_logged_out
  shallow_clone_fixture

  run_check --trunk main

  assert_failure 3
  assert_golden_output setup-report-failures.txt
}

@test "a trunk that does not carry the target fails the report, as it refuses a release" {
  commit_change "feat: export the orders as CSV"

  run_check

  assert_failure 3
  assert_output --partial "FAIL  the trunk carries HEAD"
  assert_output --partial "origin/main does not contain HEAD"
}

@test "a half-published release is a state, not a failure" {
  tag_version v1.0.0
  push_fixture

  run_check

  assert_success
  assert_output --partial "info  half-published release"
  assert_output --partial "v1.0.0 is on origin with no GitHub release: a release would resume it at step 4"
}

@test "a gh that is not logged in is a failing check, so 3" {
  given_gh_logged_out

  run_check

  assert_failure 3
  assert_output --partial "FAIL  gh is logged in"
  assert_output --partial "gh is not logged in — run: gh auth login"
}

@test "a missing gh cannot be evaluated, so 1" {
  PATH=$(path_without gh) run_check

  assert_failure 1
  assert_output --partial "GitHub CLI (gh) not found in PATH"
}

@test "a missing git cannot be evaluated, so 1" {
  PATH=$(path_without git) run_check

  assert_failure 1
  assert_output --partial "git not found in PATH"
}

@test "an option that shapes a release is refused with 1" {
  local option
  for option in "--yes" "--dry-run" "--local" "--level patch" "--notes n.md" "--changelog c.md" "--summary s.env"; do
    # shellcheck disable=SC2086
    run_check $option

    assert_failure 1
    assert_output --partial "--check accepts only --trunk, --to and --since"
  done
}

@test "--trunk, --to and --since name the target the report weighs" {
  tag_version v1.0.0
  commit_change "fix: keep the cart total in sync"
  push_fixture
  given_default_branch develop
  push_trunk_fixture develop

  run_check --trunk develop --to HEAD --since v1.0.0

  assert_success
  assert_output --partial "ok    the trunk 'develop' is reachable on origin"
}

@test "an unknown ref is a mistake in the command line, so 1" {
  run_check --to no-such-ref

  assert_failure 1
  assert_output --partial "unknown ref: no-such-ref"
}

@test "it decides no version and writes nothing" {
  tag_version v1.0.0
  commit_change "feat: export the orders as CSV"
  push_fixture

  run_check

  assert_success
  refute_output --partial "Step 1"
  refute_output --partial "v1.1.0"
  assert_no_release_created
  refute_local_tag v1.1.0
  refute_remote_tag v1.1.0
  [[ -z $(git status --porcelain) ]] || fail "the check changed the working tree: $(git status --porcelain)"
}

@test "with gh logged out and no --trunk, the checks that need the trunk are listed as skipped" {
  given_gh_logged_out

  run_check

  assert_failure 3
  assert_output --partial "skip  the trunk is known"
  assert_output --partial "skip  the release guards"
}
