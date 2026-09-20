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
# A release the previous run left half published — its tag on origin, its
# GitHub release missing — is resumed at step 4 rather than recomputed.
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
readonly EXIT_ERROR=1              # bad usage, a gate with no terminal, a missing tool, a failed push
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
SUMMARY_OUT=""
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
  # A terminal to read the answer from. /dev/tty can be there and still refuse
  # to open — a CI runner holds no controlling terminal — so opening it is the
  # only test worth making, and it has to happen before the read rather than be
  # inferred from it: a read that fails leaves the same empty answer as a human
  # declining, and a job that forgot --yes would go green having released
  # nothing. The open is a subshell's, so the script's own descriptors are left
  # as its caller handed them over.
  if ! ( exec </dev/tty ) 2>/dev/null; then
    die "no terminal available to confirm '$prompt' — rerun with --yes"
  fi
  local answer=""
  printf '%s%s%s [y/N] ' "$BOLD" "$prompt" "$RESET" >&2
  # The terminal opened a moment ago, so a read that fails here is end-of-input
  # on it: a human who closed it with Ctrl-D, which the empty answer below
  # reads as a decline.
  read -r answer < /dev/tty || true
  case "$answer" in
    [yY] | [yY][eE][sS]) return 0 ;;
    # A human said no. Nothing was released, and nothing went wrong. The
    # version was decided all the same, so the summary is written before the
    # run ends: a consumer reading it learns what the run declined.
    *) write_summary no; info "Stopped before: $prompt"; exit "$EXIT_OK" ;;
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
      --summary <file>  Write what the run decided to <file>, as key=value
                         lines: tag, version, bump, baseline, released.
  -h, --help            Show this help.

Steps (a human gate sits before each one, unless --dry-run):
  1. evaluate the new version from the commit range
  2. build the Markdown release notes
  3. create and push the tag
  4. create the GitHub release

A version tag the target already carries, that origin holds and GitHub has no
release for, is a release left half published by a run that died between steps
3 and 4. It is resumed instead: the version is read off the tag, the notes are
rebuilt over its range, and step 3 has nothing to create — and so no gate in
front of it, leaving step 4's as the only one to answer.

Exit codes:
  0  released, or previewed with --dry-run or --local
  1  error: bad usage, a gate with no terminal, a missing tool, a failed push
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
    --summary)      SUMMARY_OUT="${2:-}"; [[ -n $SUMMARY_OUT ]] || die "--summary needs a path"; shift 2 ;;
    -h | --help)    usage; exit "$EXIT_OK" ;;
    *)              usage >&2; die "unknown option: $1" ;;
  esac
done

case "$FORCE_LEVEL" in
  "" | major | minor | patch) ;;
  *) die "--level must be one of: major, minor, patch" ;;
esac

# ------------------------------------------------------------ release summary
#
# The exit code says how a run ended; --summary says what it decided, so a
# consumer's CI reads the version off a file instead of grepping output meant
# for a human.
#
# Bare `key=value` lines, unquoted, one per line: every value is a tag, a
# version, a bump name or yes/no, so the file reads as it stands, sourced into
# a shell or appended to $GITHUB_OUTPUT. Appended, never pointed at: the file
# is written whole, and GITHUB_OUTPUT holds a step's other outputs too. Adding
# a key means documenting it in usage() and in the README, and pinning it in
# tests/summary.bats.
#
# Every run that got as far as deciding a version writes one — a release, a
# preview, a resume, a gate a human declined — and no other run does. Nothing
# to release, a refusal and an error each decided no version, so they leave the
# path as they found it, a file a previous run wrote there included: the code
# is what tells a consumer whether the file answers for this run.

# write_summary <yes|no> — the release this run decided, or nothing when
# --summary was not asked for or no version was reached.
write_summary() {
  [[ -n $SUMMARY_OUT && -n ${NEW_TAG:-} ]] || return 0

  local bump="${LEVEL:-}"
  # A resume publishes the version the run that pushed the tag decided, so this
  # run bumped nothing. Named rather than left empty, so a consumer matching on
  # major|minor|patch reads a value it cannot mistake for one of them.
  [[ ${RESUMING:-false} == false ]] || bump="none"

  mkdir -p "$(dirname "$SUMMARY_OUT")"
  # Truncated, never appended to: the file is this run's answer, whole.
  cat >"$SUMMARY_OUT" <<EOF
tag=${NEW_TAG}
version=${NEW_VERSION}
bump=${bump}
baseline=${CURRENT_VERSION}
released=$1
EOF
  note "Summary written to ${SUMMARY_OUT}"
}

