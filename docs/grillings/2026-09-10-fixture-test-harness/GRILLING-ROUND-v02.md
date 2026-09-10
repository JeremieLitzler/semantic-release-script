# Grilling round v02 — fixture test harness for release.sh

## Settled in v01

- Q1: the test runner is **bats-core**. It's a dev-only dependency; `release.sh` itself stays dependency-free.
- Q2: tests swap `gh` with a **fake `gh` script first on `PATH`**. `release.sh` gets no new variable for this.
- Q3: each test's `origin` is a **bare repo in its temp dir**, so push and fetch really run.
- Q4: this slice is **characterization only**: every test pins today's behaviour and passes. Stranded tag, shallow clone and non-monotonic version scenarios come with candidate 02, red first. As you asked, those three terms are now defined in a new root `CONTEXT.md`, with the terms they lean on (version tag, release, baseline, bump, trunk, twin, replay, consumer, vendored copy). Correct any definition in place.
- Q5: the old test assets (`tests/create-dummy-issues.sh`, `tests/generate-dummy-changes.sh`, `tests/dummy-issues.env`, `tests/CHANGELOG.md`, `COMMIT-MESSAGES.md`, `DUMMY-COMMITS-TARGET.md`) are **deleted in the same change** that adds the harness. Dummy issues #2-#8 are cleaned up with candidate 05.
- Q7: notes are checked against **golden files**. Exit code, tags, the version line and `gh` calls are checked **inline**.
- Q8: a **`.github/workflows/test.yml`** runs the suite on every PR to `main` and every push to `main`, on `ubuntu-latest`.
- Q9: **`release.sh` moves out of the repo root** in this slice, and an **agent-ready playbook** takes each of the 2 consumers (`transcript-cleaner-webapp`, `french-gas-stations-scraper`) through the move.
- Q10: the scraper artefacts stay where they are; **candidate 05** decides what happens to them.

## Reopened

- Q6: you answered by creating `JeremieLitzler/semantic-release-script-tests` to test against. That rules out option a (no live test): there will be a live test, against that repo. It doesn't say _when_ it runs or _what_ it does to the repo, so those two decisions come back as Q6b and Q6c. For reference, the sandbox is public, its trunk is `main`, and it holds only `Initial commit` (`LICENSE`, `README.md`), with no issues, tags or releases.

## Q6b - When the live test runs

The live test runs `release.sh` inside a clone of `semantic-release-script-tests` with the real `gh`.

a. **Opt-in, locally**: something like `LIVE=1 bats tests/live.bats`, run by hand, typically before a consumer sync. It needs no secret, because your own `gh` login is used.
b. **In CI on every PR**: needs a PAT (or GitHub App) secret with write access to the sandbox, because a workflow's `GITHUB_TOKEN` only covers its own repo. Two PRs running at once share one sandbox and can collide.
c. **In CI, manual or scheduled** (`workflow_dispatch` and/or weekly): catches changes in `gh` behaviour without any PR. It needs the same PAT secret as b, but avoids PR collisions.

➡️ Recommendation: **a**. The point is to catch a `gh` behaviour change before it reaches a consumer, and the moment that matters is right before a sync. b and c bring a long-lived write token to manage for a repo only you touch.

### Answer to Q6b

I'd say (a). It'd be used to run integration tests for `release.sh`.

I created the repo because I though it'd help to have a real github repo to run integration tests against.

Am I correct?

## Q6c - What the live test does to the sandbox

a. **Dry run only**: `release.sh --yes --dry-run`. It exercises `gh auth status`, `gh repo view` and `gh api .../issues/<n>`, but never `git push` or `gh release create --verify-tag`.
b. **Full publish, then clean up**: `release.sh --yes` creates and pushes a real tag and a real release, the test checks them through `gh`, then deletes the release and the tag. All four `gh` calls and the push run for real, which is the path consumers run unattended.

➡️ Recommendation: **b**. Now that the sandbox exists only for this, publishing there is harmless, and `release create --verify-tag` is the one call a consumer's publish job depends on that a dry run never touches. How the sandbox is seeded and cleaned up depends on this answer, so it comes next round.

### Answer to Q6c

(b)

## Q11 - Where `release.sh` moves to

