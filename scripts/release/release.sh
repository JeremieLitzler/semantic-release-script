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
LEVEL_FROM=""
FORCE_LEVEL_OPTION="--level" # how the run names the option that forced the level, in what it says only
NOTES_OUT=""
CHANGELOG_OUT=""
SUMMARY_OUT=""
TRUNK=""
CHECK_ONLY=false
RELEASE_OPTIONS=() # the options given that only shape a release, which --check refuses

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
      --level-from <ref>
                         Force the bump from a branch name: the segment after
                         release/ in release/<major|minor|patch>/<id>, or the
                         bare release/<major|minor|patch>. A name
                         with no level there changes nothing. Must be a branch,
                         locally or on origin. A level below the one
                         the commits imply is refused. Not with --level.
      --notes <file>    Also write the release notes to <file>.
      --changelog <f>   Prepend the release to the changelog <f> (newest first).
      --summary <file>  Write what the run decided to <file>, as key=value
                         lines: tag, version, bump, baseline, released.
      --check           Print the setup report instead of releasing: every
                         check of the preflight and every guard, each with its
                         reason and its fix. Decides no version and writes no
                         file. Takes only --trunk, --to, --since and
                         --level-from.
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
     With --check, 0 and 3 say no check a release would refuse on failed, or one did.
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
    --check)        CHECK_ONLY=true; shift ;;
    -y | --yes)     ASSUME_YES=true; RELEASE_OPTIONS+=("$1"); shift ;;
    -n | --dry-run) DRY_RUN=true; RELEASE_OPTIONS+=("$1"); shift ;;
    -l | --local)   LOCAL_ONLY=true; RELEASE_OPTIONS+=("$1"); shift ;;
    --since)        SINCE_REF="${2:-}"; [[ -n $SINCE_REF ]] || die "--since needs a ref"; shift 2 ;;
    --to)           TO_REF="${2:-}"; [[ -n $TO_REF ]] || die "--to needs a ref"; shift 2 ;;
    --trunk)        TRUNK="${2:-}"; [[ -n $TRUNK ]] || die "--trunk needs a name"; shift 2 ;;
    --level)        FORCE_LEVEL="${2:-}"; RELEASE_OPTIONS+=("$1"); shift 2 ;;
    --level-from)   LEVEL_FROM="${2:-}"; [[ -n $LEVEL_FROM ]] || die "--level-from needs a ref"; shift 2 ;;
    --notes)        NOTES_OUT="${2:-}"; [[ -n $NOTES_OUT ]] || die "--notes needs a path"; RELEASE_OPTIONS+=("$1"); shift 2 ;;
    --changelog)    CHANGELOG_OUT="${2:-}"; [[ -n $CHANGELOG_OUT ]] || die "--changelog needs a path"; RELEASE_OPTIONS+=("$1"); shift 2 ;;
    --summary)      SUMMARY_OUT="${2:-}"; [[ -n $SUMMARY_OUT ]] || die "--summary needs a path"; RELEASE_OPTIONS+=("$1"); shift 2 ;;
    -h | --help)    usage; exit "$EXIT_OK" ;;
    *)              usage >&2; die "unknown option: $1" ;;
  esac
done

