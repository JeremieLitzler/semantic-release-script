# common.bash — shared setup for the fixture suite. Every .bats file of the
# fixture suite starts with `load helpers/common` and calls setup_fixture from
# its setup().

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_SH="${TESTS_DIR}/../scripts/release/release.sh"
GOLDEN_DIR="${TESTS_DIR}/golden"
# The repository the fake gh answers for, like `gh repo view` would.
export FIXTURE_REPO_NAME="fixture-owner/fixture-repo"

load "${TESTS_DIR}/libs/bats-support/load"
load "${TESTS_DIR}/libs/bats-assert/load"
load "${TESTS_DIR}/helpers/fixture"

# setup_fixture — a throwaway repository in $REPO (the current directory
# afterwards) with a single "Initial commit", a bare `origin` in $ORIGIN, and
# the fake gh first on PATH, with `main` as the only GitHub state declared.
setup_fixture() {
  # Keep the machine's git config out (autocrlf, signing, hooks, templates...).
  # The identity is the tagger of the tags release.sh creates.
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_CONFIG_GLOBAL="${BATS_TEST_TMPDIR}/gitconfig"
  git config --global user.name "Fixture Author"
  git config --global user.email "fixture@example.com"
  git config --global advice.detachedHead false

  export FAKE_GH_STATE="${BATS_TEST_TMPDIR}/gh"
  mkdir -p "${FAKE_GH_STATE}/issues"
  export PATH="${TESTS_DIR}/helpers/fake-gh:${PATH}"
  # init_fixture_repo builds the repository on `main`, so that is the default
  # branch GitHub reports until a test declares another one.
  given_default_branch main

  ORIGIN="${BATS_TEST_TMPDIR}/origin.git"
  REPO="${BATS_TEST_TMPDIR}/repo"
  git init -q --bare "$ORIGIN"
  mkdir -p "$REPO"
  cd "$REPO"
  init_fixture_repo
  git remote add origin "$ORIGIN"
}

# push_fixture — push `main` and every tag to the bare origin.
push_fixture() {
  git push -q origin main --tags
}

# shallow_clone_fixture — swap the working repository for a depth-1 clone of
# origin, the checkout CI hands a job when nobody sets fetch-depth. The file://
# URL is what makes --depth count: git ignores it on a plain path.
shallow_clone_fixture() {
  local shallow="${BATS_TEST_TMPDIR}/shallow"
  git clone -q --depth 1 --branch main "file://${ORIGIN}" "$shallow"
  cd "$shallow"
}

# unreachable_origin_fixture — point `origin` at a path that holds no
# repository, so fetching the tags fails the way a lost network, a moved remote
# or a revoked access does.
unreachable_origin_fixture() {
  git remote set-url origin "${BATS_TEST_TMPDIR}/no-such-origin.git"
}

# clobbering_tag_fixture <tag> — move <tag> locally after origin took it, so
# the two disagree. `git fetch --tags` then rejects that ref rather than
# overwriting it, and fails with origin perfectly reachable.
clobbering_tag_fixture() {
  fixture_git tag -f -a "$1" -m "$1" HEAD
}

# ------------------------------------------------------------ GitHub state

# given_issue <number> <title> [extra jq object] — the issue as `gh api`
# returns it, merged with the extra fields.
given_issue() {
  local extra="${3:-}"
  [[ -n $extra ]] || extra='{}'
  jq -n --argjson number "$1" --arg title "$2" --arg repo "$FIXTURE_REPO_NAME" '{
    url: "https://api.github.com/repos/\($repo)/issues/\($number)",
    html_url: "https://github.com/\($repo)/issues/\($number)",
    number: $number,
    title: $title,
    state: "open",
    locked: false,
    comments: 0,
    closed_at: null,
    author_association: "OWNER",
    state_reason: null
  } + '"$extra" >"${FAKE_GH_STATE}/issues/$1.json"
}

# given_pull_request <number> <title> — closed without being merged. The
# issues endpoint answers for pull requests too, with a pull_request key.
given_pull_request() {
  given_issue "$1" "$2" '{
    html_url: "https://github.com/\($repo)/pull/\($number)",
    state: "closed",
    closed_at: "2026-01-01T00:00:00Z",
    pull_request: {
      url: "https://api.github.com/repos/\($repo)/pulls/\($number)",
      html_url: "https://github.com/\($repo)/pull/\($number)",
      diff_url: "https://github.com/\($repo)/pull/\($number).diff",
      patch_url: "https://github.com/\($repo)/pull/\($number).patch",
      merged_at: null
    }
  }'
}

# given_reference_issues — every issue and pull request of the number map, as
# the sandbox holds them.
given_reference_issues() {
  load_reference_issues
  local key kind number title
  for key in $REFERENCE_ITEMS; do
    kind="${key}_KIND" number="${key}_NUMBER" title="${key}_TITLE"
    if [[ ${!kind} == pr ]]; then
      given_pull_request "${!number}" "${!title}"
    else
      given_issue "${!number}" "${!title}"
    fi
  done
}

