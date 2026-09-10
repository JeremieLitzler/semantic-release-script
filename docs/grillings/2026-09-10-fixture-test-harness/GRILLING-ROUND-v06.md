# Grilling round v06 — fixture test harness for release.sh

## Settled in v05

- Q40: the explanation matches your thinking: both options test the same rules, my "20+ line diff" argument was overstated, and your Q34 answer tipped it towards extending the dataset.
- Q37b: the reference dataset is **extended by appending commits at the end** for the rules it missed: a PR reference, two commits of different categories on the same issue, a `BREAKING-CHANGE:` footer, "BREAKING CHANGE" in prose, and a merge commit. One golden file covers every notes rule, and the same dataset runs live. Bump levels (patch-only, minor-only), `--level`, replay, the first release and the options get focused scenarios.
- Q41: **one committed number map** (e.g. `tests/fixtures/reference-issues.env`), written by the seed script, holds each issue's number and title. Both suites build identical commit subjects from it, and the fake's issues match the sandbox's.

## Reopened

- Q42: you answered "(a) applies" (plain titles), but your edit to `tests/create-dummy-issues.sh` gives the titles a conventional-type prefix matching their category: `feat:` for features, `feat!:` for the breaking one, `fix:` for the bugs. That's neither plain (a) nor `feat:` everywhere (b). Re-asked as Q42b so the seed script, which replaces `create-dummy-issues.sh` (Q5, Q33), gets the titles you actually want.

## Q42b - Issue titles in the seed

Here's how each choice reads in the golden notes:

```markdown
### Bug fixes

- The cart total goes out of sync (#6)          <- a
- fix: the cart total goes out of sync (#6)     <- b
```

a. **Plain titles**: "The cart total goes out of sync". This is what issue titles look like in a real tracker (e.g. "Add a button to refresh data from remote source" in `french-gas-stations-scraper`), and the section heading already says it's a fix.
b. **Type prefix matching the category**, as in your edit: `feat:`, `feat!:`, `fix:`. Each issue shows at a glance which rule it exercises, at the cost of repeating the section heading on every line.

➡️ Recommendation: **a**. The golden notes then read like the notes a consumer actually publishes, so the live comparison (Q43) checks realistic output. The category is already visible from the section.

### Answer to Q42b

(a)

## Q43 - How the live test compares its notes

Thanks to Q41, a live run and the fixture build share the same commit subjects, issue numbers and titles. The notes can still differ in two ways: the repo in commit links (`semantic-release-script-tests` vs the fake's repo name), and the commit hashes. The sandbox's history starts from its own `Initial commit`, so every hash above it differs from the fixture's.

a. **Normalise, then diff against the reference golden**: replace the repo name and every 7- or 40-character hash with placeholders on both sides, then `diff`. Any other difference (a title that didn't resolve, a PR not filtered, a 404 not falling back) fails the test, with a readable diff.
b. **Make the histories identical**: instead of resetting to `Initial commit` (Q28), the live run force-pushes the fixture-built history as the sandbox's `main`. The hashes then match exactly, and only the repo name needs replacing. This reopens Q28, and the sandbox's `README.md` and `LICENSE` vanish from `main`.
c. **Check specific lines only**: `grep` for the lines that depend on `gh` (the resolved titles, the PR line's fallback, the `#9999` fallback).

➡️ Recommendation: **a**. The live suite only has to prove that real `gh` behaves the way the fake assumes. Hashes and links are built locally, and the fixture suite already pins them. a checks every `gh`-dependent line through the one golden, without touching Q28.

### Answer to Q43

(a)
