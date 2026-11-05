# Grilling round v05 — leave out commits that only touch excluded paths

## Settled in v04

- Q26: two paths that differ only by case stay distinct, as in git; the docs must be very clear about it.
- Q27: the match is case-sensitive.
- Q28: a commit touching excluded and non-excluded paths stays in the notes under its usual section and counts in the bump in full; the option filters commits, not files.
- Your note: the regex-alternation issue is created.

The frontier is empty. `GRILLING-SUMMARY.md` is written, and `CONTEXT.md` now holds **Excluded path** and **Excluded commit**.

## Q29 - Does the summary match your understanding?

Read `GRILLING-SUMMARY.md`, in particular its "Never grilled, decided here" section (the ADR proposed for the implementation, the README placement, the refusal wording and tests, and `--level` over an all-excluded range still exiting `2`).

- A. Yes, it matches; the next move is the implementation.
- B. Something is off (edit the summary in place, or say what here).

➡️ Recommendation: A, after you have read the "Never grilled, decided here" list, since those four points were decided without a question.

### Answer to Q29

yes