given_gh_logged_out() {
  touch "${FAKE_GH_STATE}/logged-out"
}

# given_default_branch <name> — the branch `gh repo view` reports as the
# repository's default, the one release.sh resolves the trunk from.
given_default_branch() {
  printf '%s\n' "$1" >"${FAKE_GH_STATE}/default-branch"
}

# given_no_default_branch — GitHub reports none, as it does for a repository
# without a commit.
given_no_default_branch() {
  rm -f "${FAKE_GH_STATE}/default-branch"
}

# ----------------------------------------------------------------- running

# run_release [options...] — run release.sh unattended (--yes) in the current
# directory.
run_release() {
  run bash "$RELEASE_SH" --yes "$@"
}

# run_release_unanswered [options...] — run release.sh with no --yes and
# nothing on stdin, the shape a CI job runs it in.
#
# A gate that is reached still reads from /dev/tty, which a developer's own
# terminal answers for even with stdin closed: the timeout is what turns a
# gate that came back into a failing test rather than a suite that hangs. It
# is a convenience, not a dependency — macOS ships no timeout, and there the
# test runs unbounded, still failing on a runner with no terminal.
run_release_unanswered() {
  if command -v timeout >/dev/null 2>&1; then
    run timeout 30 bash "$RELEASE_SH" "$@" </dev/null
  else
    run bash "$RELEASE_SH" "$@" </dev/null
  fi
}

# gh_calls -> every gh call made so far, one per line
gh_calls() {
  cat "${FAKE_GH_STATE}/calls.log" 2>/dev/null || true
}

# refute_gh_call <prefix> — no gh call starts with <prefix>.
refute_gh_call() {
  local call
  while IFS= read -r call; do
    [[ $call != "$1"* ]] || fail "gh was called: gh ${call}"
  done < <(gh_calls)
}

# published_notes_file <tag> -> the path of the notes the fake gh published
published_notes_file() {
  printf '%s' "${FAKE_GH_STATE}/releases/$1.md"
}

assert_no_release_created() {
  refute_gh_call "release create"
  [[ ! -e ${FAKE_GH_STATE}/releases ]] || [[ -z $(ls -A "${FAKE_GH_STATE}/releases") ]] \
    || fail "a release was published: $(ls "${FAKE_GH_STATE}/releases")"
}

# assert_remote_tag <tag> / refute_remote_tag <tag>
assert_remote_tag() {
  git ls-remote --exit-code --tags "$ORIGIN" "refs/tags/$1" >/dev/null \
    || fail "tag $1 is not on origin"
}
refute_remote_tag() {
  if git ls-remote --exit-code --tags "$ORIGIN" "refs/tags/$1" >/dev/null; then
    fail "tag $1 is on origin"
  fi
}

# assert_local_tag <tag> [ref] — the tag exists locally, on <ref> when given.
assert_local_tag() {
  git rev-parse --verify --quiet "refs/tags/$1" >/dev/null || fail "tag $1 does not exist locally"
  if [[ -n ${2:-} ]]; then
    [[ $(git rev-parse "$1^{commit}") == $(git rev-parse "$2^{commit}") ]] \
      || fail "tag $1 is on $(git rev-parse --short "$1^{commit}"), not on $(git rev-parse --short "$2")"
  fi
}
refute_local_tag() {
  if git rev-parse --verify --quiet "refs/tags/$1" >/dev/null; then
    fail "tag $1 exists locally"
  fi
}

# ------------------------------------------------------------------ golden

# assert_golden <actual file> <golden file name> — diff against
# tests/golden/<name>. UPDATE_GOLDEN=1 rewrites the golden file instead, for
# review in git.
assert_golden() {
  local actual="$1" golden="${GOLDEN_DIR}/$2"
  [[ -f $actual ]] || fail "no output to compare with tests/golden/$2: $actual does not exist"
  if [[ ${UPDATE_GOLDEN:-} == 1 ]]; then
    mkdir -p "$GOLDEN_DIR"
    cp "$actual" "$golden"
    return 0
  fi
  [[ -f $golden ]] || fail "tests/golden/$2 does not exist: run with UPDATE_GOLDEN=1 to create it"
  local difference
  if ! difference=$(diff -u "$golden" "$actual"); then
    fail "$(printf 'differs from tests/golden/%s (UPDATE_GOLDEN=1 rewrites it):\n%s' "$2" "$difference")"
  fi
}

# normalise_changelog_dates <file> — replace each release date with <date>,
# after checking it's a YYYY-MM-DD date.
normalise_changelog_dates() {
  local file="$1"
  if grep -E '^## v' "$file" | grep -vqE '^## v[0-9]+\.[0-9]+\.[0-9]+ \([0-9]{4}-[0-9]{2}-[0-9]{2}\)$'; then
    fail "a changelog heading is not '## vX.Y.Z (YYYY-MM-DD)': $(grep -E '^## v' "$file")"
  fi
  sed -E -i 's/^(## v[0-9]+\.[0-9]+\.[0-9]+) \([0-9]{4}-[0-9]{2}-[0-9]{2}\)$/\1 (<date>)/' "$file"
}
