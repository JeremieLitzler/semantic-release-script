# Grilling round v07 — fixture test harness for release.sh

## Settled in v06

- Q42b: the seed uses **plain issue titles** ("The cart total goes out of sync"), with no type prefix. Your edit to `tests/create-dummy-issues.sh` is superseded, since that file is deleted in this slice (Q5).
- Q43: the live test **normalises the repo name and hashes on both sides, then diffs its notes against the reference golden**.

The frontier is empty. `GRILLING-SUMMARY.md` in this folder restates the whole outcome, indexes every decision, lists what I decided without grilling, and ends with a paste-ready GitHub issue.

## Q44 - Does the summary match your understanding?

Read `GRILLING-SUMMARY.md`, especially "Decided without grilling: object before implementation". Corrections go straight into the summary; only a correction that reopens a real decision starts a new round.

a. **Yes, it matches.**
b. **Corrections needed** (edit the summary or list them here).

➡️ Recommendation: **a**, once "Decided without grilling" has no surprises for you.

### Answer to Q44

(a)
