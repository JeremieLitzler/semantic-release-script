#!/usr/bin/env bash
#
# release.sh — own your semantic release.
#
# Reads the conventional commits since the last release tag, decides the next
# version, builds the Markdown release notes, creates and pushes the tag and
# finally publishes the GitHub release.
#
# Every step is separated from the next one by a human gate: nothing is written
# to the remote before you say so.
#
# Requirements: git, bash >= 4, and the GitHub CLI (`gh`) already logged in.

set -euo pipefail

SCRIPT_NAME=$(basename "$0")

ASSUME_YES=false
DRY_RUN=false
LOCAL_ONLY=false
SINCE_REF=""
TO_REF=""
FORCE_LEVEL=""
NOTES_OUT=""
CHANGELOG_OUT=""

# ---------------------------------------------------------------- presentation

if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'
  YELLOW=$'\033[33m'; BLUE=$'\033[34m'; RESET=$'\033[0m'
else
  BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; RESET=""
fi

info() { printf '%s\n' "$*"; }
note() { printf '%s%s%s\n' "$DIM" "$*" "$RESET"; }
warn() { printf '%s! %s%s\n' "$YELLOW" "$*" "$RESET" >&2; }
die()  { printf '%sx %s%s\n' "$RED" "$*" "$RESET" >&2; exit 1; }

step() {
  printf '\n%s%s== %s ==%s\n\n' "$BOLD" "$BLUE" "$*" "$RESET"
}

# Human gate. Returns only if the user agrees to move on.
gate() {
  local prompt="$1"
  if [[ $ASSUME_YES == true ]]; then
    note "-> $prompt (auto-confirmed with --yes)"
    return 0
  fi
  if [[ ! -t 0 && ! -e /dev/tty ]]; then
    die "no terminal available to confirm '$prompt' — rerun with --yes"
  fi
  local answer=""
  printf '%s%s%s [y/N] ' "$BOLD" "$prompt" "$RESET" >&2
  read -r answer < /dev/tty || true
  case "$answer" in
    [yY] | [yY][eE][sS]) return 0 ;;
    *) info "Stopped before: $prompt"; exit 0 ;;
  esac
}

usage() {
  cat <<EOF
${SCRIPT_NAME} — semantic release from conventional commits.

Usage: ${SCRIPT_NAME} [options]

Options:
  -y, --yes             Skip every human gate (unattended run).
  -n, --dry-run         Do everything but push the tag and create the release.
  -l, --local           Create the tag locally, but neither push nor publish.
      --since <ref>     Read commits since <ref> instead of the last v* tag.
                         This is the commit set on the last release.
      --to <ref>        Read commits up to <ref> instead of HEAD, and create
                         the tag on <ref> instead of HEAD. This is the commit
                         to set on the next release.
      --level <level>   Force the bump: major | minor | patch.
      --notes <file>    Also write the release notes to <file>.
      --changelog <f>   Prepend the release to the changelog <f> (newest first).
  -h, --help            Show this help.

Steps (a human gate sits before each one):
  1. evaluate the new version from the commit range
  2. build the Markdown release notes
  3. create and push the tag
  4. create the GitHub release

Rebuilding a history of releases:
  Combine --since and --to to replay a specific commit range instead of the
  usual "last tag..HEAD". Work oldest-first: create v0.0.1 on its commit, then
  v0.0.2 on the next one, and so on. Once a tag exists, --since can often be
  left out since the next release's range is auto-detected from the nearest
  ancestor tag of --to.
EOF
}

# ----------------------------------------------------------------------- args

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y | --yes)     ASSUME_YES=true; shift ;;
    -n | --dry-run) DRY_RUN=true; shift ;;
    -l | --local)   LOCAL_ONLY=true; shift ;;
    --since)        SINCE_REF="${2:-}"; [[ -n $SINCE_REF ]] || die "--since needs a ref"; shift 2 ;;
    --to)           TO_REF="${2:-}"; [[ -n $TO_REF ]] || die "--to needs a ref"; shift 2 ;;
    --level)        FORCE_LEVEL="${2:-}"; shift 2 ;;
    --notes)        NOTES_OUT="${2:-}"; [[ -n $NOTES_OUT ]] || die "--notes needs a path"; shift 2 ;;
    --changelog)    CHANGELOG_OUT="${2:-}"; [[ -n $CHANGELOG_OUT ]] || die "--changelog needs a path"; shift 2 ;;
    -h | --help)    usage; exit 0 ;;
    *)              usage >&2; die "unknown option: $1" ;;
  esac
done

case "$FORCE_LEVEL" in
  "" | major | minor | patch) ;;
  *) die "--level must be one of: major, minor, patch" ;;
