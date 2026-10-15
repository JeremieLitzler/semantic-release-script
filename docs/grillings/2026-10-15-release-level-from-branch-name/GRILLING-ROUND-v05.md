# Grilling round v05 — control the release level from the release/\* branch name

## Settled in v04

- Q15 (v03): `--level-from` is ignored with a warning on a resume, like `--level`; the Q5 refusal does not run.
- Q18: thin v1.0.0 notes are acceptable, and must be documented for future users.
- Q19: no v0.5.0. The pin moves to the SHA of the feature's merge commit on `main`, then `release/major/<id>` is pushed; the v1.0.0 notes carry the feature and the `ci:` commits.

## Q20 - Does the summary match your understanding?

`GRILLING-SUMMARY.md` in this folder holds the restated understanding, the decision index, the paste-ready section for #77 and the list of things decided without being grilled.

- A. It matches; go ahead.
- B. It does not match; correct it in `GRILLING-SUMMARY.md` (an edit there is not a new round unless it reopens a decision).

➡️ Recommendation: A, after you have read the "Decided without being grilled" list: it holds the three items most likely to need an objection (the prefix form of the ref, the `release/major` name with no leaf, and the meaning of "below what the commits imply").

### Answer to Q20

Actually, reading the summary made me think a very simple way is to write a `release-1.0.0.md` under the `docs/` folder which is a summary (not a word-to-word repeat of release's notes between each major). I know it reopens the grilling.
