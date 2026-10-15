# Grilling round v06 — control the release level from the release/\* branch name

## Settled in v05

- Q20 is not answered with A or B: your answer proposes a new element, a hand-written `docs/release-1.0.0.md` that summarises a major (not a repeat of the release notes between two majors). It is treated as a reopening, narrowed to Q18 (how the thin v1.0.0 notes are documented). `GRILLING-SUMMARY.md` is left as is until these are settled, then amended and Q20 re-asked.

## Reopened

- Q18 (thin v1.0.0 notes are acceptable and must be documented): the documentation you asked for is now proposed to be a file in `docs/` rather than only a README paragraph. Q19's path stays, with one added step, shown below.

Facts for the three questions:

- The v1.0.0 path under Q19 becomes: (1) merge the `feat:` implementation; (2) move `RELEASE_SCRIPT_REF` to its merge SHA; (3) write and merge `docs/release-1.0.0.md` (a `docs:` commit, which lands in the range and appears under `Others`, and does not change the forced major); (4) push `release/major/<id>`.
- `release.sh` builds the GitHub release body from the commits in the range only. It does not read any file from the repository today, and nothing links to a document.
- A forced level never changes the range, so for a major the commits since the previous tag are what the notes list, whatever the file says.

## Q21 - Scope: v1.0.0 only, or every major?

- A. A convention for every major: `docs/release-<version>.md` (`release-1.0.0.md`, `release-2.0.0.md`), written by hand before the `release/major/<id>` push, summarising what the major means and what changed for consumers since the previous major.
- B. A one-off for v1.0.0: the first stable release is the one with no breaking change in its range and a story to tell; later majors are driven by `BREAKING CHANGES` notes and need no summary.
- C. Optional, no rule: the file is written when a maintainer wants one, and the contract does not mention it.

➡️ Recommendation: A, as a documented convention with no enforcement (a script refusal on a missing file would be a later, separate decision). A major is exactly when the commit list stops being a good summary for a consumer, in v1.0.0 and in every one after it, and a rule written once costs nothing for the minor and patch releases that never need it.

### Answer to Q21

A

---

## Q22 - Does the GitHub release point to the file?

- A. No tooling: the file is linked from the README ("Cutting a release") and the `docs:` commit shows in the notes under `Others`. The GitHub release for the major can have a line added by hand.
- B. `release.sh` adds a line to the notes of a release when `docs/release-<version>.md` exists at the commit being released, linking it. This is a new behaviour of the script and needs its own tests and a pin move to be usable.
- C. The workflow adds the link after the release, without touching `release.sh`.

➡️ Recommendation: A. The script has no repository-file input today, and B or C would add one for a file that exists once per major; the README link and the `docs:` commit give a reader the way in. If a consumer later needs the pointer, B is a self-contained follow-up.

### Answer to Q22

A

---

## Q23 - What the summary must say

For a major, a short document a consumer reads instead of the whole history. A proposed outline, each part optional when it has nothing to say:

1. What this major means (for v1.0.0: the declaration that the interface, the exit codes and the options are now stable).
2. What breaks since the previous major, and what to change (for v1.0.0 there is nothing, and it says so).
3. The new things worth knowing, grouped by theme rather than by commit.
4. A link to the range of releases it covers.

- A. That outline, as a recommendation in the README, no template file in the repo.
- B. A fixed template (a file under `docs/`) that every major copies.
- C. Free form: no outline, only "summarise the major".

➡️ Recommendation: A. A template for a document written once per major is more machinery than the document; an outline in the README is enough to keep the summary from becoming a copy of the notes, which is the thing you want to avoid.

### Answer to Q23

A
