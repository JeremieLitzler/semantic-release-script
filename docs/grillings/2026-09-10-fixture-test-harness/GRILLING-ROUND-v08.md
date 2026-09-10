# Grilling round v08 — fixture test harness for release.sh (implementation of #12)

## Settled while starting the implementation

- The seed script is run against `JeremieLitzler/semantic-release-script-tests` once it's written, so the number map is written from the numbers GitHub assigns.
- The live suite is run once, with `LIVE=1`, before the work is committed.
- `SYNC-PLAYBOOK.md` is committed and pushed alone in `my-claude-conversations`, leaving your other pending changes untouched.

## Q45 - The commits appended to the reference dataset

The 14 commits from `COMMIT-MESSAGES.md` stay verbatim and in order, with their issue numbers taken from the number map. These commits are appended after commit 14. `<PR>` is the closed pull request's number, and `<CSV>` is the number of the issue "Export the orders as CSV", which commit 9 (`feat: export the orders as CSV`) already references.

| #   | Commit subject                                     | Commit body                                               | Rule it covers                                                    | Expected in the notes                                                                   |
| --- | -------------------------------------------------- | --------------------------------------------------------- | ----------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| 15  | `chore: tidy the issue templates (#<PR>)`          |                                                           | a PR number is filtered out                                       | commit message + link, under Others                                                     |
| 16  | `test: cover the CSV export (#<CSV>)`              |                                                           | dedupe by issue                                                   | no line of its own: folded into the CSV issue's line                                    |
| 17  | `fix: quote the commas in the CSV export (#<CSV>)` |                                                           | dedupe keeps the most significant category                        | the CSV issue stays listed once, under Features (the `feat` wins over `fix` and `test`) |
| 18  | `perf: stream the order export`                    | `BREAKING-CHANGE: the export endpoint now returns NDJSON` | the `BREAKING-CHANGE:` synonym                                    | commit message + link, under BREAKING CHANGES                                           |
| 19  | `docs: describe the upgrade path`                  | `No BREAKING CHANGE here: the old flags still work.`      | "BREAKING CHANGE" in prose doesn't count                          | commit message + link, under Others                                                     |
| 20  | `docs: add the contributing guide`                 |                                                           | the commit a merge brings in (made on a side branch)              | commit message + link, under Others                                                     |
| 21  | `Merge branch 'contributing-guide'`                |                                                           | a merge commit is ignored (`--no-ff` merge of commit 20's branch) | nothing                                                                                 |

The bump for the whole dataset stays **major** (commits 13, 14 and 18), so the reference release is still `v1.0.0`.

a. **Use these commits**, in this order.
b. **Change them** (say what).

➡️ Recommendation: **a**. Each commit exercises one rule the 14 commits miss, and a failure shows up as a one-line diff in the reference golden.

### Answer to Q45

(a)
