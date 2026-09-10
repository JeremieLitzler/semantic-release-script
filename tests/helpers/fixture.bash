# fixture.bash — builds the git history release.sh runs on.
#
# Shared by the fixture suite and the live suite, so both push the exact same
# commit subjects. Every commit gets a fixed author, committer and date, so the
# same history always gets the same hashes, on Windows and Linux alike.
#
# The functions work on the git repository in the current directory.

FIXTURE_HELPERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REFERENCE_ISSUES_ENV="${FIXTURE_HELPERS_DIR}/../fixtures/reference-issues.env"

FIXTURE_EPOCH=1767225600 # 2026-01-01T00:00:00Z
FIXTURE_CLOCK=0

# The hash of each reference dataset commit, by its number (1-based, see
# build_reference_dataset). A plain assignment, not `declare`: bats loads this
# file inside a function, where `declare` would make it local.
REFERENCE_COMMITS=()

# fixture_git <git args...> — git with the fixed identity, one minute later
# than the previous call.
fixture_git() {
  FIXTURE_CLOCK=$((FIXTURE_CLOCK + 1))
  local date="$((FIXTURE_EPOCH + FIXTURE_CLOCK * 60)) +0000"
  GIT_AUTHOR_NAME="Fixture Author" GIT_AUTHOR_EMAIL="fixture@example.com" GIT_AUTHOR_DATE="$date" \
  GIT_COMMITTER_NAME="Fixture Author" GIT_COMMITTER_EMAIL="fixture@example.com" GIT_COMMITTER_DATE="$date" \
    git -c commit.gpgsign=false -c tag.gpgsign=false "$@"
}

# init_fixture_repo — turn the current directory into a repository on `main`
# holding a single "Initial commit".
init_fixture_repo() {
  git init -q -b main .
  git config core.autocrlf false
  printf '# Fixture repository\n' >README.md
  git add README.md
  fixture_git commit -q -m "Initial commit"
}

# commit_change <subject> [body] — commit one line appended to CHANGES.md.
commit_change() {
  local subject="$1" body="${2:-}"
  printf -- '- %s\n' "$subject" >>CHANGES.md
  git add CHANGES.md
  if [[ -n $body ]]; then
    fixture_git commit -q -m "$subject" -m "$body"
  else
    fixture_git commit -q -m "$subject"
  fi
}

# tag_version <tag> [ref] — an annotated version tag, as release.sh creates it.
tag_version() {
  fixture_git tag -a "$1" -m "$1" "${2:-HEAD}"
}

load_reference_issues() {
  # shellcheck source=../fixtures/reference-issues.env
  source "$REFERENCE_ISSUES_ENV"
}

# reference_commit <subject> [body] — commit_change, and record the hash.
reference_commit() {
  commit_change "$@"
  REFERENCE_COMMITS[${#REFERENCE_COMMITS[@]} + 1]=$(git rev-parse HEAD)
}

# build_reference_dataset — append the reference dataset on top of HEAD.
#
# Commits 1-14 are the original dataset, carried over verbatim; 15-21 were
# appended for the notes rules it missed. Only ever append: inserting a commit
# changes the hash of every later one. The whole range bumps major (13, 14, 18).
build_reference_dataset() {
  load_reference_issues
  REFERENCE_COMMITS=()

  # Others: plain message + commit link.
  reference_commit "docs: explain the release flow in the readme"                             #  1
  reference_commit "ci: run the release script in dry-run on pull requests"                   #  2
  reference_commit "chore(deps): bump the linter to 9.0.0"                                    #  3
  reference_commit "test: cover the version bump rules"                                       #  4
  reference_commit "style: reformat the release script"                                       #  5

  # Bug fixes: issue titles.
  reference_commit "fix: keep the cart total in sync (#${CART_TOTAL_NUMBER})"                 #  6
  reference_commit "fix(api): return 404 instead of 500 on unknown order (#${UNKNOWN_ORDER_NUMBER})" # 7
  reference_commit "fix: stop the login form from eating the password (#${LOGIN_PASSWORD_NUMBER})"   # 8

  # Features: issue titles, no reference, and a number that is not an issue.
  reference_commit "feat: export the orders as CSV (#${CSV_EXPORT_NUMBER})"                   #  9
  reference_commit "feat(billing): add the monthly invoices (#${MONTHLY_INVOICES_NUMBER})"    # 10
  reference_commit "feat: dark mode for the dashboard"                                        # 11
  reference_commit "feat(search): remember the last query (#9999)"                            # 12

  # Breaking changes: flagged with "!", and with a footer in the body.
  reference_commit "feat!: drop the v1 authentication endpoints (#${V1_AUTH_NUMBER})"         # 13
  reference_commit "refactor: move the supabase client to its own module" \
    "BREAKING CHANGE: the supabase client is no longer exported from index.js"                # 14

  # A pull request number is not an issue: commit link under Others.
  reference_commit "chore: tidy the issue templates (#${ISSUE_TEMPLATES_NUMBER})"             # 15

  # Dedupe by issue: the CSV issue stays listed once, under the feat's Features.
  reference_commit "test: cover the CSV export (#${CSV_EXPORT_NUMBER})"                       # 16
  reference_commit "fix: quote the commas in the CSV export (#${CSV_EXPORT_NUMBER})"          # 17

  # The BREAKING-CHANGE synonym counts; "BREAKING CHANGE" in prose doesn't.
  reference_commit "perf: stream the order export" \
    "BREAKING-CHANGE: the export endpoint now returns NDJSON"                                 # 18
  reference_commit "docs: describe the upgrade path" \
    "No BREAKING CHANGE here: the old flags still work."                                      # 19

  # A merge commit is ignored; the commit it brings in is not.
  local trunk
  trunk=$(git rev-parse --abbrev-ref HEAD)
  git switch -q -c contributing-guide
  reference_commit "docs: add the contributing guide"                                         # 20
  git switch -q "$trunk"
  fixture_git merge -q --no-ff -m "Merge branch 'contributing-guide'" contributing-guide
  REFERENCE_COMMITS[21]=$(git rev-parse HEAD)                                                 # 21
  git branch -q -D contributing-guide
}
