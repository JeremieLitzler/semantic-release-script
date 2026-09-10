#!/usr/bin/env bash
#
# seed-sandbox.sh — seed the sandbox with the issues and the closed pull
# request the reference dataset references.
#
# The sandbox (JeremieLitzler/semantic-release-script-tests) holds nothing but
# this reference data, which is created once and kept. The script only creates
# what is missing, matched by title, so it is safe to run again: after the
# sandbox is wiped, or to check the data is still there.
#
# It then writes tests/fixtures/reference-issues.env, the number map both test
# suites read: the fixture suite declares its fake issues from it, and both
# suites build the reference commit subjects from it.
#
# Requirements: bash >= 4 and the GitHub CLI (`gh`) logged in with write access
# to the sandbox.

set -euo pipefail

SANDBOX="JeremieLitzler/semantic-release-script-tests"
PR_BRANCH="seed/closed-pull-request"
REFERENCE_ISSUES_ENV="$(cd "$(dirname "$0")/.." && pwd)/fixtures/reference-issues.env"
BODY="Reference data for the semantic-release-script test suites, created by tests/live/seed-sandbox.sh. Keep it: the live suite checks it still exists."

# key | kind | title, in creation order. Titles are plain, like a real tracker's,
# and must not contain a single quote (the map quotes them with it).
ITEMS=(
  "CSV_EXPORT|issue|Export the orders as CSV"
  "MONTHLY_INVOICES|issue|Add the monthly invoices"
  "V1_AUTH|issue|Drop the v1 authentication endpoints"
  "CART_TOTAL|issue|The cart total goes out of sync"
  "UNKNOWN_ORDER|issue|An unknown order returns 500 instead of 404"
  "LOGIN_PASSWORD|issue|The login form drops the password"
  "ISSUE_TEMPLATES|pr|Tidy the issue templates"
)

die() { printf 'x %s\n' "$*" >&2; exit 1; }

(( BASH_VERSINFO[0] >= 4 )) || die "bash 4+ required (running ${BASH_VERSION})"
command -v gh >/dev/null 2>&1 || die "GitHub CLI (gh) not found in PATH"
gh auth status >/dev/null 2>&1 || die "gh is not logged in — run: gh auth login"

# Every issue and pull request already in the sandbox, as "number<TAB>kind<TAB>state<TAB>title".
EXISTING=$(gh api --paginate "repos/${SANDBOX}/issues?state=all&per_page=100" \
  --jq '.[] | [.number, (if has("pull_request") then "pr" else "issue" end), .state, .title] | @tsv')

# find_existing <kind> <title> -> "number<TAB>state", or nothing
find_existing() {
  local kind="$1" title="$2" number item_kind state item_title
  while IFS=$'\t' read -r number item_kind state item_title; do
    if [[ $item_kind == "$kind" && $item_title == "$title" ]]; then
      printf '%s\t%s' "$number" "$state"
      return 0
    fi
  done <<<"$EXISTING"
  return 0
}

create_issue() {
  local title="$1" url
  url=$(gh issue create --repo "$SANDBOX" --title "$title" --body "$BODY")
  printf '%s' "${url##*/}"
}

# A pull request needs a branch with a diff. The branch is made through the API,
# so no clone is needed, and deleted once the pull request is closed unmerged.
create_closed_pull_request() {
  local title="$1" main_sha content url number
  main_sha=$(gh api "repos/${SANDBOX}/git/ref/heads/main" --jq .object.sha)
  # A run interrupted before the pull request was closed leaves the branch.
  gh api --method DELETE "repos/${SANDBOX}/git/refs/heads/${PR_BRANCH}" >/dev/null 2>&1 || true
  gh api --method POST "repos/${SANDBOX}/git/refs" \
    -f "ref=refs/heads/${PR_BRANCH}" -f "sha=${main_sha}" >/dev/null
  content=$(printf 'Placeholder change for the closed pull request "%s".\n' "$title" | base64 | tr -d '\n\r')
  gh api --method PUT "repos/${SANDBOX}/contents/seed/closed-pull-request.md" \
    -f "message=chore: ${title,}" -f "content=${content}" -f "branch=${PR_BRANCH}" >/dev/null
  url=$(gh pr create --repo "$SANDBOX" --base main --head "$PR_BRANCH" --title "$title" --body "$BODY")
  number="${url##*/}"
  gh pr close "$number" --repo "$SANDBOX" --delete-branch >/dev/null
  printf '%s' "$number"
}

printf 'Seeding %s...\n\n' "$SANDBOX"

declare -A NUMBERS=()
KEYS=()
for item in "${ITEMS[@]}"; do
  IFS='|' read -r key kind title <<<"$item"
  [[ $title != *"'"* ]] || die "title must not contain a single quote: $title"
  found=$(find_existing "$kind" "$title")
  number="${found%%$'\t'*}"
  state="${found#*$'\t'}"
  if [[ -z $found ]]; then
    if [[ $kind == pr ]]; then
      number=$(create_closed_pull_request "$title")
    else
      number=$(create_issue "$title")
    fi
    status="created"
  elif [[ $kind == pr && $state == open ]]; then
    gh pr close "$number" --repo "$SANDBOX" --delete-branch >/dev/null
    status="closed"
  else
    status="kept"
  fi
  NUMBERS[$key]="$number"
  KEYS+=("$key")
  printf '  %-5s #%-4s %-8s %s\n' "$kind" "$number" "$status" "$title"
done

mkdir -p "$(dirname "$REFERENCE_ISSUES_ENV")"
{
  printf '# Written by tests/live/seed-sandbox.sh: do not edit by hand, run it again.\n'
  printf '#\n'
  printf '# The kind (issue or pr), number and title of every issue and pull request\n'
  printf '# the reference dataset references, as seeded in %s.\n' "$SANDBOX"
  printf '# The fixture suite and the live suite both read it.\n'
  printf "\nREFERENCE_ITEMS='%s'\n" "${KEYS[*]}"
  for item in "${ITEMS[@]}"; do
    IFS='|' read -r key kind title <<<"$item"
    printf '\n%s_KIND=%s\n' "$key" "$kind"
    printf '%s_NUMBER=%s\n' "$key" "${NUMBERS[$key]}"
    printf "%s_TITLE='%s'\n" "$key" "$title"
  done
} >"$REFERENCE_ISSUES_ENV"

printf '\nNumber map written to %s\n' "$REFERENCE_ISSUES_ENV"
