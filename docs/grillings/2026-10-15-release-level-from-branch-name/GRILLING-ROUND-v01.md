# Grilling round v01 — control the release level from the release/\* branch name

Issue: JeremieLitzler/semantic-release-script#77.

Facts found in the repo, so you do not have to look them up:

- `release.sh` already has `--level <major|minor|patch>`. A bad value is a command-line mistake and exits `1` ("--level must be one of: major, minor, patch"). On a resume it is ignored with a warning.
- The workflow's publish job runs `release.sh --yes --summary ...` with no `--level`. It is triggered by a push to `release/**` or a dispatch with `publish`, and `release.sh` is fetched from the SHA pinned in `RELEASE_SCRIPT_REF` (currently v0.4.0).
- An empty commit range exits `2` ("nothing to release") before any version is computed, so `--level` cannot force a version over a range with no commit today.
- `next_version` applies `FORCE_LEVEL` over whatever the commits imply, in both directions: `--level patch` over a `feat!` commit yields a patch.
- The README documents `--level` under "Cutting the first release" and "Cutting a release" documents the `release/*` trigger. There is no `docs/adr/` yet.

## Q1 - Naming: where the level sits in the branch name

Existing branches are date-based (`release/20261015.1`). Where does the level go?

- A. A path segment: `release/major/20261015.1`, `release/minor/20261015.1`, `release/patch/20261015.1`. The workflow's `release/**` trigger already matches it.
- B. A prefix on the leaf: `release/major-20261015.1`.
- C. A suffix on the leaf: `release/20261015.1-major`.
- D. Something else (say what).

➡️ Recommendation: A. A segment is unambiguous to parse (the second path component is either exactly `major`, `minor` or `patch`, or it is not a level), it cannot collide with a date-based leaf, and it reads as "the kind of release" in the branch list. Accepted values are exactly `major`, `minor`, `patch`, lowercase. B and C need a regex over the leaf and make `release/major-fix-readme` ambiguous.

### Answer to Q1

A is what I had in mind

---

## Q2 - Where the branch name is parsed

- A. In the workflow (YAML): it reads `GITHUB_REF_NAME`, derives the level and passes `--level`. `release.sh` is untouched, and the contract ships with one commit to the workflow.
- B. In `release.sh`: a new option takes the branch name (for instance `--level-from <ref>`), and every consumer vendoring the script gets the same contract. The workflow just passes `GITHUB_REF_NAME`.
- C. Both: `release.sh` owns the parsing, the workflow passes the name.

➡️ Recommendation: B. The bats suite only exercises `release.sh`, so only B lets each refusal (Q1 and the unrecognised-level question to come) be pinned by a test; YAML parsing would be untested. The cost is real and you should weigh it: because the workflow runs the pinned script, v1.0.0 would need two steps: release v0.5.0 with the option, move `RELEASE_SCRIPT_REF` to it, then push `release/major/...`. With A, v1.0.0 can be cut in one PR from today's v0.4.0 pin.

### Answer to Q2

B is a good Recommendation

---

## Q3 - Dispatch

A manual `publish` dispatch from `main` has no `release/*` name to read. Which of these?

- A. Only the branch name carries the level. A dispatch from `main` keeps today's behaviour (bump decided by the commits); a dispatch run from a `release/major/...` branch honours its name, as it is the same ref.
- B. Add a `level` input (`auto`, `major`, `minor`, `patch`) to the dispatch as a second way in.

➡️ Recommendation: A. The issue states you prefer the branch name over a dispatch input, one way in means one contract to document and test, and cutting a first major is a matter of pushing `release/major/<id>`, so no dispatch is needed for it.

### Answer to Q3

A

---

## Q4 - Forcing a level over a range with no commit

With a forced level and a commit range holding no commit (for example `release/major/20261015.2` cut right after a release), what happens?

- A. Unchanged: `release.sh` exits `2` "nothing to release". The level never forces a release into existence.
- B. The forced level wins: a release is cut with an empty range and empty notes.

➡️ Recommendation: A. A major bump over zero commits publishes a version with no notes and nothing in it, which is a mistake rather than an intention. It also keeps the exit-code contract (`2` of its own) and the workflow's existing "Nothing to release" handling working for these branches, and the `release/*` branch is then not deleted, which lets you fix it.

### Answer to Q4

A

---

## Q5 - A forced level lower than the commits imply

`--level` today can lower the bump: `release/patch/...` over a range holding a `feat!` commit would publish a patch. Under the branch-name contract, what should happen?

- A. Allowed, as `--level` is today: the branch name is the maintainer's explicit decision, and the notes still show the `BREAKING CHANGES` section.
- B. Refused (exit `3`) when the name forces a level below what the commits imply; forcing up is allowed.
- C. Allowed, but with a warning in the log and the release summary.

➡️ Recommendation: B for the branch-name path only. A breaking change shipped as a patch is the one outcome semver consumers cannot recover from, and the branch name is easy to get wrong by one word; a refusal is cheap to fix by renaming the branch. Forcing up (the v1.0.0 case) stays allowed. Note this makes the name-derived level stricter than the explicit `--level` flag, which would stay as it is.

### Answer to Q5

B
