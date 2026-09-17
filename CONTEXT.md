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
A version tag on a commit the trunk cannot reach, typically left on a retired branch whose commits were rebased onto the trunk under new hashes. It's invisible when the baseline is resolved from the trunk.
_Avoid_: orphan tag, lost tag

**Twin**:
The commit on the trunk that carries the same change as a stranded tag's commit, with a different hash and an identical tree.
_Avoid_: copy, duplicate

**Shallow clone**:
A checkout whose history is cut off at a fixed depth, so version tags older than the cut are unreachable and the baseline can silently fall back to an older tag or to `0.0.0`.
_Avoid_: partial clone (a different git feature)

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
