# Supported setups

Which repository setups `release.sh` releases from, and which it refuses. The rule behind every one of them: a repository has **one trunk**, every version tag sits on a commit the trunk carries, and the baseline is the highest version tag. A setup that keeps that holds; one that breaks it is refused by a guard, exit `3`, having written nothing.

`./scripts/release/release.sh --check` prints the setup report: every check below against the target a release would use, and every result at once. The terms are defined in [CONTEXT.md](../CONTEXT.md).

## Supported

### S1 - Local run on the trunk

You run the script from a checkout of the trunk (or a `release/*` branch cut from it), with a terminal to answer the gates on.

```mermaid
flowchart LR
  A[checkout of the trunk] --> B[release.sh]
  B --> C{gate before each step}
  C -- y --> D[tag pushed, GitHub release created]
  C -- N --> E[exit 0, nothing released]
```

### S2 - Single-trunk CI

A job on the trunk runs `release.sh --yes`, with the full history fetched (`fetch-depth: 0`) and `gh` logged in. `--dry-run` alone previews a release on a runner: it reaches no remote, so it asks nothing.

```mermaid
flowchart LR
  A[push to the trunk] --> B[job: full clone, gh logged in]
  B --> C[release.sh --yes --summary file]
  C --> D{exit code}
  D -- 0 --> E[released, or previewed]
  D -- 2 --> F[nothing to release]
  D -- 3 --> G[refused by a guard]
  D -- 1 --> H[error]
```

### S3 - First release

No version tag exists yet. The baseline is `0.0.0`, so the first release lands on `0.0.1`, `0.1.0` or `1.0.0` depending on the commits, or wherever `--level` forces it. The baseline guards have no tag to weigh.

```mermaid
flowchart LR
  A[no version tag] --> B[baseline 0.0.0]
  B --> C[bump from the commits]
  C --> D[first tag, first release]
```

### S4 - Replay

Cutting past releases that were never tagged, with `--since <ref>` and `--to <ref>`. Oldest first: `--since` older than the latest release is refused, because the baseline would not be the highest version tag.

```mermaid
flowchart LR
  A[--since r0 --to c1] --> B[tag v1.0.0 at c1]
  B --> C[--since v1.0.0 --to c2]
  C --> D[tag v1.1.0 at c2]
  D --> E[newest last]
```

## Unsupported

### U1 - The develop/main rebase dance

Releasing from a branch that is later rebased onto another, so the tag written there ends up on a commit the trunk does not carry: the tag is **stranded**, and its **twin** on the trunk has a different hash. The next baseline resolved from the trunk cannot see the tag, and a release would compute a version at or below one already cut.

```mermaid
flowchart LR
  A[v1.0.0 tagged on develop] --> B[develop rebased onto main]
  B --> C[commits get new hashes]
  C --> D[v1.0.0 stranded, twin on main]
  D --> E[refused: off-trunk or baseline-not-highest]
```

Refused by `off-trunk` when the target is not on the trunk, and by `baseline-not-highest` when a stranded tag sits above the baseline. Fix: find the twin (same tree) and re-point the tag at it.

### U2 - Maintenance lines

A second long-lived branch releasing an older major, such as `v1.2.1` on `1.x` while the trunk is at `v2.0.0`. Unsupported by decision (#13): no project releases an older major, and nothing in the refusal makes supporting one harder later. There is no detection of a line by name; the guards below refuse a release run from one as a side effect.

```mermaid
flowchart LR
  A[trunk at v2.0.0] --- B[1.x line at v1.2.0]
  B --> C[release v1.2.1 from 1.x]
  C --> D{trunk carries the target?}
  D -- no --> E[refused: off-trunk]
  D -- yes, --trunk 1.x --> F{baseline highest?}
  F -- v2.0.0 above v1.2.0 --> G[refused: baseline-not-highest]
```

### U3 - A release ref with extra commits

A `release/*` branch that grew a commit after the tag was cut, or a tag written on a trunk commit nobody pushed. The tag sits on a commit the trunk cannot reach.

```mermaid
flowchart LR
  A[release/1.1 cut from main] --> B[v1.1.0 tagged]
  B --> C[fix committed on release/1.1]
  C --> D[v1.1.0 not reachable from main]
  D --> E[refused: off-trunk, then baseline-not-highest]
```

Fix: push the extra commits to the trunk or rebase them onto it, so the tag is reachable.

### U4 - Environment traps

Setups where the script cannot see the repository whole, so a version computed from what it sees could be wrong. Each is refused rather than guessed at.

```mermaid
flowchart LR
  A[shallow clone] --> X[refused: shallow]
  B[tags not fetchable from origin] --> Y[refused: stale-tags]
  C[baseline tag deleted from origin, or never pushed] --> Z[refused: baseline-gone]
  D[gate with no terminal and no --yes] --> W[error: exit 1]
```

## The decision flow

The order the setup report weighs the checks in, one refusal per node. A failing check withholds what depends on it (`skip`) rather than stopping the report, where a release stops at the first failure.

```mermaid
flowchart TD
  S([start]) --> T{git, gh and bash 4 present?}
  T -- no --> E1[error, exit 1: install the tool]
  T -- yes --> R{inside a git repository?}
  R -- no --> E2[error, exit 1: run it from the checkout]
  R -- yes --> L{gh logged in?}
  L -- no --> E3[error, exit 1: gh auth login]
  L -- yes --> G{GitHub repository resolves, trunk known?}
  G -- no --> E4[error, exit 1: check the remote, or pass --trunk]
  G -- yes --> SH{shallow clone?}
  SH -- yes --> R1[refused: shallow, exit 3]
  SH -- no --> TF{version tags fetched from origin?}
  TF -- no --> R2[refused: stale-tags, exit 3]
  TF -- yes --> TR{trunk reachable on origin?}
  TR -- no --> E5[error, exit 1: name the branch with --trunk]
  TR -- yes --> TC{trunk carries the target?}
  TC -- no --> R3[refused: off-trunk, exit 3]
  TC -- yes --> HP{half-published release on the target?}
  HP -- yes --> RS[resume at step 4: tag and baseline checks not weighed]
  HP -- no --> CR{commit in the range?}
  CR -- no --> N[nothing to release, exit 2]
  CR -- yes --> TG{next tag free?}
  TG -- no --> R4[refused: tag-taken, exit 3]
  TG -- yes --> BO{baseline still on origin?}
  BO -- no --> R5[refused: baseline-gone, exit 3]
  BO -- yes --> BH{baseline the highest version tag?}
  BH -- no --> R6[refused: baseline-not-highest, exit 3]
  BH -- yes --> OK([a release would go ahead])
```

On a release the guards that do not need the version (shallow, stale tags, off-trunk) run before it is computed; the last three are weighed on the version it would compute. Under `--dry-run` the off-trunk guard warns instead of refusing, since no tag is written.
