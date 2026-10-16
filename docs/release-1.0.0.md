# v1.0.0

The first stable release of `release.sh`. The notes of the release list the commits; this page tells what they add up to.

## What this major means

Until now `release.sh` was a script that worked. From v1.0.0 it is a contract: the flags, the exit codes and the `--summary` keys below do not change without a major, and a consumer that vendors the script can pin it and rely on them.

- **Exit codes**: `0` released or previewed, `1` error, `2` nothing to release, `3` refused by a guard.
- **The refusals**: a run that a guard refuses exits `3` having written nothing.
- **One trunk**: a repository has one trunk, every version tag sits on a commit the trunk carries, and the baseline is the highest version tag. What that covers, and what it does not, is in [supported-setups.md](supported-setups.md). Maintenance lines are not supported.

v1.0.0 is cut from `release/major/<id>` with `--level-from`, so the major is forced whatever the commits say. No commit declares a breaking change; the break is the move from "works" to "promised", and the changes below are the ones a v0.1.0 user can feel.

## What breaks, and what to change

If you ran a 0.x script, check these.

- **The trunk is GitHub's default branch, not `main`.** A repository whose default branch is not `main` now releases from it. Pass `--trunk <name>` to keep another branch.
- **A dry run skips every human gate.** `--dry-run` reaches no remote, so its gates guarded nothing and are gone. A CI job previews with `--dry-run` alone; a script that piped answers into a dry run can drop them.
- **A gate that cannot read a terminal fails with `1`.** It used to read the missing answer as a decline and exit `0` having released nothing. In CI, pass `--yes`.
- **Exit `2` means nothing to release.** A job that treated every non-zero code as a failure must now tell `2` apart.
- **A release can be refused (`3`)** where it used to go through: a shallow clone, a failed tag fetch, a ref the trunk does not contain, a baseline that is not the highest version tag, a baseline tag that origin no longer holds. Each refusal says why and what to fix; `--check` lists them all at once.
- **`--changelog` writes the release notes** under each version heading. It used to write the headings alone.
- **The history of `main` was rewritten** to drop the dummy commits. A clone older than that must be re-synced; the old-to-new hashes are in [history-rewrite-hash-map.md](history-rewrite-hash-map.md).

## The new things, by theme

**Deciding the version**
- `--level-from <ref>` forces the bump from the branch name: `release/major/<id>`, `release/minor/<id>`, `release/patch/<id>`. A level below what the commits imply is refused with `3`; forcing up is allowed.
- `--since` resolves the current version when it is not a tag, and the notes dedupe by issue, keeping the most significant category.
- Historical ranges can be replayed to rebuild past releases.

**Refusing a bad release**
- Guards for a shallow clone, a failed tag fetch, an unreachable ref, a baseline that is not the highest tag, and a baseline origin no longer holds.

**Knowing where you stand**
- `--check` prints the setup report: every check and guard against the target a release would use, with the reason and the fix.
- `--summary <file>` writes what the run decided as `key=value` lines, so a CI job reads the version off a file.

**Recovering**
- A half-published release (a tag on origin, no GitHub release) is resumed at step 4 instead of computing a new version.

**Running in CI**
- This repository cuts its own releases from `.github/workflows/release.yml`, pinned to a commit of `release.sh`.
- The bats suite runs on fixture-built repositories, and the `gh` it calls is a fake.
- A promotion website, <https://semver-script.madebyjeremie.fr>, documents the options.

## The range

[Compare v0.5.0...v1.0.0](https://github.com/JeremieLitzler/semantic-release-script/compare/v0.5.0...v1.0.0)

The full history from the first release: [v0.1.0...v1.0.0](https://github.com/JeremieLitzler/semantic-release-script/compare/v0.1.0...v1.0.0).
