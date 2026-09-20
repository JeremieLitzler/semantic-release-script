#!/usr/bin/env bash
#
# release.sh — own your semantic release.
#
# Reads the conventional commits since the last release tag, decides the next
# version, builds the Markdown release notes, creates and pushes the tag and
# finally publishes the GitHub release.
#
# Every step is separated from the next one by a human gate: nothing is written
# to the remote before you say so. A --dry-run reaches no remote, so it runs
# straight through, with no gate to answer.
#
# Requirements: git, bash >= 4, and the GitHub CLI (`gh`) already logged in.

set -euo pipefail

SCRIPT_NAME=$(basename "$0")

# ----------------------------------------------------------------- exit codes
#
# The contract with whatever runs the script. A consumer's CI reads the code
# rather than grepping the output: a trunk that has only seen merges has
# nothing to release, which is a normal day, not a broken pipeline.
#
# Adding an outcome means adding a code here, documenting it in usage() and in
# the README, and pinning it in tests/exit-codes.bats.
#
# readonly on purpose: `exit` with an empty or non-numeric argument is itself
# an exit 2, which is the code for nothing to release. A reassignment would
# turn a broken run into the most benign outcome there is.
readonly EXIT_OK=0                 # released, or previewed with --dry-run/--local
readonly EXIT_ERROR=1              # bad usage, a missing tool, a failed push
readonly EXIT_NOTHING_TO_RELEASE=2 # no commit in the range
readonly EXIT_REFUSED=3            # a guard refused the release

ASSUME_YES=false
DRY_RUN=false
LOCAL_ONLY=false
SINCE_REF=""
TO_REF=""
FORCE_LEVEL=""
NOTES_OUT=""
CHANGELOG_OUT=""
TRUNK=""

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
# stop <exit code> <reason...> — say why the release stops, and end on the code
# that outcome is named by. die is the same thing for the plain error code, the
# one most reasons end on.
#
# Never call either from a command substitution: `exit` would end the subshell
# and the caller would carry on with the code lost.
stop() { local code="$1"; shift; printf '%sx %s%s\n' "$RED" "$*" "$RESET" >&2; exit "$code"; }
die()  { stop "$EXIT_ERROR" "$@"; }

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
  # A dry run reaches no remote — no tag pushed, no release created — so the
  # gates guard nothing and a CI job can preview a release with --dry-run
  # alone, on a runner with no terminal to answer on.
  #
  # It is the remote a dry run leaves alone, not the disk: --notes and
  # --changelog still write their file, now with no gate in front of them.
  # --local still gates, since it writes a tag to the machine.
  if [[ $DRY_RUN == true ]]; then
    note "-> $prompt (skipped: --dry-run reaches no remote)"
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
    # A human said no. Nothing was released, and nothing went wrong.
    *) info "Stopped before: $prompt"; exit "$EXIT_OK" ;;
  esac
}

usage() {
  cat <<EOF
${SCRIPT_NAME} — semantic release from conventional commits.

Usage: ${SCRIPT_NAME} [options]

Options:
  -y, --yes             Skip every human gate (unattended run).
  -n, --dry-run         Do everything but push the tag and create the release.
                         Reaches no remote, so every gate is skipped.
  -l, --local           Create the tag locally, but neither push nor publish.
      --since <ref>     Read commits since <ref> instead of the last v* tag.
                         This is the commit set on the last release.
      --to <ref>        Read commits up to <ref> instead of HEAD, and create
                         the tag on <ref> instead of HEAD. This is the commit
                         to set on the next release.
      --trunk <name>    The branch releases are cut from. Defaults to the
                         repository's default branch on GitHub.
      --level <level>   Force the bump: major | minor | patch.
      --notes <file>    Also write the release notes to <file>.
      --changelog <f>   Prepend the release to the changelog <f> (newest first).
  -h, --help            Show this help.

Steps (a human gate sits before each one, unless --dry-run):
  1. evaluate the new version from the commit range
  2. build the Markdown release notes
  3. create and push the tag
  4. create the GitHub release

Exit codes:
  0  released, or previewed with --dry-run or --local
  1  error: bad usage, a missing tool, a failed push
  2  nothing to release in the commit range
  3  refused by a guard
  *  anything else is git or gh failing unguarded (128, say): treat it as 1

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
    --trunk)        TRUNK="${2:-}"; [[ -n $TRUNK ]] || die "--trunk needs a name"; shift 2 ;;
    --level)        FORCE_LEVEL="${2:-}"; shift 2 ;;
    --notes)        NOTES_OUT="${2:-}"; [[ -n $NOTES_OUT ]] || die "--notes needs a path"; shift 2 ;;
    --changelog)    CHANGELOG_OUT="${2:-}"; [[ -n $CHANGELOG_OUT ]] || die "--changelog needs a path"; shift 2 ;;
    -h | --help)    usage; exit "$EXIT_OK" ;;
    *)              usage >&2; die "unknown option: $1" ;;
  esac
