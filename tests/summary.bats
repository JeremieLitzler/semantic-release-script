#!/usr/bin/env bats
#
# --summary: the release as key=value lines, for whatever runs the script.
#
# The exit code says how a run ended; this file says what it decided. CI reads
# it instead of grepping the human-readable output for a version, so the keys,
# their order and their values are the contract — asserted whole here, never a
# line at a time.

load helpers/common

setup() {
  setup_fixture
  SUMMARY="${BATS_TEST_TMPDIR}/summary.env"
}

# assert_summary <line...> — the summary holds exactly these lines, in this
# order. The whole file rather than a grep: the keys a consumer reads are the
# contract, and one that silently went missing should fail here.
assert_summary() {
  [[ -f $SUMMARY ]] || fail "no summary was written to ${SUMMARY}"
  assert_equal "$(cat "$SUMMARY")" "$(printf '%s\n' "$@")"
}

# refute_summary — no summary at all. A run that decided no version has none to
# write, so it writes none: the path is left as it was found, which is why a
# consumer reads the exit code before the file.
refute_summary() {
  [[ ! -e $SUMMARY ]] || fail "a summary was written: $(cat "$SUMMARY")"
}

@test "a released run writes the five keys, released=yes" {
  tag_version v1.0.0
  commit_change "feat: export the orders as CSV"
  push_fixture

  run_release --summary "$SUMMARY"

  assert_success
  assert_line "Summary written to ${SUMMARY}"
  assert_summary \
    "tag=v1.1.0" \
    "version=1.1.0" \
    "bump=minor" \
    "baseline=1.0.0" \
    "released=yes"
}

@test "--dry-run writes the release it previewed, with released=no" {
  tag_version v1.0.0
  commit_change "feat!: drop the v1 authentication endpoints"
  push_fixture

  run_release --dry-run --summary "$SUMMARY"

  assert_success
  assert_summary \
    "tag=v2.0.0" \
    "version=2.0.0" \
    "bump=major" \
    "baseline=1.0.0" \
    "released=no"
}

@test "--local writes released=no: the tag stays on the machine, nothing carries its notes" {
  tag_version v1.0.0
  commit_change "fix: keep the cart total in sync"
  push_fixture

  run_release --local --summary "$SUMMARY"

  assert_success
  assert_local_tag v1.0.1 HEAD
  assert_summary \
    "tag=v1.0.1" \
    "version=1.0.1" \
    "bump=patch" \
    "baseline=1.0.0" \
    "released=no"
}

@test "a first release writes baseline=0.0.0, the version the bump was applied to" {
  commit_change "feat: export the orders as CSV"
  push_fixture

  run_release --dry-run --summary "$SUMMARY"

  assert_success
  assert_summary \
    "tag=v0.1.0" \
    "version=0.1.0" \
    "bump=minor" \
    "baseline=0.0.0" \
    "released=no"
}

@test "the bump --level forced is the one the summary reports" {
  tag_version v1.2.3
  commit_change "feat!: drop the v1 authentication endpoints"
  push_fixture

  run_release --dry-run --level patch --summary "$SUMMARY"

  assert_success
  assert_summary \
    "tag=v1.2.4" \
    "version=1.2.4" \
    "bump=patch" \
    "baseline=1.2.3" \
    "released=no"
}

@test "baseline is the version the range's start carries, even when --since is no version tag" {
  tag_version v1.0.0
  commit_change "fix: keep the cart total in sync"
  commit_change "feat: export the orders as CSV"
  push_fixture

  run_release --dry-run --since HEAD~1 --summary "$SUMMARY"

  assert_success
  assert_summary \
    "tag=v1.1.0" \
    "version=1.1.0" \
    "bump=minor" \
    "baseline=1.0.0" \
    "released=no"
}

