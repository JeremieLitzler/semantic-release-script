# Grilling round v02 — control the release level from the release/\* branch name

## Settled in v01

- Q1: the level is a path segment, `release/<level>/<id>` (for example `release/major/20261015.1`). Accepted values are exactly `major`, `minor`, `patch`.
- Q2: the branch name is parsed in `release.sh` through a new option that takes the branch name; the workflow passes `GITHUB_REF_NAME`. Consequence accepted: v1.0.0 needs a release carrying the option and a pin bump first.
- Q3: only the branch name carries the level. No dispatch input; a dispatch from `main` keeps the commit-decided bump, and a dispatch from a `release/major/...` ref honours its name.
- Q4: a forced level over a range with no commit still exits `2`, "nothing to release".
- Q5: a name that forces a level below what the commits imply is refused (exit `3`); forcing up is allowed. The explicit `--level` flag keeps today's behaviour.

## Q6 - The option: name and what it is given

Facts: the publish job checks out `ref: ${{ github.sha }}`, which is a detached `HEAD`, so `release.sh` cannot read the branch name from git in CI. The name has to be handed over.

- A. `--level-from <ref>`: takes a branch name (`release/major/20261015.1`, or `refs/heads/release/major/...`) and derives the level from it.
- B. `--release-branch <name>`: the same input, named after what it is rather than what it does.
- C. No option: `release.sh` reads `GITHUB_REF_NAME` from the environment on its own.

➡️ Recommendation: A. It reads next to `--level` in `--help`, says what it produces, and an explicit option is testable in bats without faking an environment. C hides an input and changes behaviour on every consumer that happens to run in Actions on a `release/*` ref.

### Answer to Q6

A

---

## Q7 - A name with no level

Confirm the other half of the contract: `release/20261015.1`, `release/hotfix-login` and a name given as `main` carry no level, and `release.sh` behaves exactly as today (bump decided by the commits), without a warning.

- A. Confirmed: no level in the name means no forced level and no output change.
- B. Confirmed, but the run logs one info line saying that no level was found in the name.

➡️ Recommendation: A. Every existing branch name takes this path, so a new line would show up in every release log for no decision. The `Bump` line already says `(forced with --level)` or not.

### Answer to Q7

A and it would be good indeed to handle hotfixes. usually, hotfixes **only patch** code from a tag so naming should be `hotfix/cannot-login`.

---

## Q8 - A name that looks like it carries a level but does not

With the segment layout, a name such as `release/mayor/20261015.1`, `release/Major/20261015.1` or `release/major` (no leaf) has the shape `release/<segment>/...` where the segment is not an accepted level. Which of these?

- A. Refused before anything is written: any name with a segment after `release/` whose first component is not `major`, `minor` or `patch` is refused, and the reason names the accepted values. The segment is reserved by the contract.
- B. Ignored: only the three exact values force a level, anything else behaves as in Q7.
- C. Refused only for near-misses (case variants such as `Major`), ignored otherwise.

➡️ Recommendation: A. With B a typo (`mayor`) silently publishes a commit-decided bump on a branch the maintainer meant to force, which is the failure the contract exists to prevent; C needs a typo list that is never complete. The cost of A is that `release/hotfix/login` stops being a free-form name, and that is acceptable because the date-based leaf is the convention.

### Answer to Q8

B

---

## Q9 - `--level` given together with the new option

The explicit `--level major` and the name-derived level can both be on a command line (a maintainer testing locally with `--level-from release/minor/x --level major`).

- A. Mutually exclusive: a command-line mistake, exit `1`, nothing written.
- B. The explicit `--level` wins and the name is ignored.
- C. They must agree, otherwise exit `1`.

➡️ Recommendation: A. Two sources for one decision is the ambiguity the issue is about, and the workflow only ever passes one of them. A is also the simplest thing to document and to pin with one test.

### Answer to Q9

A

---

## Q10 - Surfacing: what the preview shows

Facts: the preview job runs on a push to `main` and on a dispatch left on "preview". Neither has a `release/*` name on `main`, so the level cannot be known there. A dispatch with `preview` run from a `release/major/...` ref is possible, as the dispatch accepts any ref.

- A. No change on `main`. The preview job also passes the ref name, so a dispatch preview from `release/major/<id>` shows the forced version before anything is published.
- B. No change at all: the preview never passes the name; the level is only known at publish.
- C. The preview on `main` lists what each level would produce (major/minor/patch versions).

➡️ Recommendation: A. It costs one argument in the preview job, lets you see `1.0.0` before the publish push, and does not invent a level on `main` where none exists. C is noise on every merge.

### Answer to Q10

A

---

## Q11 - How v1.0.0 is cut under this contract

Given Q2 (parsing lives in `release.sh`, and the workflow runs the pinned copy), the path would be:

1. Merge the feature to `main`; it is a `feat`, so the next release is v0.5.0. Cut it as today (push a date-based `release/*` branch).
2. Move `RELEASE_SCRIPT_REF` to the v0.5.0 commit and merge that to `main`.
3. Push `release/major/<id>` cut from `main`; the publish job passes the name and the release is v1.0.0.

- A. That is the path; record it in the README and the implementation ticket.
- B. Cut v1.0.0 sooner, by hand with `./release.sh --level major` locally (works today, no new code), and keep the contract for the releases after.
- C. Something else (say what).

➡️ Recommendation: A. It is the contract being used end to end the first time, which is the best test of it, and v0.5.0 is a natural intermediate release. B stays available as an escape hatch if the workflow is broken, and does not need a decision.

### Answer to Q11

If A, what would be the release's content? I fear it'd be nothing
