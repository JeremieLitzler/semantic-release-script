#!/usr/bin/env bash
#
# create-dummy-issues.sh — create the dummy issues the release test data needs.
#
# Creates 7 throwaway issues on the current GitHub repository:
#   3 for the feature commits, 1 for the breaking change, 3 for the bug fixes.
#
# Every title is prefixed with "feat:" so the dummy issues are easy to spot in
# the issue list. That prefix is only a marker for humans: release.sh never
# reads the issue title prefix, it only reads the commit type.
#
# The resulting issue numbers are written to tests/dummy-issues.env, which
# generate-dummy-changes.sh then sources to reference them in commit messages.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

ENV_FILE="tests/dummy-issues.env"
BODY="Dummy issue created by tests/create-dummy-issues.sh to exercise release.sh. Safe to close."

command -v gh >/dev/null 2>&1 || { printf 'GitHub CLI (gh) not found in PATH\n' >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { printf 'gh is not logged in — run: gh auth login\n' >&2; exit 1; }

if [[ -f $ENV_FILE ]]; then
  printf '%s already exists — delete it first to create a new set of issues.\n' "$ENV_FILE" >&2
  exit 1
fi

# create_issue <variable name> <title>
create_issue() {
  local var="$1" title="$2" url number
  url=$(gh issue create --title "$title" --body "$BODY")
  number="${url##*/}"
  printf '%s=%s\n' "$var" "$number" >>"$ENV_FILE"
  printf '  #%-4s %s\n' "$number" "$title"
}

printf 'Creating dummy issues...\n\n'
: >"$ENV_FILE"

printf 'Features:\n'
create_issue FEATURE_ISSUE_1 "feat: export the orders as CSV"
create_issue FEATURE_ISSUE_2 "feat: add the monthly invoices"
create_issue FEATURE_ISSUE_3 "feat: dark mode for the dashboard"

printf '\nBreaking change:\n'
create_issue BREAKING_ISSUE_1 "feat: drop the v1 authentication endpoints"

printf '\nBug fixes:\n'
create_issue FIX_ISSUE_1 "feat: the cart total goes out of sync"
create_issue FIX_ISSUE_2 "feat: an unknown order returns 500 instead of 404"
create_issue FIX_ISSUE_3 "feat: the login form drops the password"

printf '\nIssue numbers written to %s\n' "$ENV_FILE"
printf 'Next: ./tests/generate-dummy-changes.sh\n'