# A report that took --notes would leave a human believing it wrote the file.
# Only the options that name the target mean anything to it.
if [[ $CHECK_ONLY == true && ${#RELEASE_OPTIONS[@]} -gt 0 ]]; then
  die "--check accepts only --trunk, --to, --since and --level-from, not ${RELEASE_OPTIONS[0]}"
fi

case "$FORCE_LEVEL" in
  "" | major | minor | patch) ;;
  *) die "--level must be one of: major, minor, patch" ;;
esac

if [[ -n $LEVEL_FROM ]]; then
  [[ -z $FORCE_LEVEL ]] || die "--level and --level-from cannot be used together"
  # Exactly major, minor or patch, lowercase, as the whole segment after
  # release/. Anything else is a name that carries no level, left as it was.
  if [[ ${LEVEL_FROM#refs/heads/} =~ ^release/(major|minor|patch)(/|$) ]]; then
    FORCE_LEVEL="${BASH_REMATCH[1]}"
    FORCE_LEVEL_OPTION="--level-from"
  fi
fi

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
# for stale-tags, the trunk for off-trunk, the tag for tag-taken, the baseline's
# tag for baseline-not-highest and baseline-gone. target is the ref that would
# have been tagged, for the refusals naming both ends, and the highest version tag for the one
# that weighs the baseline against it.
refusal() {
  stop "$EXIT_REFUSED" "$(refusal_reason "$@")"
}

# refusal_reason <name> [detail] [target] — the words of a refusal, for the
# setup report to list a check the way a release would refuse it.
refusal_reason() {
  local detail="${2:-}" target="${3:-}" stranded="${4:-}"
  case "$1" in
    shallow)    printf '%s' "shallow clone: the version tags behind the cut are unreachable — fetch the full history (git fetch --unshallow, or fetch-depth: 0 in CI)" ;;
    stale-tags) printf '%s' "could not fetch the version tags from '${detail}': the local tags may be stale, and the baseline read from them older than the last release — git's own reason is above: make '${detail}' reachable, or let its tags win with git fetch --tags --force ${detail}" ;;
    off-trunk)  printf '%s' "origin/${detail} does not contain ${target}: the tag would sit on a commit the trunk cannot reach, where the next release's baseline can't see it — push those commits to ${detail} or rebase them onto it, and check --trunk when ${detail} is not the branch releases are cut from" ;;
    tag-taken)  printf '%s' "tag ${detail} already exists locally — it is the release already cut there: name a later target with --to or an earlier baseline with --since, or delete the tag if it is stale" ;;
    baseline-gone)
      printf '%s' "the baseline ${detail} is not on origin: it was deleted there (the fetch only ever adds tags, so the local copy survives) or never pushed (a --local tag), and the commits it released would drop out of the next release's notes. Push it (git push origin ${detail}), or delete the local tag (git tag -d ${detail}) if the release was withdrawn" ;;
    baseline-not-highest)
      printf '%s' "the baseline ${detail} is not the highest version tag in the repository, ${target}: the next version would not be above every release already cut"
      if [[ -n $stranded ]]; then
        printf '%s' " — above it, ${stranded} sit on commits the target cannot reach (stranded tags). Find each one's twin, the trunk commit with the same tree: git rev-parse <tag>^{tree} against git log --format='%h %T'"
      else
        printf '%s' " — every version tag is reachable, so check that --since names a release no older than ${target}"
      fi ;;
    level-lowered)
      printf '%s' "the branch name forces ${detail}, below the ${target} the commits imply: the release would publish less than the changes it carries — rename the branch to release/${target}/<id>, or to a name without a level to let the commits decide" ;;
    *)          printf '%s' "refused: $1" ;;
  esac
}

# The guards as checks, so a release stops on the first one that fails and the
# setup report lists them all. Each returns 0 when it holds, and 1 with the
# reason in CHECK_FAILURE (fail_check, below) when it does not.

check_not_shallow() {
  # Before the fetch, because the fetch cannot repair it: the tag refs come
  # back, the commits they name stay behind the cut, and `git describe` reaches
  # none of them. Only `true` refuses, so a git too old to know the option
  # (< 2.15) leaves the release alone rather than claiming a shallow clone.
  [[ $(git rev-parse --is-shallow-repository 2>/dev/null) != true ]] \
    || fail_check "$(refusal_reason shallow)"
}

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
check_tags_fetched() {
  local fetch_output=""
  if ! fetch_output=$(git fetch --tags origin 2>&1); then
    [[ -z $fetch_output ]] || printf '%s\n' "$fetch_output" >&2
    fail_check "$(refusal_reason stale-tags origin)"
  fi
}

# origin was reachable a moment ago, when the tags came from it. So a fetch that
# fails here is origin holding no branch by that name: a trunk the caller got
# wrong, which verify_ref already treats as EXIT_ERROR.
check_trunk_fetched() {
  local fetch_output=""
  if ! fetch_output=$(git fetch origin "$TRUNK" 2>&1); then
    [[ -z $fetch_output ]] || printf '%s\n' "$fetch_output" >&2
    fail_check "cannot fetch the trunk '${TRUNK}' from origin: git's own reason is above — name the branch releases are cut from with --trunk <name>"
  fi
}

