# Grilling round v03 — fixture test harness for release.sh

## Settled in v02

- Q6b: the live test is **opt-in and run locally** (e.g. `LIVE=1`), using your own `gh` login, with no CI secret. Your question about it ("Am I correct?") gets its answer in Q26.
- Q6c: the live test does a **full publish in the sandbox and then cleans up**: a real tag, a real release, checked through `gh`, then both deleted.
- Q11: `release.sh` moves to **`scripts/release/release.sh`**, the same path consumers vendor it to.
- Q12: the consumer playbook lives in **`my-claude-conversations/prompts/`**, because that repo exists on every computer you use.
- Q13: consumers run the playbook **once, after candidate 05's history rewrite**, so the path, repo name and pinned commit change in a single sync.
- Q14: the playbook **switches every reference** from `semantic-release-script-testing` to `JeremieLitzler/semantic-release-script`.
- Q19: the fixture builder uses a **fixed author, committer and dates, plus `core.autocrlf=false`**, so hashes are stable and golden files hold them literally.
- Q20: **`UPDATE_GOLDEN=1`** regenerates the golden files, and the diff is reviewed in git.
- Q21: the `--changelog` date is **replaced by a placeholder before the diff**, and checked separately against `YYYY-MM-DD`.
- Q22: assertions use **bats-assert + bats-support**.
- Q23: bats-core, bats-support and bats-assert come in as **git submodules under `tests/libs/`**.
- Q24: **one `.bats` file per behaviour area** (`version`, `notes`, `replay`, `publish`, `options`), plus `tests/helpers/`, `tests/golden/` and `tests/live.bats`.
- Q25: the suite must pass **on your Windows bash and on CI**. CI is the reference when they disagree.

## Reopened

- Q15, Q16, Q17, Q18: each was answered "seems related to Q6b". They aren't, and Q26 explains why: they're about the fake `gh` in the offline suite, which never touches the sandbox. The four decisions are still open, so they're re-asked verbatim as Q15b-Q18b.

## Q26 - Two suites, two jobs (your "Am I correct?" in Q6b)

Yes, you're correct: a real GitHub repo is the right place for integration tests. But it complements the fake `gh` rather than replacing it. There are two suites:

- **The fixture suite** (`version`, `notes`, `replay`, `publish`, `options`) is offline and fast. It has dozens of scenarios, each in a throwaway repo with a fake `gh` (Q2) and a bare `origin` (Q3). It runs in CI (Q8) and locally, and it never touches GitHub. **Q15-Q18 are about how its fake `gh` behaves.** ✅
- **The live suite** (`tests/live.bats`) is a handful of tests in `semantic-release-script-tests` with the real `gh`, opt-in (Q6b). Its job is to prove the fake still tells the truth: that real `gh` handles the `--jq` expressions, the 404 on a missing issue, and `--verify-tag` the way the fake assumes. When `gh` changes, the live suite breaks first, and you then fix the fake to match. ✅

The sandbox can't carry every scenario on its own. Each one would need real issues and real pushes, and would be slow, need a network and a login, and couldn't run in CI without the PAT that Q6b turned down.

a. **Two suites** as above. This is what Q2, Q3, Q6b and Q8 already imply.
b. **Sandbox only**: every scenario runs against the real repo. That reopens Q2, Q3, Q8 and Q15-Q25.

➡️ Recommendation: **a**. The fixture suite gives speed and coverage, and the live suite keeps the fake honest.

### Answer to Q26

(a)

## Q15b - How the fake `gh` handles `--jq`

`release.sh` passes `--jq` expressions to `gh repo view` and `gh api`.

a. **The fake returns the post-jq result directly**, hard-coded for each call. It's simple, but if `release.sh` changes an expression, the fake still answers the old way and the tests stay green.
b. **The fake stores raw GitHub-shaped JSON and pipes it through real `jq` with the expression it was given.** A changed or broken expression then fails the tests. `jq` becomes a second dev dependency; it's on `ubuntu-latest` and on your machine.

➡️ Recommendation: **b**. The `--jq` expressions are part of how `release.sh` talks to GitHub (the PR filter `has("pull_request")` decides issue vs PR), so the fake should run them, not ignore them.

### Answer to Q15b

(b)

## Q16b - How a test declares the GitHub state

