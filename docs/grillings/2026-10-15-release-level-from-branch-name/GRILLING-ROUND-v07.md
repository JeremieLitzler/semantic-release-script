# Grilling round v07 — control the release level from the release/\* branch name

## Settled in v06

- Q21: the summary of a major, `docs/release-<version>.md`, is a convention for every major, written by hand before the `release/major/<id>` push, with no enforcement.
- Q22: no tooling links the GitHub release to it; the README links it, and a line can be added to the release by hand.
- Q23: the README recommends an outline (what the major means, what breaks and what to change, the new things by theme, a link to the range), with no template file.

## Q24 - Does the amended summary match your understanding? (re-ask of Q20)

`GRILLING-SUMMARY.md` has been amended in place: a paragraph on the major summary, the added step in the v1.0.0 path, the "Major summary" line in the paste-ready section, Q20 to Q23 in the decision index, and two more items under "Decided without being grilled" (no enforcement, and the summary's commit lands in the release's range).

- A. It matches; go ahead (`CONTEXT.md` term, the ADR, and the implementation ticket are separate asks I then name).
- B. It does not match; correct it in `GRILLING-SUMMARY.md`.

➡️ Recommendation: A, once you have read the two new "Decided without being grilled" items, which are the part of this round I assumed.

### Answer to Q24

A