# check_trunk_contains <target ref> — returns 0 when the trunk just fetched
# carries <target>, 1 when it does not, and 2 when git could not tell. Told
# apart rather than folded together: `--is-ancestor` answers 1 for a commit the
# trunk does not contain and something else when it could not tell, and
# reporting the second as the first would send its author off to rebase a
# branch that is already where it belongs.
check_trunk_contains() {
  local target="$1" contained=0
  git merge-base --is-ancestor "${target}^{commit}" FETCH_HEAD || contained=$?
  case "$contained" in
    0) return 0 ;;
    1) CHECK_FAILURE="$(refusal_reason off-trunk "$TRUNK" "${target} ($(git rev-parse --short "${target}^{commit}"))")"
       return 1 ;;
    *) CHECK_FAILURE="cannot tell whether origin/${TRUNK} contains ${target}: git merge-base exited ${contained}"
       return 2 ;;
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
  check_not_shallow || stop "$EXIT_REFUSED" "$CHECK_FAILURE"

  note "Fetching tags from origin..."
  # The tags are what the baseline is read from, so a fetch that fails is a
  # refusal (see check_tags_fetched): it leaves the stale local tags in place.
  check_tags_fetched || stop "$EXIT_REFUSED" "$CHECK_FAILURE"

  select_baseline "$target" "$since"
}

# select_baseline <target ref> [since ref] -> BASELINE_REF and CURRENT_VERSION,
# once the tags it reads are known to be whole (check_not_shallow and
# check_tags_fetched): a release goes through them in resolve_baseline, and the
# setup report has listed them already.
select_baseline() {
  local target="$1" since="${2:-}"
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
  check_trunk_fetched || die "$CHECK_FAILURE"

  local contained=0
  check_trunk_contains "$target" || contained=$?
  case "$contained" in
    0) return 0 ;;
    1) ;;
    *) die "$CHECK_FAILURE" ;;
  esac

  if [[ $DRY_RUN == true ]]; then
    warn "origin/${TRUNK} does not contain ${target} ($(git rev-parse --short "${target}^{commit}")): a real run would refuse to tag there"
    return 0
  fi
  stop "$EXIT_REFUSED" "$CHECK_FAILURE"
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
# and the caller would carry on with the code lost. They return 1 with the
# reason in CHECK_FAILURE, and the caller decides what that ends.
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
    *) fail_check "cannot tell whether origin holds ${tag}: git ls-remote exited ${held}"; return ;;
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
    || { fail_check "cannot tell whether ${tag} has a GitHub release: gh's own reason is above"; return; }

  RESUME_TAG="$tag"
}

# ------------------------------------------------------------------ preflight

# Each check returns 0 when it holds. When it does not, it returns 1 with the
# reason in CHECK_FAILURE, so the preflight can stop on the first failure today
# and a mode that lists every check can reuse them as they are.
CHECK_FAILURE=""
fail_check() { CHECK_FAILURE="$*"; return 1; }

check_bash_version() {
  (( BASH_VERSINFO[0] >= 4 )) || fail_check "bash 4+ required (running ${BASH_VERSION})"
}
check_git_installed() {
  command -v git >/dev/null 2>&1 || fail_check "git not found in PATH"
}
check_gh_installed() {
  command -v gh >/dev/null 2>&1 || fail_check "GitHub CLI (gh) not found in PATH"
}
check_inside_work_tree() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail_check "not inside a git repository"
}
check_gh_logged_in() {
  gh auth status >/dev/null 2>&1 || fail_check "gh is not logged in — run: gh auth login"
}
# Sets REPO and REPO_URL.
check_repository() {
  REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner) \
    || { fail_check "cannot resolve the GitHub repository for this checkout"; return; }
  REPO_URL="https://github.com/${REPO}"
}
# The trunk is the one branch releases are cut from, and GitHub's default
# branch answers for it: a repository whose trunk is `develop` needs no edit
# here. --trunk names it when the two differ, or when there is no default
# branch to read. Sets TRUNK.
check_trunk() {
  [[ -z $TRUNK ]] || return 0
  TRUNK=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name // ""') \
    || { fail_check "cannot resolve the default branch for this checkout"; return; }
  [[ -n $TRUNK ]] || fail_check "cannot resolve the trunk — name it with --trunk <name>"
}

# The checks in the order they run.
PREFLIGHT_CHECKS=(
  check_bash_version
  check_git_installed
  check_gh_installed
  check_inside_work_tree
  check_gh_logged_in
  check_repository
  check_trunk
)

# Runs the checks in order and stops on the first one that fails.
preflight() {
  local check
  for check in "${PREFLIGHT_CHECKS[@]}"; do
    "$check" || die "$CHECK_FAILURE"
  done
}

# Only a warning in a release, and listed as one in the setup report: neither
# stops the release, so neither is a failure.

