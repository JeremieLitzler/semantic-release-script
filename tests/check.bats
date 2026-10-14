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

@test "a tag a release would write that already exists fails the report, as it refuses a release" {
  tag_version v1.0.0
  commit_change "fix: keep the cart total in sync"
  tag_version v1.0.1
  push_fixture
  given_release v1.0.1

  run_check --since v1.0.0 --to v1.0.1

  assert_failure 3
  assert_output --partial "FAIL  the next tag is free"
  assert_output --partial "tag v1.0.1 already exists locally"
  refute_output --partial "ok    the next tag is free"
}

@test "a version below a tag already in the repository fails the report, as it refuses a release" {
  tag_version v1.0.0
  commit_change "feat: export the orders as CSV"
  tag_version v2.0.0
  commit_change "fix: keep the cart total in sync"
  push_fixture
  given_release v1.0.0
  given_release v2.0.0

  run_check --since v1.0.0

  assert_failure 3
  assert_output --partial "ok    the next tag is free"
  assert_output --partial "FAIL  the next version is higher than every version tag"
  assert_output --partial "v1.1.0 is not higher than v2.0.0"
  assert_output --partial "--since"
}

@test "the guards weigh a release over the range since the latest tag as passing" {
  tag_version v1.0.0
  commit_change "feat: export the orders as CSV"
  push_fixture
  given_release v1.0.0

  run_check

  assert_success
  assert_output --partial "ok    the next tag is free"
  assert_output --partial "ok    the next version is higher than every version tag"
}

@test "a range with no commit leaves the version guards unweighed, and is not a failure" {
  tag_version v1.0.0
  push_fixture
  given_release v1.0.0

  run_check

  assert_success
  assert_output --partial "info  the next tag is free"
  assert_output --partial "nothing to release (exit 2)"
}

@test "a half-published release leaves the version guards unweighed" {
  tag_version v1.0.0
  push_fixture

  run_check

  assert_success
  assert_output --partial "info  the next tag is free"
  assert_output --partial "a release would resume v1.0.0, which writes no tag"
}

@test "stale tags fail the report and leave the version guards skipped" {
  tag_version v1.0.0
  push_fixture
  given_release v1.0.0
  commit_change "fix: keep the cart total in sync"
  unreachable_origin_fixture

  run_check

  assert_failure 3
  assert_output --partial "FAIL  the version tags can be fetched from origin"
  assert_output --partial "skip  the next tag is free"
}

@test "a stranded tag fails the report: the trunk does not carry the target" {
  tag_version v1.0.0
  push_fixture
  given_release v1.0.0
  git switch -q -c release/1.1
  commit_change "fix: keep the cart total in sync"
  tag_version v1.0.1

  run_check --to v1.0.1

  assert_failure 3
  assert_output --partial "FAIL  the trunk carries v1.0.1"
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