done

case "$FORCE_LEVEL" in
  "" | major | minor | patch) ;;
  *) die "--level must be one of: major, minor, patch" ;;
esac

# ------------------------------------------------------------------- baseline
#
# The baseline is the version tag the next version is computed from.
# resolve_baseline works it out in one place — the tags origin holds, the ref
# the commit range starts at, the version that ref carries — and
# baseline_refusal words the reasons it has to refuse a release, so a refusal
# still to come is added there rather than inline. verify_ref sits beside it
# for the one reason that is not a refusal: a ref the caller got wrong.
#
# verify_trunk_contains guards the other end of the same drift: the baseline is
# resolved from the trunk, so a tag written where the trunk cannot reach it is
# a baseline the next release will never find.

# A version tag is named vMAJOR.MINOR.PATCH. The glob narrows `git describe`
# to those tags; the regex reads the version out of one.
VERSION_TAG_GLOB='v[0-9]*.[0-9]*.[0-9]*'
VERSION_TAG_RE='^v?([0-9]+)\.([0-9]+)\.([0-9]+)'

BASELINE_REF=""    # the ref the commit range starts at, empty on a first release
CURRENT_VERSION="" # the version BASELINE_REF carries, 0.0.0 when there is none

# verify_ref <ref> — the ref exists, or the release stops.
#
# Not a refusal: a ref the caller named that does not exist is a mistake in the
# command line, like a bad --level, so it ends on EXIT_ERROR. Both --since and
# --to come through here, which is what keeps the wording identical for each.
verify_ref() {
  git rev-parse --verify --quiet "$1" >/dev/null || die "unknown ref: $1"
}

# baseline_refusal <name> [detail] [target] — refuse the release on the named
# baseline refusal. The name picks the wording, so a refusal raised from more
# than one place reads the same in each; every one of them is the repository's
# state ruling the release out, so every one of them exits EXIT_REFUSED. An
# unrecognised name would leave `case` returning 0 and the refusal silent,
# hence the last arm.
#
# detail is whatever that refusal is about, and the name says which: the remote
# for stale-tags, the trunk for off-trunk, the tag for tag-taken. target is the
# ref that would have been tagged, for the refusals naming both ends.
baseline_refusal() {
  local detail="${2:-}" target="${3:-}"
  case "$1" in
    shallow)    stop "$EXIT_REFUSED" "shallow clone: the version tags behind the cut are unreachable — fetch the full history (git fetch --unshallow, or fetch-depth: 0 in CI)" ;;
    stale-tags) stop "$EXIT_REFUSED" "could not fetch the version tags from '${detail}': the local tags may be stale, and the baseline read from them older than the last release — git's own reason is above: make '${detail}' reachable, or let its tags win with git fetch --tags --force ${detail}" ;;
    off-trunk)  stop "$EXIT_REFUSED" "origin/${detail} does not contain ${target}: the tag would sit on a commit the trunk cannot reach, where the next release's baseline can't see it — push those commits to ${detail} or rebase them onto it, and check --trunk when ${detail} is not the branch releases are cut from" ;;
    tag-taken)  stop "$EXIT_REFUSED" "tag ${detail} already exists locally" ;;
    *)          stop "$EXIT_REFUSED" "baseline refused: $1" ;;
  esac
}

# nearest_version_tag <ref> -> the nearest version tag reachable from <ref>, or
# nothing when the ref reaches none.
nearest_version_tag() {
  git describe --tags --abbrev=0 --match "$VERSION_TAG_GLOB" "$1" 2>/dev/null || true
}