# A release is cut from the trunk, or from a `release/*` branch off it. `HEAD`
# is a detached checkout, which is how CI checks a chosen commit out.
check_branch() {
  CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
  case "$CURRENT_BRANCH" in
    "$TRUNK" | release/* | HEAD) ;;
    *) fail_check "you are on '${CURRENT_BRANCH}', not '${TRUNK}' or a 'release/*' branch" ;;
  esac
}

# Only the work done on HEAD can be left out of the tag.
check_tree_clean() {
  [[ $(git rev-parse "$TO_REF") == $(git rev-parse HEAD) ]] || return 0
  [[ -z $(git status --porcelain) ]] \
    || fail_check "the working tree is not clean; the tag will only contain committed work"
}

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

# classify_commits -> C_HASH, C_SHORT, C_SUBJECT and C_CATEGORY, one entry per
# commit in COMMITS.
classify_commits() {
  local hash raw short rest subject body
  for hash in "${COMMITS[@]}"; do
    raw=$(git show -s --format=$'%h\x1f%s\x1f%b' "$hash")
    short="${raw%%$'\x1f'*}"; rest="${raw#*$'\x1f'}"
    subject="${rest%%$'\x1f'*}"; body="${rest#*$'\x1f'}"

    C_HASH+=("$hash")
    C_SHORT+=("$short")
    C_SUBJECT+=("$subject")
    C_CATEGORY+=("$(classify "$subject" "$body")")
  done
}

# scan_commits <target ref> -> RANGE and COMMITS: the commits the baseline
# leaves out of the target, merges aside. Shared with the setup report, which
# weighs the version a release would compute without printing it.
scan_commits() {
  local target="$1"
  if [[ -n $BASELINE_REF ]]; then
    RANGE="${BASELINE_REF}..${target}"
  else
    RANGE="${target}"
  fi
  mapfile -t COMMITS < <(git log --no-merges --format=%H "$RANGE")
}

IMPLIED_LEVEL="" # the bump the commits decide, before any forcing

# next_version -> IMPLIED_LEVEL, LEVEL, NEW_VERSION and NEW_TAG, from the
# categories of the commits classified and the version the baseline carries.
next_version() {
  LEVEL="patch"
  local category
  for category in "${C_CATEGORY[@]}"; do
    case "$category" in
      breaking) LEVEL="major"; break ;;
      feature)  LEVEL="minor" ;;
    esac
  done
  IMPLIED_LEVEL="$LEVEL"
  [[ -n $FORCE_LEVEL ]] && LEVEL="$FORCE_LEVEL"

  local major minor patch
  IFS='.' read -r major minor patch <<<"$CURRENT_VERSION"
  case "$LEVEL" in
    major) major=$((major + 1)); minor=0; patch=0 ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    patch) patch=$((patch + 1)) ;;
  esac
  NEW_VERSION="${major}.${minor}.${patch}"
  NEW_TAG="v${NEW_VERSION}"
}

# check_tag_free — the tag a release would write does not exist yet. A tag on
# the target that origin holds with no release is a resume, decided before it
# gets here.
check_tag_free() {
  if git rev-parse --verify --quiet "refs/tags/${NEW_TAG}" >/dev/null; then
    fail_check "$(refusal_reason tag-taken "$NEW_TAG")"
  fi
}

# check_level_not_lowered — a level forced by the branch name is not below the
# one the commits imply. Forcing up is allowed (the v1.0.0 case), and so is an
# explicit --level, which is the caller's own word rather than a name that may
# have been cut for another range.
check_level_not_lowered() {
  [[ $FORCE_LEVEL_OPTION == "--level-from" && -n $FORCE_LEVEL ]] || return 0
  local forced implied
  forced=$(level_rank "$FORCE_LEVEL"); implied=$(level_rank "$IMPLIED_LEVEL")
  (( forced >= implied )) \n    || fail_check "$(refusal_reason level-lowered "$FORCE_LEVEL" "$IMPLIED_LEVEL")"
}

# level_rank <level> -> a number that grows with the bump.
level_rank() {
  case "$1" in major) echo 3 ;; minor) echo 2 ;; *) echo 1 ;; esac
}

# version_tags -> every version tag in the repository, highest first. The glob
# alone also matches a prerelease such as v1.0.0-rc1, which is no version tag
# and which `--sort=-v:refname` ranks above v1.0.0, so the name is held to
# vMAJOR.MINOR.PATCH here.
version_tags() {
  git tag --list "$VERSION_TAG_GLOB" --sort=-v:refname \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' || true
}

# check_baseline_on_origin — the baseline, when it is a version tag, is still
# held by origin.
#
# `git fetch --tags` never removes anything, so a tag deleted on origin
# survives locally and the fetch still succeeds: the baseline then resolves to
# a release nobody can see. Not --prune-tags, which does nothing without
# --prune and with it deletes the local-only tag --local creates. Told apart
# the way resolve_resume tells it: --exit-code answers 2 for a ref the remote
# does not hold, and anything else is the lookup failing. A tag --local wrote
# and never pushed is refused the same way: git cannot tell it from a deleted
# one, and the next release has to be cut from a tag origin holds.
check_baseline_on_origin() {
  [[ $BASELINE_REF =~ $VERSION_TAG_RE ]] || return 0
  git rev-parse --verify --quiet "refs/tags/${BASELINE_REF}" >/dev/null || return 0

  local held=0 lookup_output=""
  lookup_output=$(git ls-remote --exit-code --tags origin "refs/tags/${BASELINE_REF}" 2>&1) || held=$?
  case "$held" in
    0) ;;
    2) fail_check "$(refusal_reason baseline-gone "$BASELINE_REF")" ;;
    *) [[ -z $lookup_output ]] || printf '%s
' "$lookup_output" >&2
       fail_check "cannot tell whether origin holds ${BASELINE_REF}: git ls-remote exited ${held}" ;;
  esac
}

# check_baseline_highest — the baseline is the highest version tag in the
# repository. On a single trunk, the next version can only fall at or below
# a release already cut when the baseline is older than the latest one: the
# tags the target cannot reach (stranded tags), or a --since older than the
# latest release. One check covers both, and lists the stranded tags it finds.
#
# CURRENT_VERSION is the baseline's version, so a run with no baseline and
# tags somewhere else refuses as well: 0.0.0 is below every one of them.
#
# Only the tags above the baseline are listed: a stranded tag below it is no
# reason for this refusal. A tag is stranded when git answers 1 to whether the
# target carries it; any other answer is git failing to tell, which lists
# nothing rather than a tag that may be fine.
check_baseline_highest() {
  local highest
  highest=$(version_tags | head -n 1)
  [[ -n $highest ]] || return 0
  [[ ${highest#v} != "$CURRENT_VERSION" ]] || return 0

  local tag reachable stranded=""
  while IFS= read -r tag; do
    [[ $(printf '%s\n%s\n' "${tag#v}" "$CURRENT_VERSION" | sort -V | tail -n 1) != "$CURRENT_VERSION" ]] \
      || break
    reachable=0
    git merge-base --is-ancestor "${tag}^{commit}" "${TO_REF}^{commit}" 2>/dev/null \
      || reachable=$?
    [[ $reachable -ne 1 ]] \
      || stranded+="${stranded:+, }${tag} ($(git rev-parse --short "${tag}^{commit}"))"
  done < <(version_tags)

  fail_check "$(refusal_reason baseline-not-highest "v${CURRENT_VERSION}" "$highest" "$stranded")"
}

# ---------------------------------------------------------------- setup report
#
# `--check` runs every check above and every guard against the target a release
# would use, and lists them all, so a human sees what would stop a release at
# once rather than the first thing. It decides no version and writes no file;
# the one thing it shares with a release is the fetch of the tags.
#
# A failing check is what a release would stop on, and ends the report on
# EXIT_REFUSED. A check whose input a failing one withheld is skipped, and what
# the report cannot even start on (no git, no gh, a ref that does not exist) is
# an error, as it is for a release.

REPORT_STATUS=() # ok, warn, FAIL, skip or info
REPORT_LABEL=()
REPORT_DETAIL=() # the reason and the fix, one per line
REPORT_FAILURES=0
REPORT_OK=false  # whether the check listed last held

# report <status> <label> [detail]
report() {
  REPORT_STATUS+=("$1")
  REPORT_LABEL+=("$2")
  REPORT_DETAIL+=("${3:-}")
  [[ $1 != FAIL ]] || REPORT_FAILURES=$((REPORT_FAILURES + 1))
}

# report_check <fail|warn> <label> <fix> <check> [args...] — run one check and
# list its result. The reason is the check's own, and the fix is said apart for
# the checks whose reason does not carry one.
report_check() {
  local level="$1" label="$2" fix="$3"; shift 3
  CHECK_FAILURE=""
  if "$@"; then
    REPORT_OK=true
    report ok "$label"
    return 0
  fi
  local status="FAIL"
  REPORT_OK=false
  if [[ $level == warn ]]; then status="warn"; REPORT_OK=true; fi
  report "$status" "$label" "${CHECK_FAILURE}${fix:+$'\n'fix: ${fix}}"
}

# report_skip <label> <what it needed>
report_skip() {
  REPORT_OK=false
  report skip "$1" "needs ${2}"
}

print_report() {
  step "Setup report"
  local i colour line
  for i in "${!REPORT_STATUS[@]}"; do
    case "${REPORT_STATUS[$i]}" in
      ok)         colour="$GREEN" ;;
      FAIL)       colour="$RED" ;;
      warn)       colour="$YELLOW" ;;
      *)          colour="$DIM" ;;
    esac
    printf '%s%-4s%s  %s\n' "$colour" "${REPORT_STATUS[$i]}" "$RESET" "${REPORT_LABEL[$i]}"
    if [[ -n ${REPORT_DETAIL[$i]} ]]; then
      while IFS= read -r line; do
        printf '        %s\n' "$line"
      done <<<"${REPORT_DETAIL[$i]}"
    fi
  done
  printf '\n'
}

run_setup_report() {
  # Nothing to evaluate with: this is not a report but a run that cannot start.
  check_git_installed || die "$CHECK_FAILURE"
  check_gh_installed || die "$CHECK_FAILURE"

  local in_repo=false repository=false trunk=false
  report_check fail "bash 4 or later" "install bash 4 or later and run the script with it" check_bash_version
  report ok "git installed"
  report ok "gh installed"
  report_check fail "inside a git repository" "run it from inside the checkout" check_inside_work_tree
  in_repo=$REPORT_OK
  report_check fail "gh is logged in" "" check_gh_logged_in
  if [[ $REPORT_OK == true ]]; then
    report_check fail "the GitHub repository resolves" "check that the checkout's remote is a GitHub repository gh can see" check_repository
    repository=$REPORT_OK
  else
    report_skip "the GitHub repository resolves" "gh logged in"
  fi
  if [[ -n $TRUNK || $repository == true ]]; then
    report_check fail "the trunk is known" "" check_trunk
    trunk=$REPORT_OK
  else
    report_skip "the trunk is known" "the GitHub repository"
  fi

  if [[ $in_repo != true || $trunk != true ]]; then
    report_skip "the release guards" "a git repository and a trunk"
    return
  fi

  [[ -n $TO_REF ]] || TO_REF="HEAD"
  verify_ref "$TO_REF"
  [[ -z $SINCE_REF ]] || verify_ref "$SINCE_REF"

  report_check warn "on the trunk or a release branch" "" check_branch
  report_check warn "the working tree is clean" "" check_tree_clean
  report_check fail "not a shallow clone" "" check_not_shallow
  local tags_whole=$REPORT_OK
  report_check fail "the version tags can be fetched from origin" "" check_tags_fetched
  [[ $REPORT_OK == true ]] || tags_whole=false
  report_check fail "the trunk '${TRUNK}' is reachable on origin" "" check_trunk_fetched
  if [[ $REPORT_OK == true ]]; then
    report_check fail "the trunk carries ${TO_REF}" "" check_trunk_contains "$TO_REF"
  else
    report_skip "the trunk carries ${TO_REF}" "the trunk fetched"
  fi

  # The guards over the version a release would write. Weighed on the version
  # it would compute, not printed: the report decides none.
  local resume_known=false
  if [[ $repository != true ]]; then
    report_skip "half-published release" "the GitHub repository"
  elif resolve_resume "$TO_REF"; then
    resume_known=true
    if [[ -n $RESUME_TAG ]]; then
      # A state, not a failure: the next run finishes the release.
      report info "half-published release" "${RESUME_TAG} is on origin with no GitHub release: a release would resume it at step 4"
    else
      report ok "no half-published release"
    fi
  else
    report FAIL "half-published release" "$CHECK_FAILURE"
  fi

  local needs=""
  if [[ $tags_whole != true ]]; then
    needs="the shallow clone and version tag checks to hold"
  elif [[ $resume_known != true ]]; then
    needs="the half-published release lookup"
  fi
  if [[ -n $needs ]]; then
    report_skip "the next tag is free" "$needs"
    report_skip "the baseline is still on origin" "$needs"
    report_skip "the baseline is the highest version tag" "$needs"
  elif [[ -n $RESUME_TAG ]]; then
    report info "the next tag is free" "not weighed: a release would resume ${RESUME_TAG}, which writes no tag"
    report info "the baseline is still on origin" "not weighed: a release would resume ${RESUME_TAG}, which computes no version"
    report info "the baseline is the highest version tag" "not weighed: a release would resume ${RESUME_TAG}, which computes no version"
  else
    select_baseline "$TO_REF" "$SINCE_REF"
    scan_commits "$TO_REF"
    if (( ${#COMMITS[@]} == 0 )); then
      report info "the next tag is free" "not weighed: no commit to release in range '${RANGE}', so a release would stop with nothing to release (exit ${EXIT_NOTHING_TO_RELEASE})"
      report info "the baseline is still on origin" "not weighed: no commit to release in range '${RANGE}'"
      report info "the baseline is the highest version tag" "not weighed: no commit to release in range '${RANGE}'"
    else
      classify_commits
      next_version
      report_check fail "the next tag is free" "" check_tag_free
      report_check fail "the baseline is still on origin" "" check_baseline_on_origin
      report_check fail "the baseline is the highest version tag" "" check_baseline_highest
      [[ -z $LEVEL_FROM || -z $FORCE_LEVEL ]] \n        || report_check fail "the branch name forces no level below the commits" "" check_level_not_lowered
    fi
  fi
}

if [[ $CHECK_ONLY == true ]]; then
  run_setup_report
  print_report
  if (( REPORT_FAILURES > 0 )); then
    stop "$EXIT_REFUSED" "${REPORT_FAILURES} check(s) failed: a release would refuse"
  fi
  info "No check a release would refuse on fails."
  exit "$EXIT_OK"
fi

preflight

# A name that maps to no branch is a typo or a stale variable, not a name that
# carries no level, so it is refused whatever it holds. Checked on the local
# branches and on origin's remote-tracking ones, which a CI clone has alone.
if [[ -n $LEVEL_FROM ]]; then
  branch="${LEVEL_FROM#refs/heads/}"
  git show-ref --verify --quiet "refs/heads/${branch}" \
    || git show-ref --verify --quiet "refs/remotes/origin/${branch}" \
    || die "--level-from '${LEVEL_FROM}' is not a branch, locally or on origin"
fi

check_branch || warn "$CHECK_FAILURE"

[[ -n $TO_REF ]] || TO_REF="HEAD"
verify_ref "$TO_REF"

check_tree_clean || warn "$CHECK_FAILURE"

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
resolve_resume "$TO_REF" || die "$CHECK_FAILURE"
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

scan_commits "$TO_REF"
# Its own exit code: a range with nothing in it is the ordinary state of a
# trunk between releases, and CI should not read it as a failure. The wording
# stays as it was, for the consumers still grepping for it.
(( ${#COMMITS[@]} > 0 )) \
  || stop "$EXIT_NOTHING_TO_RELEASE" "no commit to release in range '${RANGE}'"

classify_commits

if [[ $RESUMING == true ]]; then
  NEW_TAG="$RESUME_TAG"
  NEW_VERSION="${NEW_TAG#v}"
  # Nothing left for it to force: the version was decided by the run that wrote
  # the tag. Said out loud rather than dropped, since a caller passing it wants
  # a version this run is not the one to choose.
  [[ -z $FORCE_LEVEL ]] \
    || warn "${FORCE_LEVEL_OPTION} is ignored on a resume: ${NEW_TAG} already carries the version"
else
  next_version
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
  info "Bump            : ${BOLD}${LEVEL}${RESET}${FORCE_LEVEL:+ (forced with ${FORCE_LEVEL_OPTION})}"
  info "Version         : ${CURRENT_VERSION} -> ${BOLD}${GREEN}${NEW_VERSION}${RESET}"

  # A tag on the target with no release never reaches these: that one is a
  # resume, decided above.
  check_tag_free || stop "$EXIT_REFUSED" "$CHECK_FAILURE"
  check_baseline_on_origin || stop "$EXIT_REFUSED" "$CHECK_FAILURE"
  check_baseline_highest || stop "$EXIT_REFUSED" "$CHECK_FAILURE"
  check_level_not_lowered || stop "$EXIT_REFUSED" "$CHECK_FAILURE"
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
    cat "$NOTES_FILE"
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
