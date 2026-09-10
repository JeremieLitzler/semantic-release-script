# Grilling round v04 — fixture test harness for release.sh

## Settled in v03

- Q26: **two suites**. The fixture suite is offline, uses the fake `gh` and a bare `origin`, and runs in CI and locally. The live suite is a handful of opt-in tests against `semantic-release-script-tests` with the real `gh`, and its job is to keep the fake honest.
- Q15b: the fake `gh` **stores raw GitHub-shaped JSON and runs the given `--jq` expression through real `jq`**. `jq` is the second dev dependency.
- Q16b: each test **declares its GitHub state with helper calls** (`given_issue`, `given_pull_request`, ...) in its own state dir. An undeclared number answers like a real 404, and the reference dataset declares its issues in one shared helper.
- Q17b: the fake **logs every call** (arguments, plus a copy of the notes file for `release create`), so tests can check what was or wasn't published.
- Q18b: the fake's `release create --verify-tag` **fails when the tag isn't in the bare `origin`**.
- Q27: the consumer playbook is a **standing sync playbook** that agents follow for every sync. Its first run also handles this move. Each consumer's `VENDORED.md` shrinks to provenance plus a pointer to it.
- Q28: each live run **resets the sandbox's `main` to `Initial commit`**, pushes a small fixed dataset, releases with `--yes`, checks, then deletes the release and tag and resets `main` again.
- Q29: the sandbox's issues and pull request are **seeded once and kept forever**. The live dataset refers to them by number, and the test checks they still exist first.
- Q30: **nothing stays at the root** once `release.sh` moves to `scripts/release/release.sh`.

## Q31 - Name and path of the sync playbook

Folders in `my-claude-conversations/prompts/` are named `YYYY-MM-DD-<slug>/` (e.g. `2026-09-09-single-trunk-release-migration/RELEASE-MIGRATION.md`). The date there usually means "when it was written", but this playbook is standing and gets edited at every upstream change.

a. **`prompts/2026-09-10-release-sh-sync/SYNC-PLAYBOOK.md`**: follows the folder convention, dated when it was created.
b. **`prompts/release-sh-sync/SYNC-PLAYBOOK.md`**: no date, because it's a living document.

➡️ Recommendation: **a**. It keeps the archive's one naming convention, and the date only records when it was first written; git has the rest.

### Answer to Q31

(a)

## Q32 - When the sync playbook is written

a. **In this slice**: this slice moves the file, so it writes the steps that follow the move (new path, new repo name, `VENDORED.md` shrinking to a pointer). Candidates 02-05 then amend it as they change what a sync involves (e.g. candidate 03 removes the trunk-name local hunk).
b. **With candidate 05**, right before the consumers run it (Q13).

➡️ Recommendation: **a**. The change that creates a sync step should also write it down, while it's fresh. Written as late as 05, it would have to piece four candidates back together.

### Answer to Q32

(a)

## Q33 - How the sandbox gets seeded

a. **A committed, idempotent seed script** (e.g. `tests/live/seed-sandbox.sh`): it creates the issues and the closed PR only if they're missing, and prints their numbers. It can be re-run safely, and it rebuilds the sandbox if the repo is ever wiped.
b. **By hand, once**: I create them now with `gh`, and the live test hard-codes the numbers.

➡️ Recommendation: **a**. The numbers then come from a documented source, not from memory, and the live test's "they still exist" check can point to the script when they don't.

### Answer to Q33

(a)

## Q34 - What the seed contains

Proposed seed, plus what the live dataset does with each item:

- **Issue A**, "Live: a feature" > referenced by a `feat:` commit > its title must appear under Features.
- **Issue B**, "Live: a bug" > referenced by a `fix:` commit > its title must appear under Bug fixes.
- **PR C**, opened from a branch and closed unmerged > referenced by a `chore:` commit > filtered as a PR, so the commit link appears under Others.
- **A number that doesn't exist** (e.g. `#9999`) > referenced by a `docs:` commit > 404 fallback to the commit link.

