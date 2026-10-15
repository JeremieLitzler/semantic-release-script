# Grilling round v04 — control the release level from the release/\* branch name

## Settled in v03

- Q12: the implementation carries a `feat:` type (the contract is a feature), so the intermediate release is v0.5.0 and its `Features` section names the option.
- Q14: hotfixes are out of scope. The patch-only path is `release/patch/<id>` cut from `main`; no `hotfix/*` family, no workflow trigger change. A fix from a tag, rather than from `main`, would be the maintenance-line question again and gets its own ticket if it ever matters.
- Q16: every mode that computes a version weighs the Q5 refusal: a real run, `--dry-run` (refuses with exit `3`), `--local`, and `--check` (listed in the setup report with its reason and fix).
- Q17: documented in README "Cutting a release", `CONTEXT.md` (a new term **Level segment**, and the **Bump** entry's "Avoid: level" note updated) and an ADR in a new `docs/adr/`.

## Reopened

- Q12 came back as a question: you accept the `feat:` type, but v1.0.0 would have "release contents" of nothing, since no commit sits between v0.5.0 and v1.0.0. It is answered in Q18, and the Q13 path, which depended on it, is re-asked as Q19.

## Q18 - What v1.0.0 would contain under the v0.5.0-first path

Fact: this is the range the notes of v1.0.0 would be built over. The baseline is v0.5.0, so the range is v0.5.0 to the tip of `main`, which holds exactly one commit from the path itself: the `ci:` commit that moves `RELEASE_SCRIPT_REF` to v0.5.0 (Q11 step 2). Without it the range would be empty and Q4 applies: `release.sh` exits `2` and no v1.0.0 is cut, even with `release/major/<id>`. With it, the notes are one `Others` line and nothing else: the first stable release announces only a pin move, and the feature that made it possible is in v0.5.0's notes.

- A. Acceptable: the v1.0.0 notes say what changed since v0.5.0, which is what they always say. The GitHub release for v1.0.0 can carry a line you edit by hand afterward, or not.
- B. Not acceptable: v1.0.0 should carry the feature.

➡️ Recommendation: A. Notes are built from the range, and a forced level never changes the range (the README states it for `--level`: "the notes are still built from the real commits"). If the first stable release must carry the feature, that is a question of which path you take (Q19), not of the notes.

### Answer to Q18

A, but documenting it is key for future users.

---

## Q19 - How v1.0.0 is cut (re-ask of Q13, itself the re-ask of Q11)

- A. v0.5.0 first, as in v03 Q13: merge the feature, cut v0.5.0 as today, move `RELEASE_SCRIPT_REF` to the v0.5.0 commit, then push `release/major/<id>`. The v1.0.0 notes are the pin-move commit (Q18).
- B. No v0.5.0: merge the feature, move `RELEASE_SCRIPT_REF` to the SHA of the feature's merge commit on `main` (not a version tag), then push `release/major/<id>`. The range is v0.4.0 to `main`, so the v1.0.0 notes carry the feature under `Features` and the three `ci:` commits and the pin move under `Others`. The pin comment would name the commit instead of a tag until the next pin move to v1.0.0.
- C. Cut v1.0.0 by hand with `./release.sh --level major` locally, today, no new code; keep the contract for the releases after.

➡️ Recommendation: B if you want the first stable release to carry the feature; A if you prefer the pin to always sit on a released tag, as the workflow comment says ("the commit the latest published release points to"), and accept Q18 as it is. Going by your two last answers (the feature is the reason for v1.0.0; "I fear it'd be nothing"), B is the one that matches your intention. It bends the pin rule once, for a commit on `main` that the bats suite already validated, and the next pin move restores it.

### Answer to Q19

B
