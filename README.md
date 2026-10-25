# semantic-release-script

A bash implementation of semantic release, so a release does not depend on a
tree of npm packages. It reads the conventional commits, decides the version,
writes the notes, tags and publishes — with a human gate before each step.

Requires `git`, `bash` 4+ and the [GitHub CLI](https://cli.github.com/). Run locally, `gh` must
already be logged in (`gh auth login`); in CI, a `GH_TOKEN` in the environment stands in for the login.

## Releasing

```bash
./scripts/release/release.sh --dry-run   # see the version and the notes, change nothing
./scripts/release/release.sh             # the real thing, one gate per step
```

A real run stops at a human gate before each step. A dry run reaches no remote — no tag pushed, no release created — so its gates guard nothing: it runs straight through, and needs no terminal to answer on. That is what lets a CI job preview a release with `--dry-run` alone. The cost is local: a dry run no longer pauses between its steps.

A real run needs a terminal to answer on, or `--yes` in place of one. A runner has neither: there `/dev/tty` is still a device node, but nothing opens it, so the run stops at the first gate and exits `1` telling you to pass `--yes` — rather than reading the answer it could not get as a decline and going green having released nothing.

It is the remote a dry run leaves alone, not your disk. `--notes`, `--changelog` and `--summary` write their file under `--dry-run` exactly as they do on a real run, and now with no gate in front of them. `--local` still gates, because it writes a tag to your machine.

| Option | Effect |
| --- | --- |
| `-y`, `--yes` | Skip every human gate (unattended run). |
| `-n`, `--dry-run` | Do everything but push the tag and create the release. Reaches no remote, so every gate is skipped. |
| `-l`, `--local` | Create the tag locally, but neither push it nor publish a release. |
| `--since <ref>` | Read the commits since `<ref>` instead of the last `v*` tag. |
| `--trunk <name>` | The branch releases are cut from, instead of GitHub's default branch. |
| `--level <level>` | Force the bump: `major`, `minor` or `patch`. |
| `--level-from <ref>` | Force the bump from a branch name: the segment right after `release/` in `release/major/<id>`, `release/minor/<id>` or `release/patch/<id>`, or the bare `release/major`, `release/minor` or `release/patch`. A name with no level there changes nothing. A level below what the commits imply (`release/patch/<id>` over a `feat`) is refused with `3`; forcing up is allowed. The value must be a branch, locally or on origin, or the run errors. Not with `--level`, which is never refused for being lower. |
| `--notes <file>` | Also write the release notes to `<file>`. |
| `--changelog <file>` | Prepend the release to `<file>`, newest release on top. |
| `--summary <file>` | Write what the run decided to `<file>`, as `key=value` lines. |
| `--check` | Print the setup report instead of releasing. Takes only `--trunk`, `--to`, `--since` and `--level-from`. |

### Cutting a release

`.github/workflows/release.yml` cuts this repository's own releases.

- **Preview**: a push to `main`, or a manual dispatch left on `preview`, dry-runs the release and writes the pending version and notes to the job summary. Nothing is written.
- **Publish**: push a `release/*` branch cut from `main`, or dispatch the workflow with `publish` from `main` or a `release/*` branch. The tag and the GitHub release are created, and a push-triggered run then deletes the `release/*` branch.

Publish refuses a `release/*` ref that `main` does not contain, and does not start until the bats suite is green for that commit.

The workflow runs `release.sh` fetched at the commit named by `RELEASE_SCRIPT_REF` at the top of the file, not the copy on the commit being released. It points at the commit the `v1.0.1` tag targets, named in a comment above it, until the next pin move. To move the pin, set `RELEASE_SCRIPT_REF` to the SHA of the commit to run (for a version tag, `git rev-parse 'vX.Y.Z^{commit}'`) and update the comment to name it, then merge that change: the next push to `main` previews with it.

The "Fetch the pinned release.sh" step (a `curl` of the file at `RELEASE_SCRIPT_REF`, then `chmod +x`) appears in both the `preview` and the `publish` job, and that is intended, not an oversight for consumers to factor out. The two jobs never run in the same workflow run, so each run downloads the script once; the SHA is declared once, in `RELEASE_SCRIPT_REF`, so a pin move touches one line. No composite action or reusable workflow is published from this repository: it would carry a second ref to pin, and the step is two commands. A consumer copying the workflow keeps both steps. See [ADR 0002](docs/adr/0002-the-release-sh-download-is-repeated-in-each-job.md).

Both jobs pass the ref name to `--level-from`, so a push to `release/major/<id>` publishes a major, and a preview dispatched from that branch shows the forced version. A push or dispatch from `main` forces no level.

#### Forcing the level from the branch name

The segment right after `release/` can force the bump, so CI can cut a release the commits alone would not.

| Branch | Effect |
| --- | --- |
| `release/major/<id>`, `release/major` | Forces a major. |
| `release/minor/<id>`, `release/minor` | Forces a minor. |
| `release/patch/<id>`, `release/patch` | Forces a patch. |
| `release/20261015.1`, `main`, `release/hotfix-login` | No level: the commits decide, as before. |
| `release/mayor/x`, `release/Major/x`, `release/major-x/y` | Near-misses: no level either, and not refused. Only the three lowercase values count. |

The contract is `release.sh`'s own (`--level-from`), so a consumer vendoring the script gets the same one. It ends in these outcomes:

- **Exit `3`**: the name forces a level below what the commits imply, `release/patch/<id>` over a `feat` for instance. Forcing up is allowed. `--level` is never refused for being lower. This holds in a real run, `--dry-run`, `--local` and `--check`.
- **Exit `1`**: the value is not an existing branch (locally or on origin) or is empty, or `--level` is given with `--level-from`.
- **Exit `2`**: a forced level over a range with no commit is still "nothing to release".
- **A resume**: `--level-from` is ignored with a warning, like `--level`.

There is no dispatch input: only the branch name carries the level, and a dispatch from a `release/major/...` ref honours its name.

**A patch-only release** is `release/patch/<id>` cut from `main`. The refusal above holds it to patch-only commits. A fix from an older tag is not supported (see the maintenance line in [docs/supported-setups.md](docs/supported-setups.md)).

**The first major (v1.0.0, from v0.4.0)** is cut without an intermediate v0.5.0:

1. Merge the work to `main`, with `docs/release-1.0.0.md` written (see below).
2. Move `RELEASE_SCRIPT_REF` to a commit that carries `--level-from`, as described above.
3. Push `release/major/<id>` from `main`.

A forced level never changes the commit range. The range is still the baseline to the release commit, so the notes of a forced major can be thin: the v1.0.0 notes carry what the commits hold (a `feat` under `Features`, the `ci:` commits under `Others`) and no `BREAKING CHANGES` section when none is declared. That is what the summary below is for.

**The summary of a major** is a hand-written `docs/release-<version>.md` (`release-1.0.0.md` first), a convention for every major, not enforced by the script and not a copy of the release notes. Write and merge it before pushing the `release/major/<id>` branch; its `docs:` commit lands under `Others` and does not change the forced major. Nothing links the GitHub release to it: link it from here, or add a line to the release by hand. A suggested outline, with no template file:

1. What the major means.
2. What breaks, and what to change.
3. The new things, by theme.
4. A link to the range (`compare/vPREVIOUS...vNEXT`).

The first one is [docs/release-1.0.0.md](docs/release-1.0.0.md).

#### Troubleshooting the workflow

- **A preview dispatched from a tag fails with `--level-from '<tag>' is not a branch, locally or on origin`.** The workflow passes the ref name to `--level-from`, which accepts a branch only. Dispatch the preview from `main` or from a `release/*` branch. This comes from the script's check; it has not been reproduced on a runner.

### Checking your setup

```bash
./scripts/release/release.sh --check     # would a release refuse right now, and why?
```

`--check` runs every check of the preflight and every guard against the target a release would use, and prints them all as a setup report: each result, with its reason and the fix. A release stops at the first failure; the report lists them all, so you see what stands between you and a release at once — after vendoring the script, or after a refusal.

```text
ok    gh installed
FAIL  gh is logged in
        gh is not logged in — run: gh auth login
skip  the GitHub repository resolves
        needs gh logged in
warn  on the trunk or a release branch
        you are on 'some-feature', not 'main' or a 'release/*' branch
```

A check is `ok`, a `warn` (a release goes ahead and warns), a `FAIL` (a release would refuse or stop), a `skip` (a failing check withheld what it needs) or an `info`. A half-published release on the target is an `info`: a state the next run finishes, not a failure. The report weighs each guard of a release against the target, after the same fetch: not a shallow clone, the version tags fetched, the trunk carrying the target (the stranded tag), the next tag free, the baseline tag still held by `origin`, and the baseline being the highest version tag already there, listing the stranded tags it finds. The last two are weighed on the version a release would compute, without printing it; they are `info` where there is no version to weigh (a resume, or no commit in the range) and `skip` where the clone or the tags are not whole.

The setups it holds to and the ones it refuses, with the decision flow the report follows, are mapped in [docs/supported-setups.md](docs/supported-setups.md).

It accepts only the options that name the target, `--trunk`, `--to` and `--since`, and `--level-from`, which adds the check that a name-forced level is not below the commits', and exits `1` on any other, so nobody assumes `--notes` wrote a file. It decides no version and writes no file or summary. It runs the same `git fetch --tags origin` a release does, so the only thing it writes is local tag refs. It exits `0` when no check a release would refuse on fails (warnings allowed), `3` when one does, and `1` when it cannot run at all: a bad option, a ref that does not exist, no `git` or `gh` to evaluate with. A `gh` that is not logged in is a failing check, so `3`.

### Exit codes

The script's contract with whatever runs it. A CI job reads the code rather than grepping the human-readable output.

| Code | Meaning |
| --- | --- |
| `0` | Released, or previewed with `--dry-run` or `--local`. Answering `N` at a gate lands here too: nothing was released, and nothing went wrong. With `--check`: no check a release would refuse on failed. |
| `1` | Error: a bad option, a ref that does not exist, a missing tool, a `gh` that is not logged in, a gate with no terminal to read, a push the remote rejected. |
| `2` | Nothing to release: no commit in the range. The ordinary state of a trunk between releases, not a failure to escalate. |
| `3` | Refused by a guard: the repository's state rules the release out — the computed tag already existing, a shallow clone whose baseline is unreachable, tags that could not be fetched from `origin`, a target commit the trunk does not contain, a baseline version tag that `origin` does not hold (deleted there, or a `--local` tag never pushed), or a baseline that is not the highest version tag already there (a stranded tag above it, or a `--since` older than the latest release), or a level forced by the `--level-from` branch name that is below the one the commits imply. With `--check`: a check a release would refuse on failed. |

Code `2` still prints `no commit to release in range '<range>'`, so a consumer grepping for that line keeps working until it switches to the code.

The four codes cover the outcomes the script decides on. They are not the only codes it can exit with: `set -e` lets a `git` or `gh` command that fails where nothing guards it surface its own status, `128` from `git` most often. Read any other code as an error, the same as `1`.

### The release summary

The exit code says how a run ended; `--summary <file>` says what it decided, so a CI job reads the version off a file instead of grepping output meant for a human, or parsing the notes.

```
tag=v1.1.0
version=1.1.0
bump=minor
baseline=1.0.0
released=yes
```

| Key | Value |
| --- | --- |
| `tag` | The version tag of the release: `v1.1.0`. |
| `version` | The same without the `v`: `1.1.0`. |
| `bump` | The step from `baseline` to `version`: `major`, `minor` or `patch`. `none` on a resume, where the version was read off the tag rather than computed. |
| `baseline` | The version the bump was applied to: `1.0.0`, and `0.0.0` on a first release. Always a version, never a ref, whatever `--since` names. |
| `released` | `yes` when the GitHub release was created, `no` otherwise — a preview with `--dry-run` or `--local`, or a gate a human declined. |

Bare `key=value` lines, unquoted, one per line: every value is a tag, a version, a bump name or `yes`/`no`, so the file reads as it stands, whether you source it into a shell or append it to `$GITHUB_OUTPUT`. Append it — the script writes its own file whole, and pointing `--summary` straight at `$GITHUB_OUTPUT` would wipe whatever the step had already written there.

```yaml
- id: release
  run: |
    ./scripts/release/release.sh --yes --summary "$RUNNER_TEMP/release.env"
    cat "$RUNNER_TEMP/release.env" >>"$GITHUB_OUTPUT"
- if: steps.release.outputs.released == 'yes'
  run: echo "published ${{ steps.release.outputs.tag }}"
```

A run writes the file once it has a version and nothing left that could change it, so every line of the file is final. A run that decided no version writes nothing at all: nothing to release (`2`), a guard's refusal (`3`) and an error (`1`) leave the path alone — including a file a previous run wrote there, which is left exactly as it was rather than cleared. So read the exit code first and the file second: a summary only answers for the run that wrote it.

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

### Tags that can't be fetched

The version is computed from the tags, so the script fetches them from `origin` before it reads a baseline. When that fetch fails — a lost network, a remote that moved, an access that was revoked — the local tags stay as they were, and `origin` may well hold releases they know nothing about. A baseline read from them is then older than the last release, and the version computed from it lands on or below a version already published.

So the script refuses there too, with code `3`, naming the remote and repeating what `git` itself said, since the reasons want different fixes:

```
! [rejected] v1.2.3     -> v1.2.3  (would clobber existing tag)
x could not fetch the version tags from 'origin': the local tags may be stale, and the baseline read from them older than the last release — git's own reason is above: make 'origin' reachable, or let its tags win with git fetch --tags --force origin
```

That second reason is the one worth knowing about: a tag that exists both locally and on `origin`, pointing at different commits, makes `git fetch --tags` reject that ref rather than overwrite it — and the fetch fails with `origin` perfectly reachable. The tags really are out of sync, so the refusal is right, but no amount of network fixes it. `git fetch --tags --force origin` lets `origin`'s tags win, which is what you want when `origin` is where the releases live.

No flag escapes it. `--local` writes a real version tag to your machine — the one you push by hand afterwards — so a wrong version there is only a wrong version that arrives more slowly. And `--dry-run` exists to preview the version a real run would cut: a preview computed from tags a real run would refuse is worth less than no preview at all. Being offline never reaches this guard anyway, since the preflight `gh auth status` and `gh repo view` both call the API first and fail with code `1`.

### Tagging off the trunk

The tag has to land on a commit the trunk carries. One that does not is stranded the moment it is written: the next release resolves its baseline from the trunk, `git describe` never reaches this tag, and the version count quietly restarts from an older release.

Two ways in. A `release/*` branch cut off the trunk and then given one more commit — a version bump, a release note, a hotfix — puts the tag on a commit the trunk has never seen. And a trunk holding commits nobody pushed does the same from the other end: `git push origin v1.2.4` sends the tag and the objects it reaches, but it does not move `refs/heads/main` on `origin`.

So the script checks the target against the trunk before it computes anything, and refuses with code `3`:

```
x origin/main does not contain HEAD (a1b2c3d): the tag would sit on a commit the trunk cannot reach, where the next release's baseline can't see it — push those commits to main or rebase them onto it, and check --trunk when main is not the branch releases are cut from
```

That last clause is the one to read twice. The trunk defaults to GitHub's default branch, so a repository that cuts its releases from a branch that is **not** its default one gets the check pointed at the wrong branch, and the refusal is right about the drift but wrong about the fix. `--trunk <name>` is what puts it back.

It is the trunk **`origin` holds** that answers, fetched at the time of the check, never the local branch. A CI job that checks a `release/*` ref out has no local trunk at all, and a stale local one would wave through exactly the commit the guard exists to catch. A consumer whose workflow already runs this check in YAML can drop it.

`--dry-run` is the one flag that gets past it, and the only guard it gets past. The two above are about the version being **wrong**, so previewing one is worse than previewing nothing; this one is about where the tag **lands**, and a dry run writes no tag to strand. It also has to bend: previewing a pull request's release means running on the PR head, which the trunk does not contain and will not until it merges. So the preview happens, with the refusal a real run would raise reported as a warning:

```
! origin/main does not contain HEAD (a1b2c3d): a real run would refuse to tag there
```

`--local` does not get past it. It writes a real version tag to your machine, the one you push by hand afterwards, so a stranded tag there is only a stranded tag that arrives more slowly.

The trunk has to exist on `origin` for any of this to be answerable. One that does not is a name you got wrong rather than a state the repository is in, so it is an error with code `1`, the same as any other ref that does not exist — `origin` is known reachable by then, since the tags were just fetched from it. `git`'s own reason comes with it:

```
fatal: couldn't find remote ref develop
x cannot fetch the trunk 'develop' from origin: git's own reason is above — name the branch releases are cut from with --trunk <name>
```

### A baseline that is not the latest release

The next version is computed from the baseline, so it is only above every release already cut when the baseline is the highest version tag in the repository. One that is not — a stranded tag above it, which the trunk cannot reach and so `git describe` never finds, or a `--since` older than the latest release — is refused with code `3` before any tag is written, even when the version it would compute collides with no tag:

```
x the baseline v0.29.0 is not the highest version tag in the repository, v0.30.1: the next version would not be above every release already cut — above it, v0.30.1 (a1b2c3d) sit on commits the target cannot reach (stranded tags). Find each one's twin, the trunk commit with the same tree: git rev-parse <tag>^{tree} against git log --format='%h %T'
```

Only the tags above the baseline are listed. A name that is not `vMAJOR.MINOR.PATCH`, a prerelease such as `v1.0.0-rc1` included, is no version tag and takes no part in it.

It is also what refuses a release cut from a maintenance line, which the script does not support: the highest version tag is on the trunk, above the line's baseline. `--since` is held to the same rule, so a replay has to go oldest first.

A baseline version tag deleted on `origin` is refused too, with code `3`: `git fetch --tags` only adds, so the local copy survives the fetch, and the commits of the unpublished release would drop out of the next notes. Restore the tag on `origin`, or delete the local one if the release was withdrawn. `--prune-tags` is not the way: it does nothing without `--prune`, and with it also deletes the local-only tag `--local` creates.

### Resuming a half-published release

Step 3 pushes the tag and step 4 creates the GitHub release. A run that dies between the two — a cancelled job, a runner that went away, a `gh` call that failed — leaves a **half-published release**: the version tag is on `origin`, and nothing carries its notes.

Re-running used to dead-end there. The tag sits on the very commit the run was releasing, so the next run resolves it as its own baseline, finds a range with no commit in it, and reports code `2`, "nothing to release" — over a release that never happened. The release never appears on its own, and consumers worked around it in YAML, by deleting the tag from `origin` so the next run could re-cut it.

So the script looks for one on the target before it computes a version — a version tag on the target's commit, that `origin` holds, and that GitHub carries no release for — and resumes it:

```
v1.1.0 is on origin with no GitHub release: resuming it at step 4 rather than computing a new version.

== Step 1 — resume the half-published v1.1.0 ==
...
Version         : 1.1.0 (read off v1.1.0, which origin already holds)
```

The version is read off the tag, not computed, so `--level` has nothing left to force and says so. The notes are rebuilt over the range the tag was cut on — the nearest version tag behind it, or `--since` when you name one — so they come back the same as the run that died would have published. Step 3 creates nothing, and has no gate in front of it: a gate holds back a step that writes, and the only write left is step 4's release, which keeps its own.

Three states look alike from the outside, and only the middle one resumes:

| The tag on the target | What happens |
| --- | --- |
| On `origin`, with its GitHub release | The release is finished: the range behind it holds no commit, so code `2`, nothing to release. |
| On `origin`, with no GitHub release | Half published: resumed at step 4. |
| On this machine only | Never pushed, so what it is waiting for is step 3, not step 4. Left alone — push it, or delete it and let the next run re-cut it. |

Every guard still applies, the containment one included, and it runs before the resume is even recognised as one. The tag it would publish is written already, so the guard undoes nothing there — but a release on a stranded tag is one more thing to unpick once the topology is put right, and the fix the refusal names is the same either way.

**The guarantee, and the workaround it retires.** A tag on the target that `origin` holds and GitHub has no release for is finished by the next run, with the same tag and the same notes. A workflow step that deletes such a tag before `release.sh` runs is not needed, and is harmful: it removes the tag the script would resume, so the run re-cuts it instead, with a new tag object and, if commits landed in between, possibly another version. Delete the step. The one window the script does not close is the one below, and the step never closed it either: it only looked at tags on `HEAD`.

A resume is scoped to the **target**. Commits pushed on top of a half-published tag move `HEAD` past it, and a plain re-run then tags and releases the next version, leaving the older tag without a release for good. `--to <the tag>` resumes it.

`--dry-run` previews the resume and publishes nothing:

```
[dry-run] v1.1.0 is already on origin: a real run would publish its release
```

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

Two [bats](https://github.com/bats-core/bats-core) suites test `release.sh` without touching this repository's history or tracker. bats, bats-support and bats-assert are pinned as git submodules under `tests/libs/`, and [`jq`](https://jqlang.org/) and [`node`](https://nodejs.org/) (for the website's version-fill script, `tests/website.bats`) are the only other dev dependencies.

```bash
git submodule update --init          # once per clone
tests/libs/bats-core/bin/bats tests/ # the fixture suite; the live suite shows as skipped
```

### The fixture suite

Each test builds a throwaway repository in a temp dir, with a bare repository as its `origin`, and runs `release.sh --yes` with a fake `gh` first on `PATH` (`tests/helpers/fake-gh/gh`). The fake runs the real `--jq` expressions over GitHub-shaped JSON, answers an issue number no test declared like a 404, checks `--verify-tag` against the bare `origin`, exits `1` from `release view` for a tag no release was created for, and logs every call. Tests declare the GitHub state they need with `given_issue`, `given_pull_request`, `given_release` and `given_default_branch`.

| File | Covers |
| --- | --- |
| `tests/version.bats` | the bump each commit type causes, the baseline, the first release, `--level`, `--level-from` |
| `tests/notes.bats` | the notes: sections, issue titles, the pull request and missing number fallbacks, dedupe by issue |
| `tests/replay.bats` | `--since` and `--to` |
| `tests/publish.bats` | the tag and its push, the release, `--dry-run`, `--local` |
| `tests/resume.bats` | resuming a half-published release: what is detected, what is left alone, what a resume writes |
| `tests/options.bats` | `--notes`, `--changelog`, `--trunk`, the trunk containment guard, bad arguments, the preflight checks |
| `tests/exit-codes.bats` | the code each outcome exits on: released, previewed, nothing to release, refused, error |
| `tests/check.bats` | `--check`: the setup report, its golden files, what it lists, skips and refuses |
| `tests/summary.bats` | `--summary`: the keys, their values on each outcome, and the runs that write no file at all |

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
