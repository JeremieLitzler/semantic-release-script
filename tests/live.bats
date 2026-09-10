#!/usr/bin/env bats
#
# The live suite: keeps the fake gh honest against real GitHub.
#
# Opt-in with LIVE=1, never in CI. It runs the real gh, logged in as you, only
# ever against the sandbox, in a fresh clone in a temp dir. Its issues and pull
# request are seeded once by tests/live/seed-sandbox.sh.
#
# The full release resets the sandbox's `main` to "Initial commit" and pushes
# the reference dataset, releases v1.0.0, then diffs the notes against the
# reference golden. It deletes the release and the tag and resets `main` again
# on success only: after a failure they stay on GitHub for inspection, and the
# next run's reset clears them.

load helpers/common

SANDBOX="JeremieLitzler/semantic-release-script-tests"
MISSING_ISSUE=9999

setup() {
  [[ ${LIVE:-} == 1 ]] || skip "live suite: run with LIVE=1 (gh logged in with write access to ${SANDBOX})"
  load_reference_issues
}

# assert_seeded <number> <title> <true|false: is a pull request>
assert_seeded() {
  local actual
  actual=$(gh api "repos/${SANDBOX}/issues/$1" --jq '[.title, has("pull_request")] | @tsv') \
    || fail "#$1 is missing from ${SANDBOX}: run tests/live/seed-sandbox.sh"
  [[ $actual == "$2"$'\t'"$3" ]] \
    || fail "#$1 in ${SANDBOX} is '${actual}', expected '$2' (pull request: $3): run tests/live/seed-sandbox.sh"
}

# normalise_notes <file> — the notes with the repository and the commit hashes
# replaced by placeholders, and no trailing blank line.
normalise_notes() {
  printf '%s\n' "$(sed -E \
    -e 's#\[[0-9a-f]{7,40}\]#[<short>]#g' \
    -e 's#https://github\.com/[^/]+/[^/]+/commit/[0-9a-f]{40}#https://github.com/<repo>/commit/<sha>#g' \
    "$1")"
}

# assert_reference_notes <normalised file> <what it is> — diff against the
# normalised reference golden in $BATS_TEST_TMPDIR/expected.md.
assert_reference_notes() {
  local difference
  difference=$(diff -u "${BATS_TEST_TMPDIR}/expected.md" "$1") \
    || fail "$(printf '%s differs from tests/golden/reference-notes.md once normalised:\n%s' "$2" "$difference")"
}

# delete_sandbox_releases — every release and version tag the sandbox holds.
delete_sandbox_releases() {
  local tag
  for tag in $(gh release list --repo "$SANDBOX" --limit 1000 --json tagName --jq '.[].tagName'); do
    gh release delete "$tag" --repo "$SANDBOX" --yes
  done
  for tag in $(gh api "repos/${SANDBOX}/git/matching-refs/tags/v" --jq '.[].ref | ltrimstr("refs/tags/")'); do
    gh api --method DELETE "repos/${SANDBOX}/git/refs/tags/${tag}"
  done
}

# reset_sandbox_main — force `main` back to the sandbox's "Initial commit".
reset_sandbox_main() {
  local initial
  initial=$(git rev-list --max-parents=0 origin/main)
  [[ $(git log -1 --format=%s "$initial") == "Initial commit" ]] \
    || fail "the sandbox's root commit is not 'Initial commit'"
  git reset -q --hard "$initial"
  git push -q --force origin main
}

@test "the sandbox still holds the seeded issues and pull request" {
  local key kind number title
  for key in $REFERENCE_ITEMS; do
    kind="${key}_KIND" number="${key}_NUMBER" title="${key}_TITLE"
    if [[ ${!kind} == pr ]]; then
      assert_seeded "${!number}" "${!title}" true
    else
      assert_seeded "${!number}" "${!title}" false
    fi
  done
}

@test "real gh answers a missing issue the way the fake does" {
  local jq_filter='if has("pull_request") then empty else .title end'
  local real_status=0 fake_status=0 real_stdout fake_stdout
  real_stdout=$(gh api "repos/${SANDBOX}/issues/${MISSING_ISSUE}" --jq "$jq_filter" 2>/dev/null) || real_status=$?
  export FAKE_GH_STATE="${BATS_TEST_TMPDIR}/gh"
  fake_stdout=$("${TESTS_DIR}/helpers/fake-gh/gh" api "repos/${FIXTURE_REPO_NAME}/issues/${MISSING_ISSUE}" \
    --jq "$jq_filter" 2>/dev/null) || fake_status=$?

  assert_equal "$fake_status" "$real_status"
  assert_equal "$fake_stdout" "$real_stdout"
}

@test "real gh refuses --verify-tag for a tag the repository doesn't hold, like the fake" {
  local tag="v0.0.0-verify-tag-probe"
  if git ls-remote --exit-code --tags "https://github.com/${SANDBOX}.git" "refs/tags/${tag}" >/dev/null; then
    fail "${tag} exists in ${SANDBOX}: delete it, the probe must not publish a release"
  fi
  printf 'probe\n' >"${BATS_TEST_TMPDIR}/notes.md"

  run gh release create "$tag" --repo "$SANDBOX" --title "$tag" \
    --notes-file "${BATS_TEST_TMPDIR}/notes.md" --verify-tag

  assert_failure 1
  assert_output "tag ${tag} doesn't exist in the repo ${SANDBOX}, aborting due to --verify-tag flag"
}

@test "a full release in the sandbox carries the reference notes" {
  delete_sandbox_releases
  git clone -q "https://github.com/${SANDBOX}.git" "${BATS_TEST_TMPDIR}/sandbox"
  cd "${BATS_TEST_TMPDIR}/sandbox"
  git config core.autocrlf false
  [[ $(gh repo view --json nameWithOwner --jq .nameWithOwner) == "$SANDBOX" ]] \
    || fail "the clone doesn't resolve to ${SANDBOX}: refusing to touch it"

  reset_sandbox_main
  build_reference_dataset
  git push -q --force origin main

  run bash "$RELEASE_SH" --yes --notes "${BATS_TEST_TMPDIR}/notes.md"

  assert_success
  assert_line "Version         : 0.0.0 -> 1.0.0"
  git ls-remote --exit-code --tags origin refs/tags/v1.0.0 >/dev/null || fail "v1.0.0 is not in ${SANDBOX}"
  gh release view v1.0.0 --repo "$SANDBOX" --json body --jq .body >"${BATS_TEST_TMPDIR}/published.md"
  normalise_notes "${GOLDEN_DIR}/reference-notes.md" >"${BATS_TEST_TMPDIR}/expected.md"
  normalise_notes "${BATS_TEST_TMPDIR}/notes.md" >"${BATS_TEST_TMPDIR}/sent.md"
  normalise_notes "${BATS_TEST_TMPDIR}/published.md" >"${BATS_TEST_TMPDIR}/actual.md"
  assert_reference_notes "${BATS_TEST_TMPDIR}/sent.md" "the notes release.sh built"
  assert_reference_notes "${BATS_TEST_TMPDIR}/actual.md" "the published release"

  # Clean up on success only.
  delete_sandbox_releases
  git tag -d v1.0.0 >/dev/null
  reset_sandbox_main
}