a. **Helper calls inside each test**, e.g. `given_issue 2 "Export the orders as CSV"` and `given_pull_request 9`, written to the test's own state dir. Any number not declared answers like real `gh` does for a 404: an error payload on stdout and a non-zero exit. The reference dataset declares its issues in one shared helper.
b. **One static issues file** shared by all tests.

➡️ Recommendation: **a**. Each test shows the GitHub state it depends on, and tests can't break each other through a shared file.

### Answer to Q16b

(a)

## Q17b - Recording `gh` calls

a. **The fake logs every call** (the arguments, plus a copy of the `--notes-file` for `release create`) to the test's state dir, so tests can check that `release create` was called with the right tag, title and notes, or not called at all under `--dry-run` / `--local`.
b. **No call log**: tests only look at stdout and git state.

➡️ Recommendation: **a**. "No release was created" under `--dry-run` and `--local` is behaviour worth pinning, and it can only be seen from the call log.

### Answer to Q17b

(a)

## Q18b - `--verify-tag` in the fake

Real `gh release create --verify-tag` refuses when the tag isn't on the remote.

a. **The fake checks the bare `origin`** and fails the same way when the tag isn't there.
b. **The fake always succeeds.**

➡️ Recommendation: **a**. It's a few lines in the fake, and it keeps the push-then-release order honest in tests.

### Answer to Q18b

(a)

## Q27 - Scope of the consumer playbook

Each consumer's `VENDORED.md` already has its own "Syncing a deliberate update" steps (fetch the upstream file by commit, diff, review, replace, re-apply the local hunk, re-pin, preview).

a. **A standing sync playbook**: one file in `my-claude-conversations/prompts/` that an agent follows for _every_ sync. Its first run also handles this move (the new path, the new repo name, re-pinning after the rewrite). Each consumer's `VENDORED.md` shrinks to its provenance plus a pointer to the playbook.
b. **A one-off move playbook** that only covers this move. Later syncs keep following each consumer's own `VENDORED.md` steps.

➡️ Recommendation: **a**. The sync steps are the same in every consumer, so one copy gives locality: a fix to the procedure lands once. A one-off playbook would sit next to two drifting copies of the same procedure.

### Answer to Q27

(a)

## Q28 - How the sandbox's commits are staged for a live run

`release.sh` tags a commit on the branch it runs from. Once candidate 03 lands, a release from anything but the trunk will be refused.

a. **Append to the sandbox's `main` on every run**: new commits each time, so `main` grows forever. It's the same problem as this repo's dummy history, just moved to a dedicated repo.
b. **A throwaway branch per run** (`live/<timestamp>`), deleted afterwards. `main` stays clean, but the release is cut off the trunk, which is exactly the setup candidate 03 will refuse.
c. **Reset `main` at the start of each run**: force-push `main` back to `Initial commit`, push a small fixed dataset, run `release.sh --yes`, check, then delete the release and tag and reset `main` again. Every run starts from a known state, and the release is cut from the trunk.

➡️ Recommendation: **c**. It's the only option where the live run uses a supported setup and the sandbox never accumulates anything. Force-pushing is safe there, because the sandbox has no ruleset and nobody else uses it.

### Answer to Q28

(c)

## Q29 - Issues and pull request in the sandbox

The live test should see an issue title resolve, a PR number get filtered out, and a missing number fall back to a commit link. The sandbox has none of these yet.

a. **Seed once, keep forever**: a one-time setup creates a couple of issues and one pull request (opened from a branch and closed without merging, so the number exists). The live dataset refers to them by number, and the test checks they still exist before running.
b. **Create them on every run, then close them**: issue numbers climb forever and the closed issues pile up.

➡️ Recommendation: **a**. The issues are fixed reference data, not something a run produces, and numbers the test can rely on are what keep its assertions simple.

### Answer to Q29

(a)

## Q30 - A root `release.sh` after the move

After `release.sh` moves to `scripts/release/release.sh`, should something stay at the root?

a. **Nothing**: the root `release.sh` is removed. Consumers fetch by pinned commit, and the old commit still has the file at the root until the rewrite.
b. **A stub** at the root that prints the new path and exits non-zero.

➡️ Recommendation: **a**. Nobody runs the root copy from `main`: consumers vendor by commit, and the only local caller (the scraper replay script) is already broken and belongs to candidate 05.

### Answer to Q30

(a)