# resolve_baseline <target ref> [since ref] -> BASELINE_REF and CURRENT_VERSION.
#
# Without --since the baseline is the nearest version tag the target ref
# reaches. With one it is the --since ref itself, which accepts any ref, not
# just a version tag (a commit hash when replaying history): the nearest
# version tag behind it then answers for the current version.
resolve_baseline() {
  local target="$1" since="${2:-}"

  # Before the fetch, because the fetch cannot repair it: the tag refs come
  # back, the commits they name stay behind the cut, and `git describe` reaches
  # none of them. Only `true` refuses, so a git too old to know the option
  # (< 2.15) leaves the release alone rather than claiming a shallow clone.
  [[ $(git rev-parse --is-shallow-repository 2>/dev/null) != true ]] || baseline_refusal shallow

  note "Fetching tags from origin..."
  # The tags are what the baseline is read from, so a fetch that fails is not a
  # detail to warn about: it leaves the stale local tags in place, and a version
  # computed from them can sit below a release origin already holds. No flag
  # escapes it; the README's "Tags that can't be fetched" says why --local and
  # --dry-run are no exception.
  #
  # Captured rather than --quiet, because the reasons differ too much to guess
  # at: an unreachable origin says so itself, while a local tag that disagrees
  # with origin's is a "! [rejected] ... would clobber existing tag" that
  # --quiet swallows whole, leaving a refusal with nothing behind it. Held back
  # until the fetch fails, so an ordinary run still prints none of it.
  local fetch_output=""
  if ! fetch_output=$(git fetch --tags origin 2>&1); then
    [[ -z $fetch_output ]] || printf '%s\n' "$fetch_output" >&2
    baseline_refusal stale-tags origin
  fi

  if [[ -n $since ]]; then
    verify_ref "$since"
    BASELINE_REF="$since"
  else
    BASELINE_REF=$(nearest_version_tag "$target")
  fi

  local version_tag="$BASELINE_REF"
  if [[ -n $BASELINE_REF && ! $BASELINE_REF =~ $VERSION_TAG_RE ]]; then
    version_tag=$(nearest_version_tag "$BASELINE_REF")
  fi

  CURRENT_VERSION="0.0.0"
  if [[ $version_tag =~ $VERSION_TAG_RE ]]; then
    CURRENT_VERSION="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
  fi
}

# verify_trunk_contains <target ref> — the trunk reaches <target>, or the
# release stops.
#
# A version tag has to sit on a commit the trunk carries. One that does not is
# a stranded tag from the moment it is written: the next release resolves its
# baseline from the trunk, `git describe` never reaches this tag, and the
# version count silently restarts from an older one. A `release/*` branch that
# grew a commit after it was cut is the usual way in — a version bump, a note,
# a hotfix — and a trunk holding commits nobody pushed is the other.
#
# It is the trunk origin holds that answers, never the local branch. A CI job
# that checks a `release/*` ref out has no local trunk at all, and a stale
# local one would wave through exactly the commit this guard exists to catch.
# Hence the fetch, and FETCH_HEAD to read it: that is what the fetch just
# wrote, whatever refspec the remote happens to be configured with.
#
# --dry-run warns where the others refuse, and it is the one guard that bends
# that way. The shallow and stale-tag refusals are about the version being
# wrong, so previewing one is worse than previewing nothing; this one is about
# where the tag lands, and a dry run writes no tag to strand. Refusing anyway
# would break the use the flag exists for: a consumer previewing a pull
# request's release runs on the PR head, which the trunk does not contain and
# never will until it merges.
verify_trunk_contains() {
  local target="$1"

  note "Fetching the trunk '${TRUNK}' from origin..."
  # An error, not a refusal. origin was reachable a moment ago: resolve_baseline
  # fetched the tags from it, and refused the release when it could not. So a
  # fetch that fails here is origin holding no branch by that name — a trunk the
  # caller got wrong, which verify_ref already treats as EXIT_ERROR.
  local fetch_output=""
  if ! fetch_output=$(git fetch origin "$TRUNK" 2>&1); then
    [[ -z $fetch_output ]] || printf '%s\n' "$fetch_output" >&2
    die "cannot fetch the trunk '${TRUNK}' from origin: git's own reason is above — name the branch releases are cut from with --trunk <name>"
  fi

  # Told apart rather than folded together: `--is-ancestor` answers 1 for a
  # commit the trunk does not contain and something else when it could not
  # tell, and reporting the second as the first would send its author off to
  # rebase a branch that is already where it belongs.
  local contained=0
  git merge-base --is-ancestor "${target}^{commit}" FETCH_HEAD || contained=$?
  case "$contained" in
    0) return 0 ;;
    1) ;;
    *) die "cannot tell whether origin/${TRUNK} contains ${target}: git merge-base exited ${contained}" ;;
  esac

  local where
  where="${target} ($(git rev-parse --short "${target}^{commit}"))"
  if [[ $DRY_RUN == true ]]; then
    warn "origin/${TRUNK} does not contain ${where}: a real run would refuse to tag there"
    return 0
  fi
  baseline_refusal off-trunk "$TRUNK" "$where"
}