esac

# ------------------------------------------------------------------ preflight

(( BASH_VERSINFO[0] >= 4 )) || die "bash 4+ required (running ${BASH_VERSION})"
command -v git >/dev/null 2>&1 || die "git not found in PATH"
command -v gh  >/dev/null 2>&1 || die "GitHub CLI (gh) not found in PATH"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git repository"
gh auth status >/dev/null 2>&1 || die "gh is not logged in — run: gh auth login"

REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner) \
  || die "cannot resolve the GitHub repository for this checkout"
REPO_URL="https://github.com/${REPO}"

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
[[ $CURRENT_BRANCH == "main" ]] || warn "you are on '${CURRENT_BRANCH}', not 'main'"

[[ -n $TO_REF ]] || TO_REF="HEAD"
git rev-parse --verify --quiet "$TO_REF" >/dev/null || die "unknown ref: $TO_REF"

if [[ $(git rev-parse "$TO_REF") == $(git rev-parse HEAD) ]]; then
  if [[ -n $(git status --porcelain) ]]; then
    warn "the working tree is not clean; the tag will only contain committed work"
  fi
fi

note "Fetching tags from origin..."
git fetch --tags --quiet origin || warn "could not fetch tags from origin"

# ------------------------------------------------------- step 1: next version

LAST_TAG=""
if [[ -n $SINCE_REF ]]; then
  git rev-parse --verify --quiet "$SINCE_REF" >/dev/null || die "unknown ref: $SINCE_REF"
  LAST_TAG="$SINCE_REF"
