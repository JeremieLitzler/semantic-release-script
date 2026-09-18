#!/usr/bin/env bats
#
# The exit codes release.sh promises its callers. They are its contract with
# CI, which needs to tell a trunk with nothing to release from a run that went
# wrong, so each one is pinned here with the smallest history that reaches it.
#
# This file is the only place release.sh's own codes are asserted. The other
# suites cover the same paths for their messages and their effects, with a bare
# `assert_failure`, so a code that changes fails here and nowhere else. The two
# `assert_failure 1` left elsewhere are gh's exit code under --verify-tag, not
# release.sh's: publish.bats runs the fake, live.bats the real one.

load helpers/common

setup() {
  setup_fixture
}

@test "a published release exits 0" {
  tag_version v1.0.0
  commit_change "feat: export the orders as CSV"
  push_fixture

  run_release

  assert_success
  assert_line "Released v1.1.0"
}

@test "a preview exits 0, under --dry-run and under --local alike" {
  tag_version v1.0.0
  commit_change "feat: export the orders as CSV"
  push_fixture

  run_release --dry-run
  assert_success

  run_release --local
  assert_success
}

@test "nothing to release exits 2, and still says so" {
  tag_version v1.2.3
  push_fixture

  run_release --dry-run

  assert_failure 2
  # The wording consumers grep for until they read the code instead.
  assert_output --partial "no commit to release in range 'v1.2.3..HEAD'"
}

@test "a guard refusing the release exits 3" {
  tag_version v1.0.0
  commit_change "fix: keep the cart total in sync"
  tag_version v1.0.1
  push_fixture

  run_release --dry-run --since v1.0.0 --to v1.0.1

  assert_failure 3
  assert_output --partial "tag v1.0.1 already exists locally"
}

@test "an unknown ref exits 1: a mistake in the command line, not a refusal" {
  tag_version v1.0.0
  commit_change "fix: keep the cart total in sync"
  push_fixture

  run_release --dry-run --since v9.9.9

  assert_failure 1
  assert_output --partial "unknown ref: v9.9.9"
}

@test "a bad option exits 1" {
  run_release --bogus

  assert_failure 1
  assert_output --partial "unknown option: --bogus"
}

@test "--help exits 0 and documents the codes" {
  run bash "$RELEASE_SH" --help

  assert_success
  assert_line "Exit codes:"
  assert_line "  0  released, or previewed with --dry-run or --local"
  assert_line "  1  error: bad usage, a missing tool, a failed push"
  assert_line "  2  nothing to release in the commit range"
  assert_line "  3  refused by a guard"
}
