# semantic-release-script

A bash script that turns the conventional commits since the last release into the next version, its release notes, a tag and a GitHub release. Other repos vendor it to run their releases.

## Language

### Versions and releases

**Version tag**:
A git tag named `vMAJOR.MINOR.PATCH` that marks the commit a release was cut from. Tags with any other name are not version tags.
_Avoid_: release tag, semver tag

**Release**:
A version tag together with the GitHub release that carries its notes.
_Avoid_: publish, version (when the tag plus notes is meant)

**Baseline**:
The version tag the next version is computed from: the nearest version tag reachable from the commit being released, or `0.0.0` when there is none.
_Avoid_: last tag, current version, previous release

**Bump**:
The step from the baseline to the next version: major, minor or patch, decided by the commits in the range.
_Avoid_: increment, level (except when naming the `--level` option)

**Non-monotonic version**:
A computed next version that is not higher than every version tag already in the repository. On a single trunk it can only come from a baseline older than the latest release.
_Avoid_: version regression, downgrade

### Branch topology

**Trunk**:
The one long-lived branch of a repository that releases are cut from, read from GitHub's default branch unless `--trunk` names another. Every version tag should sit on a commit the trunk carries.
_Avoid_: main branch, default branch (they usually coincide, but the trunk is the role)

**Stranded tag**:
A version tag on a commit the trunk cannot reach: left on a retired branch whose commits were rebased onto the trunk under new hashes, written on a `release/*` branch that grew a commit after it was cut, or written on a trunk commit nobody pushed. It's invisible when the baseline is resolved from the trunk.
_Avoid_: orphan tag, lost tag

**Twin**:
The commit on the trunk that carries the same change as a stranded tag's commit, with a different hash and an identical tree.
_Avoid_: copy, duplicate

**Shallow clone**:
A checkout whose history is cut off at a fixed depth, so version tags older than the cut are unreachable and the baseline can silently fall back to an older tag or to `0.0.0`.
_Avoid_: partial clone (a different git feature)

**Stale tags**:
A local tag set origin has moved past, left behind when fetching the tags fails. The baseline read from it can be older than the last release, so the next version computed from it is non-monotonic.
_Avoid_: outdated tags, out-of-sync tags

### Outcomes

**Gate**:
A stop before a step that only the human can lift: the script asks, and goes no further until it is answered. Unlike a guard it weighs nothing — `--yes` answers every gate in advance, `--dry-run` asks none, and declining one ends the run at `0` with nothing released, what the steps before it wrote left standing.
_Avoid_: prompt, confirmation, checkpoint

**Guard**:
A check that stops a release over the repository's state rather than over the command line — the computed tag already existing, for instance. It refuses, it does not fail. A guard over where the tag lands has nothing to stop under `--dry-run`, which writes no tag: there it warns instead of refusing.
_Avoid_: validation, safety check

**Refusal**:
A guard stopping a release: the script says why and exits `3`, having written nothing. A mistake in the command line is not one, and exits `1`.
_Avoid_: rejection, abort, error (an error is the other outcome)

**Nothing to release**:
A commit range holding no commit, so there is no version to compute. The ordinary state of a trunk between releases, not a refusal and not an error: it exits `2` of its own.
_Avoid_: empty range, no changes, up to date

**Preview**:
A run that writes nothing to the remote — no tag pushed, no release created — though it still reads from it: `--dry-run`, which writes nothing beyond the files `--notes` and `--changelog` name, or `--local`, which also writes the version tag to the machine. It exits `0`, as a release does.
_Avoid_: trial run, simulation, test run

### Usage

**Replay**:
Rebuilding a series of past releases oldest first, each one over an explicit commit range.
_Avoid_: backfill, rebuild

**Consumer**:
A repository that runs its releases with a vendored copy of the script.
_Avoid_: client, downstream repo

**Vendored copy**:
The script as committed inside a consumer, pinned to an upstream commit and synced only on purpose.
_Avoid_: fork, submodule