@test "a resume writes bump=none: the version was read off the tag, not computed" {
  tag_version v1.0.0
  commit_change "feat: export the orders as CSV"
  tag_version v1.1.0
  push_fixture

  run_release --summary "$SUMMARY"

  assert_success
  assert_line --partial "v1.1.0 is on origin with no GitHub release"
  assert_summary \
    "tag=v1.1.0" \
    "version=1.1.0" \
    "bump=none" \
    "baseline=1.0.0" \
    "released=yes"
}

@test "a resume previewed with --dry-run writes released=no" {
  tag_version v1.0.0
  commit_change "feat: export the orders as CSV"
  tag_version v1.1.0
  push_fixture

  run_release --dry-run --summary "$SUMMARY"

  assert_success
  assert_summary \
    "tag=v1.1.0" \
    "version=1.1.0" \
    "bump=none" \
    "baseline=1.0.0" \
    "released=no"
}

@test "nothing to release writes no summary: the run decided no version" {
  tag_version v1.2.3
  push_fixture
  given_release v1.2.3

  run_release --dry-run --summary "$SUMMARY"

  assert_failure 2
  refute_summary
}

@test "a guard refusing the release writes no summary" {
  tag_version v1.0.0
  commit_change "fix: keep the cart total in sync"
  tag_version v1.0.1
  push_fixture
  given_release v1.0.1

  run_release --dry-run --since v1.0.0 --to v1.0.1 --summary "$SUMMARY"

  assert_failure 3
  refute_summary
}

@test "an error before the version writes no summary" {
  tag_version v1.0.0
  commit_change "feat: export the orders as CSV"
  push_fixture

  run_release --dry-run --since v9.9.9 --summary "$SUMMARY"

  assert_failure 1
  refute_summary
}

@test "a run that decided no version leaves a previous run's summary exactly as it was" {
  tag_version v1.2.3
  push_fixture
  given_release v1.2.3
  printf 'tag=v1.2.3\nversion=1.2.3\nbump=patch\nbaseline=1.2.2\nreleased=yes\n' >"$SUMMARY"

  run_release --dry-run --summary "$SUMMARY"

  # Left alone, not cleared: the path is the caller's, and this run has no
  # answer to put there. Which is why a consumer reads the exit code first.
  assert_failure 2
  assert_summary \
    "tag=v1.2.3" \
    "version=1.2.3" \
    "bump=patch" \
    "baseline=1.2.2" \
    "released=yes"
}

@test "a stale summary from a previous run is replaced, not appended to" {
  tag_version v1.0.0
  commit_change "feat: export the orders as CSV"
  push_fixture
  printf 'tag=v0.0.9\nversion=0.0.9\nstale=yes\n' >"$SUMMARY"

  run_release --dry-run --summary "$SUMMARY"

  assert_success
  assert_summary \
    "tag=v1.1.0" \
    "version=1.1.0" \
    "bump=minor" \
    "baseline=1.0.0" \
    "released=no"
}

@test "--summary creates the folders its path names" {
  tag_version v1.0.0
  commit_change "feat: export the orders as CSV"
  push_fixture
  SUMMARY="${BATS_TEST_TMPDIR}/ci/out/summary.env"

  run_release --dry-run --summary "$SUMMARY"

  assert_success
  assert_summary \
    "tag=v1.1.0" \
    "version=1.1.0" \
    "bump=minor" \
    "baseline=1.0.0" \
    "released=no"
}

@test "the summary is shell- and GITHUB_OUTPUT-safe: bare key=value, one per line" {
  tag_version v1.0.0
  commit_change "feat: export the orders as CSV"
  push_fixture

  run_release --dry-run --summary "$SUMMARY"

  assert_success
  # No quoting, no spaces around the '=', nothing but the five keys: what a
  # consumer sources, or appends to $GITHUB_OUTPUT.
  run grep -cvE '^(tag|version|bump|baseline|released)=[A-Za-z0-9.]+$' "$SUMMARY"
  assert_output "0"

  # Sourcing it is the point of the format.
  # shellcheck disable=SC1090
  ( set -a; . "$SUMMARY"; [[ $version == 1.1.0 && $released == no ]] ) \
    || fail "the summary does not source into the five variables"
}
