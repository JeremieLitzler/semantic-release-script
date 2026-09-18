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

A real run stops at a human gate before each step. A dry run reaches no remote — no tag pushed, no release created — so its gates guard nothing: it runs straight through, and needs no terminal to answer on. That is what lets a CI job preview a release with `--dry-run` alone. The cost is local: a dry run no longer pauses between its steps.

It is the remote a dry run leaves alone, not your disk. `--notes` and `--changelog` write their file under `--dry-run` exactly as they do on a real run, and now with no gate in front of them. `--local` still gates, because it writes a tag to your machine.

| Option | Effect |
| --- | --- |
| `-y`, `--yes` | Skip every human gate (unattended run). |
| `-n`, `--dry-run` | Do everything but push the tag and create the release. Reaches no remote, so every gate is skipped. |
| `-l`, `--local` | Create the tag locally, but neither push it nor publish a release. |
| `--since <ref>` | Read the commits since `<ref>` instead of the last `v*` tag. |
| `--trunk <name>` | The branch releases are cut from, instead of GitHub's default branch. |
| `--level <level>` | Force the bump: `major`, `minor` or `patch`. |
| `--notes <file>` | Also write the release notes to `<file>`. |
| `--changelog <file>` | Prepend the release to `<file>`, newest release on top. |

### Exit codes

The script's contract with whatever runs it. A CI job reads the code rather than grepping the human-readable output.

| Code | Meaning |
| --- | --- |
| `0` | Released, or previewed with `--dry-run` or `--local`. Answering `N` at a gate lands here too: nothing was released, and nothing went wrong. |
| `1` | Error: a bad option, a ref that does not exist, a missing tool, a `gh` that is not logged in, a gate with no terminal to read, a push the remote rejected. |
| `2` | Nothing to release: no commit in the range. The ordinary state of a trunk between releases, not a failure to escalate. |
| `3` | Refused by a guard: the repository's state rules the release out — the computed tag already existing, or a shallow clone whose baseline is unreachable. |

Code `2` still prints `no commit to release in range '<range>'`, so a consumer grepping for that line keeps working until it switches to the code.

The four codes cover the outcomes the script decides on. They are not the only codes it can exit with: `set -e` lets a `git` or `gh` command that fails where nothing guards it surface its own status, `128` from `git` most often. Read any other code as an error, the same as `1`.

### The trunk

A release is cut from the **trunk**, and the trunk is whatever GitHub reports as the repository's default branch — `gh repo view` answers for it, so a repository releasing from `develop` needs no change here. A `release/*` branch cut off the trunk is accepted too, and so is a detached `HEAD`, which is how CI checks out a chosen commit. Anything else only warns, it does not stop the release.

`--trunk <name>` names the trunk instead, for a repository whose releases are cut from a branch that is not its default one, or one GitHub reports no default branch for.

### Shallow clones

A **shallow clone** — `git clone --depth 1`, and the checkout `actions/checkout` hands a job when nobody sets `fetch-depth` — cuts the history off at a fixed depth. Every version tag behind the cut is then unreachable: `git describe` reaches no baseline, the current version falls back to `0.0.0`, and a repository sitting at `v1.2.3` would release `v0.0.1`. Fetching the tags does not repair it, since the tag refs come back but the commits they name stay behind the cut.

So the script refuses to compute a version there, with code `3`, rather than computing a wrong one. Check out the full history instead:

```yaml
- uses: actions/checkout@v7
  with:
    fetch-depth: 0
```

On a shallow checkout you already have, `git fetch --unshallow` fills in the rest.

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
| `tests/exit-codes.bats` | the code each outcome exits on: released, previewed, nothing to release, refused, error |

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