# ------------------------------------------------------------------- baseline
#
# The baseline is the version tag the next version is computed from.
# resolve_baseline works it out in one place — the tags origin holds, the ref
# the commit range starts at, the version that ref carries — and refusal words
# the reasons a release is refused, wherever they are found, so a refusal still
# to come is added there rather than inline. verify_ref sits beside it for the
# one reason that is not a refusal: a ref the caller got wrong.
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

# refusal <name> [detail] [target] — refuse the release on the named refusal.
# The name picks the wording, so a refusal raised from more than one place
# reads the same in each; every one of them is the repository's state ruling
# the release out, so every one of them exits EXIT_REFUSED. An unrecognised
# name would leave `case` returning 0 and the refusal silent, hence the last
# arm.
#
# detail is whatever that refusal is about, and the name says which: the remote
# for stale-tags, the trunk for off-trunk, the tag for tag-taken. target is the
# ref that would have been tagged, for the refusals naming both ends.
refusal() {
  local detail="${2:-}" target="${3:-}"
  case "$1" in
    shallow)    stop "$EXIT_REFUSED" "shallow clone: the version tags behind the cut are unreachable — fetch the full history (git fetch --unshallow, or fetch-depth: 0 in CI)" ;;
    stale-tags) stop "$EXIT_REFUSED" "could not fetch the version tags from '${detail}': the local tags may be stale, and the baseline read from them older than the last release — git's own reason is above: make '${detail}' reachable, or let its tags win with git fetch --tags --force ${detail}" ;;
    off-trunk)  stop "$EXIT_REFUSED" "origin/${detail} does not contain ${target}: the tag would sit on a commit the trunk cannot reach, where the next release's baseline can't see it — push those commits to ${detail} or rebase them onto it, and check --trunk when ${detail} is not the branch releases are cut from" ;;
    tag-taken)  stop "$EXIT_REFUSED" "tag ${detail} already exists locally" ;;
    *)          stop "$EXIT_REFUSED" "refused: $1" ;;
  esac
}

# nearest_version_tag <ref> -> the nearest version tag reachable from <ref>, or
# nothing when the ref reaches none.
nearest_version_tag() {
  git describe --tags --abbrev=0 --match "$VERSION_TAG_GLOB" "$1" 2>/dev/null || true
}

# version_tag_behind <version tag> -> the nearest version tag reachable from
# <tag> other than <tag> itself, or nothing when it reaches none.
#
# What `git describe` answered for the run that pushed <tag>, back when <tag>
# did not exist yet — so it is the baseline a half-published release was cut
# over, and the notes rebuilt from it come back the same.
version_tag_behind() {
  git describe --tags --abbrev=0 --match "$VERSION_TAG_GLOB" --exclude "$1" "$1" 2>/dev/null || true
}

# resolve_current_version -> CURRENT_VERSION, the version BASELINE_REF carries.
#
# Its own function because BASELINE_REF is set in two places: resolve_baseline
# reads it from --since or from the tag the target reaches, and a resume then
# moves it behind the tag being published, where the version has to follow it.
#
# The ref is a version tag on an ordinary release, but --since accepts any ref
# — a commit hash when replaying history — so the version is the ref's own when
# it is a version tag, the nearest version tag behind it otherwise, and 0.0.0
# when it reaches none at all.
resolve_current_version() {
  local version_tag="$BASELINE_REF"
  if [[ -n $BASELINE_REF && ! $BASELINE_REF =~ $VERSION_TAG_RE ]]; then
    version_tag=$(nearest_version_tag "$BASELINE_REF")
  fi

  CURRENT_VERSION="0.0.0"
  if [[ $version_tag =~ $VERSION_TAG_RE ]]; then
    CURRENT_VERSION="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
  fi
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
  [[ $(git rev-parse --is-shallow-repository 2>/dev/null) != true ]] || refusal shallow

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
    refusal stale-tags origin
  fi

  if [[ -n $since ]]; then
    verify_ref "$since"
    BASELINE_REF="$since"
  else
    BASELINE_REF=$(nearest_version_tag "$target")
  fi

  resolve_current_version
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
  refusal off-trunk "$TRUNK" "$where"
}

