# semantic-release-script-testing

A bash implementation of semantic release, so a release does not depend on a
tree of npm packages. It reads the conventional commits, decides the version,
writes the notes, tags and publishes — with a human gate before each step.

Requires `git`, `bash` 4+ and the [GitHub CLI](https://cli.github.com/) already
logged in (`gh auth login`).

## Releasing

```bash
./release.sh --dry-run   # see the version and the notes, change nothing
./release.sh             # the real thing, one confirmation per step
```

| Option | Effect |
| --- | --- |
| `-y`, `--yes` | Skip every human gate (unattended run). |
| `-n`, `--dry-run` | Do everything but push the tag and create the release. |
| `-l`, `--local` | Create the tag locally, but neither push it nor publish a release. |
| `--since <ref>` | Read the commits since `<ref>` instead of the last `v*` tag. |
| `--level <level>` | Force the bump: `major`, `minor` or `patch`. |
| `--notes <file>` | Also write the release notes to `<file>`. |
| `--changelog <file>` | Prepend the release to `<file>`, newest release on top. |

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
./release.sh --dry-run --level major   # 0.0.0 -> 1.0.0
./release.sh --level major
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

```bash
./tests/create-dummy-issues.sh      # 7 throwaway issues, numbers saved to tests/dummy-issues.env
./tests/generate-dummy-changes.sh   # 14 commits touching DUMMY-COMMITS-TARGET.md
./release.sh --dry-run              # check the result against COMMIT-MESSAGES.md
```

The dataset covers features with and without an issue, bug fixes, a breaking
change flagged with `!` and one flagged in the body, the other conventional
types, and a reference to a number that is not a real issue.
`COMMIT-MESSAGES.md` records what each commit should produce.

To rehearse a series of releases instead of a single one, walk a throwaway
branch through the dataset and release at each stop. Each run picks up the tag
left by the previous one, so the versions chain the way they would in real life:

```bash
git switch -c reltest <commit 7>
./release.sh --local --yes --changelog tests/CHANGELOG.md   # patch -> v0.0.1
git merge --ff-only <commit 12>
./release.sh --local --yes --changelog tests/CHANGELOG.md   # minor -> v0.1.0
git merge --ff-only <commit 14>
./release.sh --local --yes --changelog tests/CHANGELOG.md   # major -> v1.0.0
git switch main && git branch -d reltest
```

`tests/CHANGELOG.md` then holds the three releases, newest on top. Clean up the
rehearsal with `git tag -d v0.0.1 v0.1.0 v1.0.0`.