With no tag left in the sandbox after each run, the baseline is always `0.0.0`, so every run releases the same version (`v0.1.0`).

a. **This seed.**
b. **Something else** (say what to add or drop).

➡️ Recommendation: **a**. It covers exactly the three real-`gh` behaviours the fake mimics (issue title, PR filter, 404) and nothing the fixture suite already covers better.

### Answer to Q34

Use the @COMMIT-MESSAGES.md for seeding

## Q35 - Safety guard on the live test

The live test force-pushes `main` and deletes tags and releases. Run by mistake from the wrong clone, or with a mistyped repo name, it would do that to another repo.

a. **Hard-code the sandbox**: the live test resolves the repo with `gh repo view` and refuses unless it's exactly `JeremieLitzler/semantic-release-script-tests`. It always works in its own fresh clone in a temp dir, never in your working copy.
b. **Configurable target** through an environment variable, with the sandbox as the default.

➡️ Recommendation: **a**. There's one sandbox, and a destructive test shouldn't have a knob that points it somewhere else.

### Answer to Q35

(a)

## Q36 - Sandbox state after a failed live run

Q28's start-of-run reset already cleans any leftovers, so teardown only decides what you see after a failure.

a. **Always clean up** in `teardown`, pass or fail.
b. **Clean up on success only**: after a failure the tag, the release and `main` stay as they were, so you can inspect them on GitHub. The next run's reset clears them.

➡️ Recommendation: **b**. The evidence of a failure is most useful exactly where it happened, and the next run cleans it up anyway.

### Answer to Q36

(b)

## Q37 - The reference dataset and the rules it misses

The 14-commit dataset from `generate-dummy-changes.sh` covers the categories, `!` and body `BREAKING CHANGE`, issue vs no reference, and a non-existent number. It **doesn't** cover several rules the script already implements: a PR number being filtered out, dedupe by issue (added in `9283f36`), the `BREAKING-CHANGE` synonym, "BREAKING CHANGE" in prose not counting, and merge commits being ignored.

a. **Keep the 14 commits verbatim** as the reference dataset with its own golden notes, and cover each missing rule with a small, focused scenario of its own.
b. **Extend the reference dataset** with extra commits for the missing rules, so one golden file covers everything.

➡️ Recommendation: **a**. The reference golden stays readable, and when a focused scenario fails, its name says which rule broke. A single growing dataset makes every failure a diff through 20+ lines.

### Answer to Q37

If rules are already written into the script, (b) is the smart choice, isn't it?

## Q38 - Keeping the live suite out of a normal run

a. **`tests/live.bats` skips every test unless `LIVE=1`**, so a normal `bats tests/` shows them as skipped, with a note on how to run them.
b. **Move it to `tests/live/live.bats`**, which `bats tests/` doesn't load (it isn't recursive), and run it explicitly. This changes Q24's layout.

➡️ Recommendation: **a**. Seeing "3 skipped (set LIVE=1)" in every run is a reminder the live suite exists, and Q24's layout stays as settled.

### Answer to Q38

(a)

## Q39 - The human gates in this slice

Every test runs with `--yes`. The gates themselves (`release.sh:46-62`) read from `/dev/tty`, which a test can't drive reliably. While reading them I found something to note: where `/dev/tty` exists but can't be opened (common in CI), the `read` fails, the answer is empty, and the script prints "Stopped before ..." and **exits 0 without releasing**. A CI job that forgets `--yes` goes green having done nothing.

a. **Out of scope here**: only `--yes` paths are pinned, and the exit-0-on-no-terminal finding goes to candidate 04 (the outcome contract), where exit codes get redesigned anyway.
b. **Pin today's gate behaviour now**, with whatever tricks it takes to simulate a missing terminal.

➡️ Recommendation: **a**. It's an exit-code question, and candidate 04 is where the exit codes change. A characterization test written now would pin behaviour that's about to be redesigned.

### Answer to Q39

(a)