# ----------------------------------------------------- half-published release
#
# Step 3 pushes the tag and step 4 creates the GitHub release, so a run that
# dies between the two leaves a half-published release behind: the version tag
# is on origin, and nothing carries its notes.
#
# Re-running used to dead-end there. The tag sits on the very commit the run
# was releasing, so the next run resolves it as its own baseline and finds a
# range with no commit in it — "nothing to release" over a release that never
# happened. Consumers worked around it in YAML, by deleting the tag from origin
# so the next run could re-cut it.
#
# So the script looks for one on the target before it computes a version, and
# resumes at step 4: the version is read off the tag, the notes are rebuilt
# over the range the tag was cut on, and nothing is tagged or pushed.

RESUME_TAG="" # the half-published tag being resumed, empty on an ordinary run

# resolve_resume <target ref> -> RESUME_TAG.
#
# The version tag on <target> that origin holds and GitHub carries no release
# for, or nothing when the target carries no such tag. A global rather than
# something printed, so the two questions it cannot get an answer to can end
# the run: `exit` inside a command substitution would end the subshell alone,
# and the caller would carry on with the code lost.
resolve_resume() {
  local target="$1" tag=""
  RESUME_TAG=""

  # The highest version tag on the target's commit. release.sh writes one tag
  # per release, so more than one there is somebody else's doing; the highest
  # is the release the repository is furthest along.
  tag=$(git tag --list "$VERSION_TAG_GLOB" --points-at "${target}^{commit}" --sort=v:refname | tail -n 1)
  [[ -n $tag ]] || return 0

  # origin's tag, never the machine's. A tag --local wrote, or one made by
  # hand, has no release for the plain reason that it was never pushed: what it
  # is waiting for is step 3, not step 4.
  #
  # Told apart rather than folded together, the way verify_trunk_contains tells
  # its answer from a git that could not give one: --exit-code answers 2 for a
  # ref the remote does not hold, and something else when the lookup itself
  # failed. Reading the second as the first would turn a lost network into
  # "nothing to release" over a release waiting to be published.
  local held=0
  git ls-remote --exit-code --tags origin "refs/tags/${tag}" >/dev/null || held=$?
  case "$held" in
    0) ;;
    2) return 0 ;;
    *) die "cannot tell whether origin holds ${tag}: git ls-remote exited ${held}" ;;
  esac

  # `gh release view` exits non-zero both for a tag with no release and for gh
  # failing outright, and no code tells those apart either. So a failure is put
  # back to gh: a repo view that answers proves the lookup really did find
  # nothing, while one that does not leaves the run unable to tell — and
  # publishing over a release that may already be there is not a guess worth
  # making.
  if gh release view "$tag" --repo "$REPO" >/dev/null 2>&1; then
    return 0
  fi
  gh repo view "$REPO" --json nameWithOwner >/dev/null \
    || die "cannot tell whether ${tag} has a GitHub release: gh's own reason is above"

  RESUME_TAG="$tag"
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

# ------------------------------------------------------------ step 1: version

resolve_baseline "$TO_REF" "$SINCE_REF"
# Before the version rather than before the tag, like the refusals above it: a
# run that will refuse should refuse before it prints a version nothing can act
# on. Under --dry-run it warns instead and the version follows, which is the
# whole point of previewing a ref the trunk has yet to take.
#
# A resume answers to it too, ahead of being recognised as one. The tag it
# would publish is written already, so the guard undoes nothing there — but a
# release on a stranded tag is one more thing to unpick once the topology is
# put right, and the fix the refusal names is the same either way.
verify_trunk_contains "$TO_REF"

# A half-published release on the target ends the version computation before it
# starts: the version is the tag's, and the run has only step 4 left to do.
resolve_resume "$TO_REF"
RESUMING=false

if [[ -n $RESUME_TAG ]]; then
  RESUMING=true
  note "${RESUME_TAG} is on origin with no GitHub release: resuming it at step 4 rather than computing a new version."
  # The baseline the run that pushed the tag resolved, so the notes come back
  # the same. --since still wins over it, the way it does for a release being
  # cut.
  [[ -n $SINCE_REF ]] || BASELINE_REF=$(version_tag_behind "$RESUME_TAG")
  # And the version that baseline carries: the one resolve_baseline read is
  # off the tag being resumed, which is the release being published, not the
  # release before it.
  resolve_current_version
fi

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

