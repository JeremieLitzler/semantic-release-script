# Grilling round v03 — control the release level from the release/\* branch name

## Settled in v02

- Q6: the option is `--level-from <ref>`; it takes a branch name and derives the level from it.
- Q7: a name with no level behaves exactly as today, with no extra output. Your answer also raised hotfixes (`hotfix/cannot-login`, patch only, from a tag); that is a decision of its own, in Q14.
- Q8: a name that looks like it carries a level but is not one of the three values is ignored, like any other name (B). It is not refused.
- Q9: `--level` together with `--level-from` is a command-line mistake: exit `1`, nothing written.
- Q10: no change on `main`; the preview job also passes the ref name, so a dispatch preview from `release/major/<id>` shows the forced version.

## Reopened

- Q11 came back as a question ("what would be the release's content? I fear it'd be nothing"). It is answered in Q12 and the path decision is re-asked as Q13.

## Q12 - What v0.5.0 would contain, and the commit type that decides it

Fact: `git log v0.4.0..main` holds three commits today, all `ci:` (#74: pin the workflow's `release.sh`, quote the `rev-parse` argument, name the tag in a comment). Alone they would release v0.4.1, with an `Others` section and no `Features`. So your fear is justified for the tree as it is now.

It stops being true once the implementation of this contract is merged: if its commit is typed `feat`, the range holds a feature, `release.sh` computes a minor bump, and the release is v0.5.0 with a `Features` section carrying the new option, plus `Others` for the three `ci:` commits. If it is typed `fix` or `ci`, the release is v0.4.1 and the path in Q11 produces a pin on v0.4.1, which is fine technically but is not the version numbering you expect.

- A. The implementation commit (or the PR's commits) carries a `feat:` type, which is what it is: a new option and a new branch-name contract. The release is v0.5.0.
- B. Keep it as a smaller type and accept v0.4.1 as the intermediate release.

➡️ Recommendation: A. It is a feature by the repo's own conventional-commit rules, and it makes the intermediate release informative (a `Features` entry linking the issue) instead of a bare list of CI changes.

### Answer to Q12

Yes but the v1.0.0 would have release contents. This is my question since no commit was created between v0.5.0 and v1.0.0.

---

## Q13 - How v1.0.0 is cut (re-ask of Q11)

Unchanged from v02, with the intermediate release named by Q12:

1. Merge the feature to `main`; cut v0.5.0 as today (push a date-based `release/*` branch).
2. Move `RELEASE_SCRIPT_REF` to the v0.5.0 commit and merge that to `main` (a `ci:` commit, so the range for the next release is not empty).
3. Push `release/major/<id>` cut from `main`; the publish job passes the name and the release is v1.0.0.

- A. That is the path; record it in the README and the implementation ticket.
- B. Cut v1.0.0 sooner, by hand with `./release.sh --level major` locally (works today, no new code), and keep the contract for the releases after.
- C. Something else (say what).

➡️ Recommendation: A. It uses the contract end to end the first time, and B stays available as an escape hatch without needing a decision.

### Answer to Q13

No answer. See Q12.

---

## Q14 - Hotfixes: part of this contract?

Your note: hotfixes only patch code from a tag, so the name would be `hotfix/cannot-login`.

Facts:

- `hotfix/*` is not a `release/*` ref. The workflow triggers on `main` and `release/**` only, and the publish job's guard refuses any ref that is not `main` or `release/*`.
- A branch cut from a tag older than `main`'s head, then released, writes its tag on a commit `main` does not carry. That is a stranded tag, which the guards refuse; it is also what the closed maintenance-lines grilling (#13) ruled out as unsupported.
- Under Q5 the name `release/patch/<id>` already enforces "only patch": if the range holds a `feat` or a breaking commit, the release is refused. So a patch-only release from `main` is already expressible in this contract.

- A. Out of scope. The hotfix path is `release/patch/<id>` cut from `main`; no `hotfix/*` family, no workflow trigger change. The README names it as the way to cut a patch-only release.
- B. Add `hotfix/<name>` as a second accepted shape that forces a patch, with `hotfix/**` added to the workflow triggers and to the publish guard.
- C. A separate ticket: a real hotfix from a tag is the maintenance-line question again, and gets its own grilling if it ever matters.

➡️ Recommendation: A, with C as the answer when someone needs a fix from a tag rather than from `main`. B gives a second name for the same behaviour and would pretend to a "from a tag" semantics the guards refuse; `release/patch/<id>` already delivers "patch only" and rejects the range that is not.

### Answer to Q14

A

---

## Q15 - A forced level on a resume

Facts: on a resume (a half-published release), the version is read off the tag and `--level` is ignored with a warning ("--level is ignored on a resume: vX already carries the version"). Q5's refusal compares the forced level to what the commits imply, which on a resume has no version to compute.

- A. Same as `--level`: `--level-from` is ignored on a resume with the same kind of warning; the Q5 refusal does not run.
- B. The Q5 refusal still weighs on a resume, since "every guard still weighs on it".
- C. Refuse a resume when the name carries a level at all.

➡️ Recommendation: A. A resume finishes a release whose version is already decided, and a failed run on `release/major/<id>` must be re-pushable without the name getting in the way. Q9 (both options at once, exit `1`) still applies, since that is a command-line mistake.

### Answer to Q15

A

---

## Q16 - Which modes weigh the Q5 refusal

The refusal is about the version, not about where the tag lands, so the glossary's "warns under `--dry-run`" for guards over the tag's landing place does not apply by default.

- A. Every mode that computes a version weighs it: a real run, `--dry-run`, `--local`, and `--check` (which lists it in the setup report with its reason and fix when `--level-from` is given). `--dry-run` refuses with exit `3`, so the preview shows the same outcome as the publish.
- B. Only a real run refuses; `--dry-run` and `--check` report it as a warning.

➡️ Recommendation: A. A preview that says "1.0.0" and a publish that then refuses is the surprise the preview exists to remove (Q10 gives the preview the name for that reason).

### Answer to Q16

A

---

## Q17 - Where the contract is documented

- A. README "Cutting a release" (the branch-name contract, the refusals, the v1.0.0 path), `CONTEXT.md` (a new term for the segment, and an update to the **Bump** entry's "Avoid: level" note), and an ADR in a new `docs/adr/`: the parsing sits in `release.sh`, and the name-derived level is stricter than `--level`.
- B. README and `CONTEXT.md` only.
- C. README only.

➡️ Recommendation: A. The ADR passes the three tests: it is costly to change once consumers name branches this way, it surprises a reader who expects the workflow to own CI behaviour, and Q2 was a real trade-off (the two-step path to v1.0.0 was accepted for testability). The proposed term for `CONTEXT.md` is **Level segment**: the path component after `release/` that names the level the release is forced to.

### Answer to Q17

A