else
  LAST_TAG=$(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' "$TO_REF" 2>/dev/null || true)
fi

if [[ -n $LAST_TAG ]]; then
  RANGE="${LAST_TAG}..${TO_REF}"
else
  RANGE="${TO_REF}"
fi

CURRENT_VERSION="0.0.0"
if [[ $LAST_TAG =~ ^v?([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
  CURRENT_VERSION="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
elif [[ -n $LAST_TAG ]]; then
  # --since accepts any ref, not just a version tag (e.g. a commit hash when
  # replaying history). Resolve the nearest reachable version tag so the
  # current version is still detected correctly.
  VERSION_TAG=$(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' "$LAST_TAG" 2>/dev/null || true)
  if [[ $VERSION_TAG =~ ^v?([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
    CURRENT_VERSION="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
  fi
fi

mapfile -t COMMITS < <(git log --no-merges --format=%H "$RANGE")
(( ${#COMMITS[@]} > 0 )) || die "no commit to release in range '${RANGE}'"

# classify <subject> <body> -> breaking | feature | fix | other
classify() {
  local subject="$1" body="$2" type="" bang=""
  if [[ $subject =~ ^([a-zA-Z]+)(\([^\)]*\))?(!)?: ]]; then
    type="${BASH_REMATCH[1],,}"
    bang="${BASH_REMATCH[3]}"
  fi
  # Conventional Commits requires the uppercase footer token "BREAKING CHANGE"
  # (or its synonym "BREAKING-CHANGE"), followed by ": " or " #" — not just
  # those words appearing anywhere in the body's prose.
  if [[ -n $bang || $body =~ (^|$'\n')BREAKING[-\ ]CHANGE(:\ |\ \#) ]]; then
    printf 'breaking'
  elif [[ $type == "feat" ]]; then
    printf 'feature'
  elif [[ $type == "fix" ]]; then
    printf 'fix'
  else
    printf 'other'
  fi
}

declare -a C_HASH=() C_SHORT=() C_SUBJECT=() C_CATEGORY=()

for hash in "${COMMITS[@]}"; do
  raw=$(git show -s --format=$'%h\x1f%s\x1f%b' "$hash")
  short="${raw%%$'\x1f'*}"; rest="${raw#*$'\x1f'}"
  subject="${rest%%$'\x1f'*}"; body="${rest#*$'\x1f'}"

  C_HASH+=("$hash")
  C_SHORT+=("$short")
  C_SUBJECT+=("$subject")
  C_CATEGORY+=("$(classify "$subject" "$body")")
done

LEVEL="patch"
for category in "${C_CATEGORY[@]}"; do
  case "$category" in
    breaking) LEVEL="major"; break ;;
    feature)  LEVEL="minor" ;;
  esac
done
[[ -n $FORCE_LEVEL ]] && LEVEL="$FORCE_LEVEL"

IFS='.' read -r MAJOR MINOR PATCH <<<"$CURRENT_VERSION"
case "$LEVEL" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
esac
NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
NEW_TAG="v${NEW_VERSION}"

step "Step 1 — evaluate the new version"
info "Repository      : ${REPO}"
info "Branch          : ${CURRENT_BRANCH}"
info "Commit range    : ${RANGE}${LAST_TAG:+ (last tag: ${LAST_TAG})}"
[[ $TO_REF == "HEAD" ]] || info "Target ref      : ${TO_REF} (tag will be created there, not on HEAD)"
info "Commits scanned : ${#COMMITS[@]}"
info ""
for i in "${!C_HASH[@]}"; do
  printf '  %s%-9s%s %s %s%s%s\n' \
    "$YELLOW" "${C_CATEGORY[$i]}" "$RESET" "${C_SHORT[$i]}" "$DIM" "${C_SUBJECT[$i]}" "$RESET"
done
info ""
info "Bump            : ${BOLD}${LEVEL}${RESET}${FORCE_LEVEL:+ (forced with --level)}"
info "Version         : ${CURRENT_VERSION} -> ${BOLD}${GREEN}${NEW_VERSION}${RESET}"

if git rev-parse --verify --quiet "refs/tags/${NEW_TAG}" >/dev/null; then
  die "tag ${NEW_TAG} already exists locally"
fi

gate "Continue to step 2 and build the release notes for ${NEW_TAG}?"

# ------------------------------------------------------ step 2: release notes

declare -A ISSUE_TITLES=()

# issue_title <number> -> the issue title, or nothing when the number is a pull
# request, does not exist, or cannot be read.
issue_title() {
  local number="$1"
  if [[ -n ${ISSUE_TITLES[$number]+set} ]]; then
    printf '%s' "${ISSUE_TITLES[$number]}"
    return 0
  fi
  # gh api writes the error payload to stdout on a 404, so only trust the
  # output when the call actually succeeded.
  local title=""
  if ! title=$(gh api "repos/${REPO}/issues/${number}" \
                 --jq 'if has("pull_request") then empty else .title end' 2>/dev/null); then
    title=""
  fi
  ISSUE_TITLES[$number]="$title"
  printf '%s' "$title"
}

declare -a BREAKING_ISSUE=() BREAKING_PLAIN=()
declare -a FEATURE_ISSUE=()  FEATURE_PLAIN=()
declare -a FIX_ISSUE=()      FIX_PLAIN=()
declare -a OTHER_ISSUE=()    OTHER_PLAIN=()

# category_rank <category> -> larger means more significant. Used so an issue
# referenced by several commits (a feature, its docs, its tests, ...) is
# filed under the most significant category among them, rather than
# whichever commit happens to be processed first.
category_rank() {
  case "$1" in
    breaking) printf 4 ;;
    feature)  printf 3 ;;
    fix)      printf 2 ;;
    *)        printf 1 ;;
  esac
}

note "Resolving issue references with gh..."

# Several commits often close out the same issue. They'd otherwise repeat
# the same issue title on multiple lines, so each issue gets exactly one
# bullet: ISSUE_ORDER remembers first-seen order (commits are newest-first)
# while ISSUE_CATEGORY/ISSUE_RANK track the most significant category seen
# so far for that issue.
declare -a ISSUE_ORDER=()
declare -A ISSUE_BULLET=() ISSUE_CATEGORY=() ISSUE_RANK=()

for i in "${!C_HASH[@]}"; do
  subject="${C_SUBJECT[$i]}"
  category="${C_CATEGORY[$i]}"
  title=""
  number=""

  if [[ $subject =~ \#([0-9]+) ]]; then
    number="${BASH_REMATCH[1]}"
    title=$(issue_title "$number")
  fi

  if [[ -n $title ]]; then
    bullet="- ${title} (#${number})"
    rank=$(category_rank "$category")
    if [[ -z ${ISSUE_RANK[$number]+set} ]]; then
      ISSUE_ORDER+=("$number")
    fi
    if [[ -z ${ISSUE_RANK[$number]+set} || $rank -gt ${ISSUE_RANK[$number]} ]]; then
      ISSUE_RANK[$number]="$rank"
      ISSUE_CATEGORY[$number]="$category"
      ISSUE_BULLET[$number]="$bullet"
    fi
    continue
  fi

  bullet="- ${subject} ([${C_SHORT[$i]}](${REPO_URL}/commit/${C_HASH[$i]}))"
  case "$category" in
    breaking) BREAKING_PLAIN+=("$bullet") ;;
    feature)  FEATURE_PLAIN+=("$bullet") ;;
    fix)      FIX_PLAIN+=("$bullet") ;;
    other)    OTHER_PLAIN+=("$bullet") ;;
  esac
done

for number in "${ISSUE_ORDER[@]}"; do
  bullet="${ISSUE_BULLET[$number]}"
  case "${ISSUE_CATEGORY[$number]}" in
    breaking) BREAKING_ISSUE+=("$bullet") ;;
    feature)  FEATURE_ISSUE+=("$bullet") ;;
    fix)      FIX_ISSUE+=("$bullet") ;;
    other)    OTHER_ISSUE+=("$bullet") ;;
  esac
done

NOTES_FILE=$(mktemp -t "release-notes-XXXXXX.md")
trap 'rm -f "$NOTES_FILE"' EXIT

# section <heading> <issue array name> <plain array name>
section() {
  local heading="$1" issues_name="$2" plain_name="$3"
  local -n issues="$issues_name"
  local -n plain="$plain_name"
  (( ${#issues[@]} + ${#plain[@]} > 0 )) || return 0
  printf '### %s\n\n' "$heading" >>"$NOTES_FILE"
  local line
  for line in "${issues[@]}" "${plain[@]}"; do
    printf '%s\n' "$line" >>"$NOTES_FILE"
  done
  printf '\n' >>"$NOTES_FILE"
}

: >"$NOTES_FILE"
section "BREAKING CHANGES" BREAKING_ISSUE BREAKING_PLAIN
section "Features"         FEATURE_ISSUE  FEATURE_PLAIN
section "Bug fixes"        FIX_ISSUE      FIX_PLAIN
section "Others"           OTHER_ISSUE    OTHER_PLAIN

step "Step 2 — release notes for ${NEW_TAG}"
cat "$NOTES_FILE"

if [[ -n $NOTES_OUT ]]; then
  cp "$NOTES_FILE" "$NOTES_OUT"
  note "Notes also written to ${NOTES_OUT}"
fi

# The releases are the changelog, so this stays optional. It exists to review a
# whole series of releases in one file, the newest one on top.
if [[ -n $CHANGELOG_OUT ]]; then
  mkdir -p "$(dirname "$CHANGELOG_OUT")"
  CHANGELOG_TMP=$(mktemp -t "changelog-XXXXXX.md")
  {
    printf '# Changelog\n\n'
    printf '## %s (%s)\n\n' "$NEW_TAG" "$(date +%Y-%m-%d)"
    if [[ -f $CHANGELOG_OUT ]]; then
      tail -n +2 "$CHANGELOG_OUT" | sed '1{/^$/d;}'
    fi
  } >"$CHANGELOG_TMP"
  mv "$CHANGELOG_TMP" "$CHANGELOG_OUT"
  note "Changelog updated: ${CHANGELOG_OUT}"
fi

gate "Continue to step 3 and create the tag ${NEW_TAG}?"

# --------------------------------------------------------- step 3: tag & push

step "Step 3 — create and push ${NEW_TAG}"

if [[ $DRY_RUN == true ]]; then
  note "[dry-run] git tag -a ${NEW_TAG} -m ${NEW_TAG} ${TO_REF}"
  note "[dry-run] git push origin ${NEW_TAG}"
elif [[ $LOCAL_ONLY == true ]]; then
  git tag -a "$NEW_TAG" -m "$NEW_TAG" "$TO_REF"
  info "Tag ${NEW_TAG} created on $(git rev-parse --short "$TO_REF")."
  note "[local] not pushed to origin"
else
  git tag -a "$NEW_TAG" -m "$NEW_TAG" "$TO_REF"
  info "Tag ${NEW_TAG} created on $(git rev-parse --short "$TO_REF")."
  if ! git push origin "$NEW_TAG"; then
    git tag -d "$NEW_TAG" >/dev/null
    die "pushing ${NEW_TAG} failed — the local tag has been deleted, nothing was released"
  fi
  info "Tag ${NEW_TAG} pushed to origin."
fi

gate "Continue to step 4 and publish the GitHub release ${NEW_TAG}?"

# ------------------------------------------------------------ step 4: release

step "Step 4 — publish the release ${NEW_TAG}"

if [[ $DRY_RUN == true ]]; then
  note "[dry-run] gh release create ${NEW_TAG} --title ${NEW_TAG} --notes-file <notes>"
  note "[dry-run] no tag was pushed, so no release was created"
elif [[ $LOCAL_ONLY == true ]]; then
  note "[local] gh release create ${NEW_TAG} --title ${NEW_TAG} --notes-file <notes>"
  note "[local] the tag stays on this machine, so no release was created"
else
  gh release create "$NEW_TAG" \
    --repo "$REPO" \
    --title "$NEW_TAG" \
    --notes-file "$NOTES_FILE" \
    --verify-tag
  printf '\n%s%sReleased %s%s\n' "$BOLD" "$GREEN" "$NEW_TAG" "$RESET"
  info "${REPO_URL}/releases/tag/${NEW_TAG}"
fi
