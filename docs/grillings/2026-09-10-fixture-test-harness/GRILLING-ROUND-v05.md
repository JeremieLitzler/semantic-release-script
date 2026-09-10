# Grilling round v05 — fixture test harness for release.sh

## Settled in v04

- Q31: the sync playbook lives at **`my-claude-conversations/prompts/2026-09-10-release-sh-sync/SYNC-PLAYBOOK.md`**.
- Q32: the sync playbook is **written in this slice**, and candidates 02-05 amend it as they change what a sync involves.
- Q33: the sandbox is seeded by a **committed, idempotent seed script** that creates only what's missing and prints the numbers.
- Q34: the live run uses **the reference dataset recorded in `COMMIT-MESSAGES.md`** instead of the small seed I proposed. My reading: the live run pushes the same commits the fixture suite's reference dataset builds, and the seed creates the issues those commits reference (today #2, #3, #5, #6, #7, #8, plus #4, which was created but no commit references it). The file itself still goes away as settled in Q5, because its content now lives in the fixture builder. Since the dataset has a `feat!`, every live run releases **`v1.0.0`**. If I've misread "use `COMMIT-MESSAGES.md`", say so under Q41 or Q42.
- Q35: the live test **only ever targets `JeremieLitzler/semantic-release-script-tests`**, checked with `gh repo view`, and always works in its own fresh clone in a temp dir.
- Q36: after a failed live run, the sandbox is **left as it was so you can inspect it**. The next run's reset clears it.
- Q38: `tests/live.bats` **skips every test unless `LIVE=1`**.
- Q39: the human gates are **out of scope**. The exit-0-when-no-terminal finding goes to **candidate 04**.

## Reopened

- Q37: your answer is itself a question ("If rules are already written into the script, (b) is the smart choice, isn't it?"). Q40 answers it, and the decision is re-asked as Q37b. Your Q34 answer also changes the trade-off, which Q40 explains.

## Q40 - Does "the rules are already in the script" favour extending the dataset? (your question in Q37)

Not on its own: both options test exactly the rules the script already has. The difference is how the tests are laid out. But you're pointing at something real, and two things shift the balance towards b:

- **My argument for a was overstated.** I said one growing dataset "makes every failure a diff through 20+ lines". A golden diff only shows the lines that changed, so a broken rule still shows up as one or two lines. The readability cost of b is small.
- **Your Q34 answer makes the reference dataset the live dataset too.** Whatever it contains runs against real GitHub. The PR filter is one of the three rules that depend on real `gh` (issue title, PR filter, 404), and it's only covered live if the dataset holds a PR reference, which the 14 commits don't.

What still favours a is that when a focused scenario fails, its test name says which rule broke. Also, inserting a commit into the middle of the dataset changes every later hash, so a dataset that grows should only grow at the end.

Some rules can't live in one dataset whatever you pick: a patch-only or minor-only bump (the dataset always bumps major, because of its `feat!`), `--level`, replay, the first release, and the options. Those get focused scenarios either way.

a. **This explanation matches your thinking**, and Q37b decides.
b. **Something in it is wrong or missing** (say what).

➡️ Recommendation: **a**.

### Answer to Q40

(a)

## Q37b - The reference dataset and the rules it misses

The 14-commit dataset covers the categories, `!` and body `BREAKING CHANGE`, issue vs no reference, and a non-existent number. It **doesn't** cover: a PR number being filtered out, dedupe by issue (added in `9283f36`), the `BREAKING-CHANGE` synonym, "BREAKING CHANGE" in prose not counting, and merge commits being ignored.

a. **Keep the 14 commits verbatim** as the reference dataset with its own golden notes, and cover each missing rule with a small, focused scenario of its own.
b. **Extend the reference dataset**: append commits at the end for each missing rule (a commit referencing a PR, two commits of different categories on the same issue, a `BREAKING-CHANGE:` footer, "BREAKING CHANGE" in prose, a merge commit). One golden file covers every notes rule, and the same dataset runs live, so the PR filter is checked against real GitHub. Bump levels and the options still get focused scenarios (Q40).

➡️ Recommendation: **b**. With the reference dataset now also the live dataset (Q34), extending it is the only way the PR filter gets checked against real GitHub. It also keeps one readable spec of every notes rule, the role `COMMIT-MESSAGES.md` played. Appending at the end keeps the 14 original hashes stable.

### Answer to Q37b

(b)

## Q41 - Issue numbers shared by both suites

The dataset's commit subjects embed issue numbers (`(#6)`). In the sandbox, GitHub assigns numbers from `#1` up, in the order the seed creates things.

a. **One committed number map** (e.g. `tests/fixtures/reference-issues.env`) written by the seed script, holding each issue's number and title. The fixture suite declares its fake issues from the same map, so both suites build the exact same commit subjects, and the fake's issues match the real ones number for number and title for title.
b. **Separate numbers**: the fixture suite keeps its own fixed numbers (#2-#8 as today), and the live suite uses whatever the sandbox assigned.

➡️ Recommendation: **a**. With identical subjects, numbers and titles, the only differences between a live run's notes and the fixture golden are the repo name and the commit hashes. That makes the "does the fake tell the truth" comparison mechanical. How the live test compares them comes next round.

### Answer to Q41

(a)

## Q42 - Issue titles in the seed

`create-dummy-issues.sh` gave every dummy issue a `feat:` prefix, even the bug ones ("feat: the cart total goes out of sync"), as a marker so humans could spot them in a busy tracker. The titles land in the golden notes as they are.

a. **Plain titles** in the dedicated sandbox, e.g. "The cart total goes out of sync". The sandbox holds nothing else, so no marker is needed, and the notes read like real ones.
b. **Keep the `feat:` prefix**, exactly as today.

➡️ Recommendation: **a**. The prefix only made sense in a repo that also held real issues. In the golden notes it reads like a bug listed as a feature.

### Answer to Q42

I fixed `create-dummy-issues.sh` so (a) applies
