#!/usr/bin/env bats
#
# The next version: the bump each commit type causes, the baseline, the first
# release and --level.

load helpers/common

setup() {
  setup_fixture
}

@test "a fix-only range bumps the patch" {
  tag_version v1.2.3
  commit_change "fix: keep the cart total in sync"
  push_fixture

  run_release --dry-run

  assert_success
  assert_line "Bump            : patch"
  assert_line "Version         : 1.2.3 -> 1.2.4"
}

@test "a feat bumps the minor and resets the patch" {
  tag_version v1.2.3
  commit_change "fix: keep the cart total in sync"
  commit_change "feat: export the orders as CSV"
  push_fixture

  run_release --dry-run

  assert_success
  assert_line "Bump            : minor"
  assert_line "Version         : 1.2.3 -> 1.3.0"
}

@test "a '!' after the type bumps the major and resets the rest" {
  tag_version v1.2.3
  commit_change "feat: export the orders as CSV"
  commit_change "feat(auth)!: drop the v1 authentication endpoints"
  push_fixture

  run_release --dry-run

  assert_success
  assert_line "Bump            : major"
  assert_line "Version         : 1.2.3 -> 2.0.0"
}

@test "a BREAKING CHANGE footer bumps the major" {
  tag_version v1.2.3
  commit_change "refactor: move the supabase client to its own module" \
    "BREAKING CHANGE: the supabase client is no longer exported from index.js"
  push_fixture

  run_release --dry-run

  assert_success
  assert_line "Version         : 1.2.3 -> 2.0.0"
}

@test "the BREAKING-CHANGE footer synonym bumps the major" {
  tag_version v1.2.3
  commit_change "perf: stream the order export" \
    "BREAKING-CHANGE: the export endpoint now returns NDJSON"
  push_fixture

  run_release --dry-run

  assert_success
  assert_line "Version         : 1.2.3 -> 2.0.0"
}

@test "BREAKING CHANGE in the body's prose doesn't bump the major" {
  tag_version v1.2.3
  commit_change "docs: describe the upgrade path" \
    "No BREAKING CHANGE here: the old flags still work."
  push_fixture

  run_release --dry-run

  assert_success
  assert_line "Version         : 1.2.3 -> 1.2.4"
}

@test "a merge commit doesn't count towards the bump" {
  tag_version v1.2.3
  git switch -q -c topic
  commit_change "fix: keep the cart total in sync"
  git switch -q main
  fixture_git merge -q --no-ff -m "feat!: merge the topic branch" topic
  push_fixture

  run_release --dry-run

  assert_success
  assert_line "Commits scanned : 1"
  assert_line "Version         : 1.2.3 -> 1.2.4"
}

@test "the baseline is the nearest version tag reachable from HEAD" {
  tag_version v1.0.0
  commit_change "feat: export the orders as CSV"
  tag_version v1.1.0
  commit_change "fix: keep the cart total in sync"
  push_fixture

  run_release --dry-run

  assert_success
  assert_line "Commit range    : v1.1.0..HEAD (last tag: v1.1.0)"
  assert_line "Commits scanned : 1"
  assert_line "Version         : 1.1.0 -> 1.1.1"
}

@test "tags that aren't version tags are ignored" {
  tag_version v1.0.0
  commit_change "feat: export the orders as CSV"
  tag_version release-2026
  tag_version v2.0
  git tag latest
  commit_change "fix: keep the cart total in sync"
  push_fixture

  run_release --dry-run

  assert_success
  assert_line "Commit range    : v1.0.0..HEAD (last tag: v1.0.0)"
  assert_line "Version         : 1.0.0 -> 1.1.0"
}

@test "the first release starts from 0.0.0 and scans the whole history" {
  commit_change "feat: export the orders as CSV"
  push_fixture

  run_release --dry-run

  assert_success
  assert_line "Commit range    : HEAD"
  assert_line "Commits scanned : 2"
  assert_line --regexp '^  other +[0-9a-f]{7} Initial commit$'
  assert_line "Version         : 0.0.0 -> 0.1.0"
}

@test "--level major declares a first release stable whatever the commits say" {
  commit_change "fix: keep the cart total in sync"
  push_fixture

  run_release --dry-run --level major

  assert_success
  assert_line "Bump            : major (forced with --level)"
  assert_line "Version         : 0.0.0 -> 1.0.0"
}

@test "--level overrides the bump the commits decide, downwards too" {
  tag_version v1.2.3
  commit_change "feat!: drop the v1 authentication endpoints"
  push_fixture

  run_release --dry-run --level patch

  assert_success
  assert_line "Bump            : patch (forced with --level)"
  assert_line "Version         : 1.2.3 -> 1.2.4"
}

@test "--level minor overrides the bump" {
  tag_version v1.2.3
  commit_change "fix: keep the cart total in sync"
  push_fixture

  run_release --dry-run --level minor

  assert_success
  assert_line "Version         : 1.2.3 -> 1.3.0"
}

@test "a range with no commit in it is nothing to release" {
  tag_version v1.2.3
  push_fixture

  run_release --dry-run

  assert_failure
  assert_output --partial "no commit to release in range 'v1.2.3..HEAD'"
}

@test "a shallow clone is refused before any version is computed" {
  tag_version v1.2.3
  commit_change "fix: keep the cart total in sync"
  push_fixture
  shallow_clone_fixture

  run_release --dry-run

  assert_failure
  assert_output --partial "shallow clone: the version tags behind the cut are unreachable"
  assert_output --partial "fetch-depth: 0"
  # The point of the guard: 0.0.0 never reaches the screen as this repository's
  # current version, so nothing downstream can act on it.
  refute_output --partial "Version         :"
}

@test "a version whose tag already exists is refused" {
  tag_version v1.0.0
  commit_change "fix: keep the cart total in sync"
  tag_version v1.0.1
  push_fixture

  run_release --dry-run --since v1.0.0 --to v1.0.1

  assert_failure
  assert_output --partial "tag v1.0.1 already exists locally"
}
