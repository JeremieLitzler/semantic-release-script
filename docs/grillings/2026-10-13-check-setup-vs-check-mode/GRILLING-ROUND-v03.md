# Grilling round v03 — check-setup.sh or a release.sh --check mode (#14)

## Settled in v02

- Q1b: single-file vendoring is a **hard constraint**: a consumer vendors exactly one file. That rules out `check-setup.sh`, so the choice in #14 is **a `--check` mode of `release.sh`**, whose checks are functions shared with the preflight (Q2 = B). I am treating the option as decided, not asking it again.
- Correction on my side: `semantic-release-script-testing` is this repo under its old name, so the consumers vendor from here. My "not this repo" in v02 was wrong; nothing else in the recommendations depended on it.
- Q4: the length of `release.sh` and the language question are **out of scope** for #14. They belong to a new issue. I have not created it; see Q9.
- Q5: each check returns a result; the preflight still stops at the first failure with today's wording and exit code; `--check` runs every check and prints all results with the reason and the fix.
- Q3 (from v01) still holds: the report is for a human, so its output is human-readable text, not `key=value`.

## Facts found

- Resolving the baseline already runs `git fetch --tags origin` (`release.sh:354`), so the checks that detect a shallow clone, stale tags and a stranded tag are not read-only today: fetching writes tag refs to the local repository.
- The guards (shallow clone, stale tags, stranded tag, tag taken) are reached through `resolve_baseline` and `verify_trunk_contains` on a ref, after the preflight. They end in `stop "$EXIT_REFUSED"` (exit `3`); a missing tool or login ends in `die` (exit `1`).

## Q6 - Which checks does the report run?

The preflight today covers the environment (bash 4, `git`, `gh`, inside a work tree, `gh` logged in, repository resolved, trunk resolved) and warns on branch name and dirty tree. The guards cover the repository's state (shallow clone, stale tags, stranded tag, a tag already taken, a non-monotonic version, a half-published release to resume). The two consumers' CI adds guards of its own on top (a `release/*` ref the trunk doesn't contain, an orphaned tag).

A. Preflight only: the environment and the two warnings.
B. Preflight and the guards, so the report answers "would a release refuse right now, and why?" on the target.
C. B, plus checks `release.sh` does not run today (e.g. the token's permissions to push a tag and create a release).

➡️ Recommendation: **B**. The report is meant for a human after vendoring or after a refusal (Q3), and most refusals come from the guards, so A would miss the cases that matter. C adds new checks nobody has asked for and each one is a new thing to keep correct; it can follow as its own issue if a consumer hits it.

### Answer to Q6

B

---

## Q7 - What exit code does `--check` end on?

The contract is `0` ok, `1` error, `2` nothing to release, `3` refused. A report runs every check, so a run can have a mix of passes, warnings and failures.

A. `0` when every check passes (warnings allowed), `3` when any check a release would refuse on fails, `1` when `--check` itself cannot run (bad usage, no `git`/`gh` to even evaluate with).
B. `0` always once the report is printed; the human reads it.
C. `0` all pass, `3` any failure, and warnings also change the code.

➡️ Recommendation: **A**. It reuses the existing meanings: `3` is exactly "a guard would refuse this release", so a consumer who does script it reads the same code as for a real run, and a warning stays a warning as it does in the preflight today. **B** hides failures from anything that reads the code.

### Answer to Q7

A

---

## Q8 - May `--check` run with the other options?

`--check` needs to know the target the guards are weighed against: `--trunk`, `--to` and `--since` change the answer. Other options (`--yes`, `--dry-run`, `--local`, `--notes`, `--changelog`, `--summary`, `--level`) shape a release and have no meaning for a report.

A. `--check` accepts the options that name the target (`--trunk`, `--to`, `--since`) and refuses any other with exit `1`.
B. `--check` accepts every option and ignores the ones that don't apply.
C. `--check` accepts no other option: it always checks `HEAD` against the resolved trunk.

➡️ Recommendation: **A**. A consumer on a repo whose trunk is not the GitHub default needs `--trunk`, and someone previewing a range needs `--to`/`--since`, so the report must be able to weigh the same target a release would. Refusing the release-shaping options with exit `1` avoids a human assuming `--notes` wrote a file.

### Answer to Q8

A

---

## Q9 - Is `--check` allowed to write local tag refs, as `git fetch --tags` does?

Evaluating the stale-tags and stranded-tag guards means fetching tags (see Facts). A report that is supposed to only explain can either do the fetch the guards do, or stay read-only and say it could not check.

A. Allowed: `--check` runs the same `git fetch --tags origin` the release does, because a check that skips the fetch weighs different tags than a release would. It writes nothing to the remote and no file.
B. Read-only: `--check` skips the fetch, and reports the stale-tags and tag-based guards as "not checked" unless the tags are already up to date.

➡️ Recommendation: **A**. The fetch is what the release does anyway, and a report on stale tags that doesn't fetch is a report on the tags the release would not use. It still writes nothing a release would not write, and `CONTEXT.md`'s **Preview** already tolerates reads from the remote with local effects only for `--local`, so the glossary should say a check is a preview that writes no tag.

### Answer to Q9

A

---

## Q10 - Do we create the new issue for the length/language concern now, and record this decision as an ADR?

Two follow-ups from the settled branches:

A. Create a GitHub issue for "release.sh is long; is Bash the right technology?" now, labelled `needs-triage`, and write an ADR for #14's choice ("`--check` mode, not a second script, because consumers vendor one file").
B. Create the issue, but no ADR: the choice is documented in the `CONTEXT.md` glossary only.
C. Neither yet; wait for the end of the grilling.

➡️ Recommendation: **A at the end of the session**, not now: the ADR meets all three tests (hard to reverse once consumers have vendored a second file, surprising without the single-file context, a real trade-off against `check-setup.sh`), and the issue should carry the wording you settle with Q8/Q9 in mind. I will ask for your go-ahead on both before creating anything. For now I only need your choice of A, B or C.

### Answer to Q10

B