if [[ $RESUMING == true ]]; then
  NEW_TAG="$RESUME_TAG"
  NEW_VERSION="${NEW_TAG#v}"
  # Nothing left for it to force: the version was decided by the run that wrote
  # the tag. Said out loud rather than dropped, since a caller passing it wants
  # a version this run is not the one to choose.
  [[ -z $FORCE_LEVEL ]] \
    || warn "--level is ignored on a resume: ${NEW_TAG} already carries the version"
else
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
fi

if [[ $RESUMING == true ]]; then
  step "Step 1 — resume the half-published ${NEW_TAG}"
else
  step "Step 1 — evaluate the new version"
fi
info "Repository      : ${REPO}"
info "Branch          : ${CURRENT_BRANCH}"
info "Commit range    : ${RANGE}${BASELINE_REF:+ (last tag: ${BASELINE_REF})}"
if [[ $TO_REF != "HEAD" ]]; then
  if [[ $RESUMING == true ]]; then
    info "Target ref      : ${TO_REF} (the tag is there, not on HEAD)"
  else
    info "Target ref      : ${TO_REF} (tag will be created there, not on HEAD)"
  fi
fi
info "Commits scanned : ${#COMMITS[@]}"
info ""
for i in "${!C_HASH[@]}"; do
  printf '  %s%-9s%s %s %s%s%s\n' \
    "$YELLOW" "${C_CATEGORY[$i]}" "$RESET" "${C_SHORT[$i]}" "$DIM" "${C_SUBJECT[$i]}" "$RESET"
done
info ""
if [[ $RESUMING == true ]]; then
  info "Version         : ${BOLD}${GREEN}${NEW_VERSION}${RESET} (read off ${NEW_TAG}, which origin already holds)"
else
  info "Bump            : ${BOLD}${LEVEL}${RESET}${FORCE_LEVEL:+ (forced with --level)}"
  info "Version         : ${CURRENT_VERSION} -> ${BOLD}${GREEN}${NEW_VERSION}${RESET}"

  # The only guard today against a non-monotonic version, and a narrow one: it
  # catches the next version colliding with a tag that already exists, not a
  # baseline older than the latest release in general. A tag on the target with
  # no release never reaches it: that one is a resume, decided above.
  if git rev-parse --verify --quiet "refs/tags/${NEW_TAG}" >/dev/null; then
    refusal tag-taken "$NEW_TAG"
  fi
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

# --------------------------------------------------------- step 3: tag & push

if [[ $RESUMING == true ]]; then
  # No gate in front of it. A gate holds back a step that writes something, and
  # this one writes nothing: the tag it would have created is on origin
  # already, which is what made this run a resume.
  step "Step 3 — ${NEW_TAG} is already on origin"
  note "[resume] the tag was pushed before the release that never happened; it is not recreated"
else
  gate "Continue to step 3 and create the tag ${NEW_TAG}?"

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
fi

gate "Continue to step 4 and publish the GitHub release ${NEW_TAG}?"

# ------------------------------------------------------------ step 4: release

step "Step 4 — publish the release ${NEW_TAG}"

if [[ $DRY_RUN == true ]]; then
  note "[dry-run] gh release create ${NEW_TAG} --title ${NEW_TAG} --notes-file <notes>"
  if [[ $RESUMING == true ]]; then
    note "[dry-run] ${NEW_TAG} is already on origin: a real run would publish its release"
  else
    note "[dry-run] no tag was pushed, so no release was created"
  fi
elif [[ $LOCAL_ONLY == true ]]; then
  note "[local] gh release create ${NEW_TAG} --title ${NEW_TAG} --notes-file <notes>"
  if [[ $RESUMING == true ]]; then
    note "[local] ${NEW_TAG} is on origin, but --local creates no release"
  else
    note "[local] the tag stays on this machine, so no release was created"
  fi
else
  gh release create "$NEW_TAG" \
    --repo "$REPO" \
    --title "$NEW_TAG" \
    --notes-file "$NOTES_FILE" \
    --verify-tag
  printf '\n%s%sReleased %s%s\n' "$BOLD" "$GREEN" "$NEW_TAG" "$RESET"
  info "${REPO_URL}/releases/tag/${NEW_TAG}"
fi

# Last, once nothing is left that could change the answer: a consumer that
# finds the file can read every line of it as final. A gh that failed above
# took the run down with it, and wrote none.
if [[ $DRY_RUN == true || $LOCAL_ONLY == true ]]; then
  write_summary no
else
  write_summary yes
fi