# ------------------------------------------------------------------ preflight

(( BASH_VERSINFO[0] >= 4 )) || die "bash 4+ required (running ${BASH_VERSION})"
command -v git >/dev/null 2>&1 || die "git not found in PATH"
command -v gh  >/dev/null 2>&1 || die "GitHub CLI (gh) not found in PATH"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git repository"
gh auth status >/dev/null 2>&1 || die "gh is not logged in — run: gh auth login"

REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner) \
  || die "cannot resolve the GitHub repository for this checkout"
REPO_URL="https://github.com/${REPO}"

# The trunk is the one branch releases are cut from, and GitHub's default
# branch answers for it: a repository whose trunk is `develop` needs no edit
# here. --trunk names it when the two differ, or when there is no default
# branch to read.
if [[ -z $TRUNK ]]; then
  TRUNK=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name // ""') \
    || die "cannot resolve the default branch for this checkout"
  [[ -n $TRUNK ]] || die "cannot resolve the trunk — name it with --trunk <name>"
fi

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
# A release is cut from the trunk, or from a `release/*` branch off it. `HEAD`
# is a detached checkout, which is how CI checks a chosen commit out.
case "$CURRENT_BRANCH" in
  "$TRUNK" | release/* | HEAD) ;;
  *) warn "you are on '${CURRENT_BRANCH}', not '${TRUNK}' or a 'release/*' branch" ;;
esac

[[ -n $TO_REF ]] || TO_REF="HEAD"
verify_ref "$TO_REF"

if [[ $(git rev-parse "$TO_REF") == $(git rev-parse HEAD) ]]; then
  if [[ -n $(git status --porcelain) ]]; then
    warn "the working tree is not clean; the tag will only contain committed work"
  fi
fi

# ------------------------------------------------------- step 1: next version

resolve_baseline "$TO_REF" "$SINCE_REF"
# Before the version rather than before the tag, like the refusals above it: a
# run that will refuse should refuse before it prints a version nothing can act
# on. Under --dry-run it warns instead and the version follows, which is the
# whole point of previewing a ref the trunk has yet to take.
verify_trunk_contains "$TO_REF"

if [[ -n $BASELINE_REF ]]; then
  RANGE="${BASELINE_REF}..${TO_REF}"
else
  RANGE="${TO_REF}"
fi

mapfile -t COMMITS < <(git log --no-merges --format=%H "$RANGE")
# Its own exit code: a range with nothing in it is the ordinary state of a
# trunk between releases, and CI should not read it as a failure. The wording
# stays as it was, for the consumers still grepping for it.
(( ${#COMMITS[@]} > 0 )) \
  || stop "$EXIT_NOTHING_TO_RELEASE" "no commit to release in range '${RANGE}'"

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
info "Commit range    : ${RANGE}${BASELINE_REF:+ (last tag: ${BASELINE_REF})}"
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

# The only guard today against a non-monotonic version, and a narrow one: it
# catches the next version colliding with a tag that already exists, not a
# baseline older than the latest release in general.
if git rev-parse --verify --quiet "refs/tags/${NEW_TAG}" >/dev/null; then
  baseline_refusal tag-taken "$NEW_TAG"
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