a. **`scripts/release/release.sh`**: the same path consumers already vendor it to. A sync becomes "copy `scripts/release/` across" (minus the consumer's own `VENDORED.md`), and `check-setup.sh` from candidate 03 can sit beside it in both places.
b. **`src/release.sh`**
c. **`bin/release.sh`**

➡️ Recommendation: **a**. Identical paths upstream and downstream remove a translation step from every sync, and give candidate 03's second script an obvious home.

### Answer to Q11

(a)

## Q12 - Where the consumer playbook lives

a. **In this repo** (e.g. `docs/consumers/SYNC-PLAYBOOK.md`), versioned with the script. A consumer's `VENDORED.md` can point to it at the pinned commit, so the instructions always match the file being synced.
b. **In `my-claude-conversations/prompts/`**, next to `2026-09-09-single-trunk-release-migration/RELEASE-MIGRATION.md`.

➡️ Recommendation: **a**. The migration playbook is a one-off. A sync playbook applies every time the script changes, so it belongs with what it syncs.

### Answer to Q12

(b) because `my-claude-conversations` is guaranteed to exist on all computers I use.

## Q13 - When the consumers run the playbook

The consumers keep working in the meantime: they run their own vendored copy, and the pinned `de0a43a` keeps serving `release.sh` at the old path until candidate 05 rewrites the history.

a. **Right after this slice merges.**
b. **Once, after candidate 05's history rewrite**: the path, the repo name and the pinned commit all change in a single sync.

➡️ Recommendation: **b**. Syncing after this slice and again after the rewrite means two reviewed syncs per consumer. One sync after 05 covers everything, and picks up candidates 02-04's guards at the same time.

### Answer to Q13

(b)

## Q14 - Repo name in the playbook

The consumers' `VENDORED.md` and the migration playbook still name `JeremieLitzler/semantic-release-script-testing`. GitHub redirects the old name for now, but the redirect breaks if a new repo ever takes that name.

a. **The playbook also switches every reference to `JeremieLitzler/semantic-release-script`.**
b. **Leave the old name**, and rely on the redirect.

➡️ Recommendation: **a**. It costs one extra line in a sync that happens anyway.

### Answer to Q14

(a)

## Q15 - How the fake `gh` handles `--jq`

`release.sh` passes `--jq` expressions to `gh repo view` and `gh api`.

a. **The fake returns the post-jq result directly**, hard-coded for each call. It's simple, but if `release.sh` changes an expression, the fake still answers the old way and the tests stay green.
b. **The fake stores raw GitHub-shaped JSON and pipes it through real `jq` with the expression it was given.** A changed or broken expression then fails the tests. `jq` becomes a second dev dependency; it's on `ubuntu-latest` and on your machine.

➡️ Recommendation: **b**. The `--jq` expressions are part of how `release.sh` talks to GitHub (the PR filter `has("pull_request")` decides issue vs PR), so the fake should run them, not ignore them.

### Answer to Q15

seems related to Q6b.

## Q16 - How a test declares the GitHub state

a. **Helper calls inside each test**, e.g. `given_issue 2 "Export the orders as CSV"` and `given_pull_request 9`, written to the test's own state dir. Any number not declared answers like real `gh` does for a 404: an error payload on stdout and a non-zero exit. The reference dataset declares its issues in one shared helper.
b. **One static issues file** shared by all tests.

➡️ Recommendation: **a**. Each test shows the GitHub state it depends on, and tests can't break each other through a shared file.

### Answer to Q16

seems related to Q6b

## Q17 - Recording `gh` calls

a. **The fake logs every call** (the arguments, plus a copy of the `--notes-file` for `release create`) to the test's state dir, so tests can check that `release create` was called with the right tag, title and notes, or not called at all under `--dry-run` / `--local`.
b. **No call log**: tests only look at stdout and git state.

➡️ Recommendation: **a**. "No release was created" under `--dry-run` and `--local` is behaviour worth pinning, and it can only be seen from the call log.

### Answer to Q17

seems related to Q6b

## Q18 - `--verify-tag` in the fake

Real `gh release create --verify-tag` refuses when the tag isn't on the remote.

a. **The fake checks the bare `origin`** and fails the same way when the tag isn't there.
b. **The fake always succeeds.**

➡️ Recommendation: **a**. It's a few lines in the fake, and it keeps the push-then-release order honest in tests.

### Answer to Q18

seems related to Q6b

## Q19 - Commit hashes in golden files

Notes link commits by hash, e.g. `([14de0b0](https://github.com/.../commit/14de0b0...))`.

a. **Stable hashes**: the fixture builder fixes the author and committer name, email and dates for every commit, and sets `core.autocrlf=false` so Windows line endings can't change a blob. The same dataset then always produces the same hashes, and golden files hold them literally.
b. **Placeholders**: the test replaces every hash with `<sha>` before the diff. Goldens survive a change to the dataset, but no test proves a link points to the right commit.

➡️ Recommendation: **a**. The link is part of the notes, and checking it points to the right commit is part of the job. Changing the dataset means regenerating the goldens, which Q20 makes a single command.

### Answer to Q19

(a)

## Q20 - Regenerating golden files

a. **`UPDATE_GOLDEN=1 bats tests/`** rewrites every golden file from the actual output. The diff is then reviewed in git like any other change.
b. **Goldens are only edited by hand.**

➡️ Recommendation: **a**. A hand-edited golden drifts. With a, git becomes the review tool.

### Answer to Q20

(a)

## Q21 - The date in `--changelog` output

`--changelog` writes today's date (`## v1.0.0 (2026-09-10)`), so a golden file for it would go stale every day.

a. **The test swaps the date for a placeholder before the diff**, and separately checks that it matches `YYYY-MM-DD`.
b. **A fake `date` on `PATH`** returns a fixed day.

➡️ Recommendation: **a**. `date` isn't a seam worth faking: one line of substitution covers it, and a fake `date` would also change `mktemp` and anything else that reads the clock.

### Answer to Q21

(a)

## Q22 - Assertion helpers

a. **bats-assert + bats-support**: `assert_success`, `assert_output --partial`, `assert_line`, with readable failure messages. That's two more small bash libraries.
b. **Our own few helpers** in `tests/helpers/`.

➡️ Recommendation: **a**. Nothing to maintain, and they're what any bats reader expects.

### Answer to Q22

(a)

## Q23 - How bats and its libraries are installed

bats-core isn't in your enabled Scoop buckets. It's available as the npm package `bats`, by cloning and running its `install.sh`, or in CI through `bats-core/bats-action`.

a. **Git submodules** under `tests/libs/` (bats-core, bats-support, bats-assert): the versions are pinned in the repo and identical locally and in CI, with no package manager. A clone needs `git submodule update --init`.
b. **Installed outside the repo**: npm or a manual clone locally, `bats-core/bats-action` in CI. Nothing in the repo, but local and CI versions can drift.

➡️ Recommendation: **a**. A pinned, package-manager-free toolchain fits the project, and the one-time `submodule update` goes in the README.

### Answer to Q23

(a)

## Q24 - Test file layout

a. **One `.bats` file per behaviour area**: `tests/version.bats` (bump, baseline, first release, `--level`), `tests/notes.bats` (sections, issue/PR/missing number, dedupe by issue), `tests/replay.bats` (`--since`/`--to`), `tests/publish.bats` (push, `--dry-run`, `--local`, `--verify-tag`), `tests/options.bats` (`--notes`, `--changelog`, bad arguments). Plus `tests/helpers/` (fixture builder, fake `gh`), `tests/golden/`, and `tests/live.bats` for Q6b.
b. **One `.bats` file per scenario.**

➡️ Recommendation: **a**. Areas match how `release.sh` is read, and a failing file name tells you which behaviour broke.

### Answer to Q24

(a)

## Q25 - Supported local environments

Your bash here reports `x86_64-pc-cygwin`. CI will be `ubuntu-latest`.

a. **Both**: the suite must pass on your Windows bash and on CI. CI is the reference when they disagree.
b. **CI only**: local Windows runs are best effort.

➡️ Recommendation: **a**. You'll mostly run it locally, and a suite that only passes in CI gets skipped. The Windows traps are known: line endings (Q19), temp paths and `/dev/tty`, which `--yes` avoids.

### Answer to Q25

(a)
