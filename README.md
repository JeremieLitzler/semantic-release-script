# semantic-release-script-testing

A bash implementation of semantic release, so a release does not depend on a
tree of npm packages. It reads the conventional commits, decides the version,
writes the notes, tags and publishes — with a human gate before each step.

Requires `git`, `bash` 4+ and the [GitHub CLI](https://cli.github.com/) already
logged in (`gh auth login`).

## Releasing

```bash
./scripts/release/release.sh --dry-run   # see the version and the notes, change nothing
./scripts/release/release.sh             # the real thing, one confirmation per step
```

| Option | Effect |
| --- | --- |
| `-y`, `--yes` | Skip every human gate (unattended run). |
| `-n`, `--dry-run` | Do everything but push the tag and create the release. |
| `-l`, `--local` | Create the tag locally, but neither push it nor publish a release. |
| `--since <ref>` | Read the commits since `<ref>` instead of the last `v*` tag. |
| `--trunk <name>` | The branch releases are cut from, instead of GitHub's default branch. |
| `--level <level>` | Force the bump: `major`, `minor` or `patch`. |
| `--notes <file>` | Also write the release notes to `<file>`. |
| `--changelog <file>` | Prepend the release to `<file>`, newest release on top. |

### The trunk

A release is cut from the **trunk**, and the trunk is whatever GitHub reports as the repository's default branch — `gh repo view` answers for it, so a repository releasing from `develop` needs no change here. A `release/*` branch cut off the trunk is accepted too, and so is a detached `HEAD`, which is how CI checks out a chosen commit. Anything else only warns, it does not stop the release.

`--trunk <name>` names the trunk instead, for a repository whose releases are cut from a branch that is not its default one, or one GitHub reports no default branch for.

### The version

The commits since the last `v*.*.*` tag decide the bump. Merge commits are
ignored.

| The commit range contains | Bump | 1.2.3 becomes |
| --- | --- | --- |
| a `!` before the `:`, or `BREAKING CHANGE` in the body | major | 2.0.0 |
| a `feat` commit | minor | 1.3.0 |
| anything else | patch | 1.2.4 |

When no tag exists yet, the current version is `0.0.0`.

### The first release

With no `v*` tag to start from, the whole history is scanned and the bump is
applied to `0.0.0`, so the first release lands on `0.0.1`, `0.1.0` or `1.0.0`
depending on what the commits contain. Expect the repository's very first
commit to show up under `Others`.

Reaching `1.0.0` therefore only happens on its own if the history holds a
breaking change. To declare the first release stable whatever the commits say,
force it:

```bash
./scripts/release/release.sh --dry-run --level major   # 0.0.0 -> 1.0.0
./scripts/release/release.sh --level major
```

`--level` only overrides the bump. The notes are still built from the real
commits, so a forced `1.0.0` with no breaking change simply has no
`BREAKING CHANGES` section.

Two neighbouring cases:

- **The project already has releases, but not from this script.** Nothing to do
  as long as the existing tags are named `v1.2.3`: the last one is picked up and
  the next version follows from it.
- **The history before a given point is not worth releasing.** Point the script
  at where you want to start with `--since <ref>`. Careful, the version is then
  read from `<ref>` too, so `--since` on something that is not a `v1.2.3` tag
  restarts the count at `0.0.0` — pair it with `--level` when that matters.

### The notes

Four sections, empty ones omitted: `BREAKING CHANGES`, `Features` (`feat`),
`Bug fixes` (`fix`), `Others`.

A commit referencing an issue is listed with the issue title:

```markdown
- Export the orders as CSV (#2)
```

The number is checked against the GitHub API first. A pull request number, or a
number that is not an issue at all, does not qualify: the commit is then listed
with its message and a link to itself.

```markdown
- feat: dark mode for the dashboard ([14de0b0](../../commit/14de0b0))
```

Inside a section, the commits backed by an issue come first, each group ordered
from the newest commit to the oldest.

No `CHANGELOG.md` is written by default: the releases already hold that
history. `--changelog <file>` is there for the times you want to read a whole
series of releases in one file, for instance to review the test runs.

## Testing it

Two [bats](https://github.com/bats-core/bats-core) suites test `release.sh` without touching this repository's history or tracker. bats, bats-support and bats-assert are pinned as git submodules under `tests/libs/`, and [`jq`](https://jqlang.org/) is the only other dev dependency.

```bash
git submodule update --init          # once per clone
tests/libs/bats-core/bin/bats tests/ # the fixture suite; the live suite shows as skipped
```

### The fixture suite

Each test builds a throwaway repository in a temp dir, with a bare repository as its `origin`, and runs `release.sh --yes` with a fake `gh` first on `PATH` (`tests/helpers/fake-gh/gh`). The fake runs the real `--jq` expressions over GitHub-shaped JSON, answers an issue number no test declared like a 404, checks `--verify-tag` against the bare `origin`, and logs every call. Tests declare the GitHub state they need with `given_issue`, `given_pull_request` and `given_default_branch`.

| File | Covers |
| --- | --- |
| `tests/version.bats` | the bump each commit type causes, the baseline, the first release, `--level` |
| `tests/notes.bats` | the notes: sections, issue titles, the pull request and missing number fallbacks, dedupe by issue |
| `tests/replay.bats` | `--since` and `--to` |
| `tests/publish.bats` | the tag and its push, the release, `--dry-run`, `--local` |
| `tests/options.bats` | `--notes`, `--changelog`, `--trunk`, bad arguments, the preflight checks |

The reference dataset (`build_reference_dataset` in `tests/helpers/fixture.bash`) is the readable spec of every notes rule: 21 commits covering features with and without an issue, bug fixes, breaking changes flagged with `!`, `BREAKING CHANGE:` and `BREAKING-CHANGE:`, "BREAKING CHANGE" in prose, the other conventional types, a number that isn't an issue, a pull request number, several commits on one issue, and a merge commit. `tests/golden/reference-notes.md` holds the notes it produces.

Every fixture commit has a fixed author, committer and date, so its hashes are the same on every machine, and the golden files hold them literally. After a deliberate change to the notes or the dataset, regenerate the golden files and review the diff in git:

```bash
UPDATE_GOLDEN=1 tests/libs/bats-core/bin/bats tests/
```

`.github/workflows/test.yml` runs the suite on every pull request to `main` and every push to `main`.

### The live suite

`tests/live.bats` keeps the fake honest: it runs the real `gh`, logged in as you, against the sandbox [`JeremieLitzler/semantic-release-script-tests`](https://github.com/JeremieLitzler/semantic-release-script-tests), and never runs in CI.

```bash
LIVE=1 tests/libs/bats-core/bin/bats tests/live.bats
```

In a fresh clone in a temp dir, it resets the sandbox's `main` to `Initial commit`, pushes the reference dataset, releases `v1.0.0`, and diffs its notes against the reference golden once the repository name and the hashes are normalised. On success it deletes the release and the tag and resets `main`. On failure it leaves them on GitHub for inspection, and the next run's reset clears them.

The sandbox's issues and closed pull request are seeded once by `tests/live/seed-sandbox.sh`. It's idempotent, and it writes `tests/fixtures/reference-issues.env`, the number and title map both suites build their commits from.
