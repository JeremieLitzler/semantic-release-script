# Grilling round v01 — fixture test harness for release.sh

Candidate 01 from the architecture review (`my-claude-conversations/summaries/2026-09-10-stranded-release-tags-single-trunk-migration/architecture-review-20260910-091844.html`). Today, testing needs 7 real GitHub issues (#2-#8), 14 dummy commits on `main`, and a human comparing notes with `COMMIT-MESSAGES.md` by eye. The proposal: each scenario builds a throwaway repo in a temp dir, with a bare local repo as `origin` and a fake `gh` first on `PATH`. Then it runs `release.sh` and checks the exit code, the notes, the tags and the `gh` calls.

What I found on this machine: bash 5.3 (Cygwin build), git 2.55, gh 2.100, jq 1.8.2 (Scoop), npm 11. `bats` and `shellcheck` are **not** installed. This repo has no `.github/workflows/`.

## Q1 - Test runner

What runs the test cases?

a. **bats-core**: the standard bash test framework. Each `@test` runs isolated in its own subshell, `run` captures the exit status and output, it has `setup`/`teardown`, and it prints TAP output that CI understands. It's a dev-only dependency: installed locally with Scoop or npm, and in CI with apt. `release.sh` itself stays dependency-free.
b. **Plain bash harness**: a `tests/run.sh` of about 60-100 lines that finds the case files, runs each in a subshell, and provides `assert_*` helpers. No dependency at all, but it rebuilds what bats already does (isolation, capturing status and output, reporting).
c. **ShellSpec**: a BDD-style framework. It's more powerful, but its DSL is less common and adds more to learn.

➡️ Recommendation: **a, bats-core**. The zero-dependency promise in the README is about `release.sh` at release time, not the dev loop. bats gives per-test isolation and status/output capture for free, which is exactly what a homemade harness would have to rebuild and then maintain.

### Answer to Q1

(a)

## Q2 - The `gh` seam

`release.sh` calls `gh` by name in four places: `auth status` (:127), `repo view` (:129), `api repos/<repo>/issues/<n>` (:268) and `release create` (:431). How do tests swap it?

a. **A fake `gh` script first on `PATH`.** `release.sh` doesn't change. The seam already exists, because the script runs `gh` by name.
b. **An injectable variable** such as `RELEASE_GH="${RELEASE_GH:-gh}"` in `release.sh`, pointed at the fake by the tests. It's more explicit, but it adds to the interface every vendoring repo sees and syncs.

➡️ Recommendation: **a, PATH shim**. The seam is real today with two adapters (the real `gh` and the fake), and it costs `release.sh` nothing. A variable would only widen the interface to serve the tests.

### Answer to Q2

(a)

## Q3 - The `origin` seam

`release.sh` runs `git fetch --tags origin` (:146) and `git push origin <tag>` (:411). How do tests stand in for GitHub?

a. **A bare repo in the test's temp dir**, set as the fixture repo's `origin`. Push and fetch really happen, so tests can check that a tag reached the remote, or that a failed push deleted the local tag (:411-414).
b. **No remote**: tests only use `--dry-run` / `--local`, and `origin` doesn't exist. Simpler, but the push path and the "fetch failed, warn only" path are never exercised.

➡️ Recommendation: **a, bare repo**. It's cheap, it runs the real git code paths, and it lets candidate 02 later stage the "tags not fetched" and "stranded tag on the remote" cases.

### Answer to Q3

(a)

## Q4 - What the first slice covers

The harness can land with different scopes:

a. **Characterization only**: tests that pin today's behaviour and all pass. That means the 14-commit dataset (classification, bump, notes sections, issue vs PR vs missing number, dedupe by issue), `--level`, `--since`/`--to` replay, the first release from `0.0.0`, `--notes`, `--changelog`, `--dry-run`/`--local` and the push path. The gap scenarios (stranded tag, shallow clone, non-monotonic version) are left to candidate 02, which writes them red first.
b. **Characterization + gap scenarios marked `skip`**: same as a, plus the gap repros written now but skipped with a pointer to candidate 02.
c. **Characterization + gap scenarios failing (red)**: the suite fails until candidate 02 lands.

➡️ Recommendation: **a**. This slice gives the suite a green baseline you can trust. Candidate 02 then starts with its own red tests, test-first, where the guard's design will shape how the scenario is staged. Skipped tests written before that design exists tend to get rewritten anyway.

### Answer to Q4

(a).

Note: I'd like a definition of stranded tag, shallow clone, non-monotonic version in the glossary.

## Q5 - Fate of the old test assets

Once their coverage is ported to fixtures, what happens to `tests/create-dummy-issues.sh`, `tests/generate-dummy-changes.sh`, `tests/dummy-issues.env`, `tests/CHANGELOG.md`, `COMMIT-MESSAGES.md` and `DUMMY-COMMITS-TARGET.md`?

a. **Delete them in the same change** that adds the harness. Their history goes when candidate 05 rewrites it.
b. **Keep them** next to the new harness as a manual end-to-end path.
c. **Move them** into an `archive/` folder.

➡️ Recommendation: **a, delete**. The fixture builder replaces them one-to-one, and keeping them means two sources of truth for the dataset. The dummy issues #2-#8 on GitHub are a separate cleanup that belongs with candidate 05.

### Answer to Q5

(a)

## Q6 - A live smoke test against real GitHub

The fake `gh` never proves that the real `gh` still answers the way `release.sh` expects (the `--jq` expressions, the 404 behaviour at :265-271, `--verify-tag`). Do we keep an opt-in test that talks to real GitHub?

a. **No live test.** A GitHub CLI behaviour change would only show up in a consumer's preview run.
b. **An opt-in live test** (e.g. `LIVE=1`) that runs `release.sh --dry-run` against a real repo and only checks that it exits 0 and resolves at least one issue title. It never runs in CI by default.
c. **A live test in CI** against a dedicated sandbox repo.

➡️ Recommendation: **b, opt-in, dry-run only**. It covers the one thing the fake can't (real `gh` behaviour) without creating anything remote. c would bring back a sandbox repo with dummy issues, which is exactly what this candidate removes.

### Answer to Q6

I created a new repo: https://github.com/JeremieLitzler/semantic-release-script-tests to test against.

## Q7 - How release notes are asserted

a. **Golden files**: one expected-notes Markdown file per scenario, compared with `diff`. The golden file replaces the `COMMIT-MESSAGES.md` table, and a failure shows a readable diff.
b. **Inline assertions**: `grep` for specific lines and sections inside each test.
c. **Golden files for full notes, inline assertions for everything else** (exit code, tags, version line, `gh` calls).

➡️ Recommendation: **c**. The notes are a document, so they're best reviewed whole. Exit codes and tags are single facts, so they're best checked inline.

### Answer to Q7

(c)

## Q8 - CI for this repo

This repo has no workflow. Do we add one that runs the suite?

a. **Yes**: `.github/workflows/test.yml` runs the suite on every pull request to `main` and every push to `main`, on `ubuntu-latest`.
b. **No**: the suite only runs locally.

➡️ Recommendation: **a**. `release.sh` runs unattended in publish mode in other repos, so the upstream should never merge a change without the suite passing. This is also the home for `shellcheck` later, if you want it.

### Answer to Q8

(a)

## Q9 - `release.sh` location

The review mentioned reorganising the repo. Consumers sync with `gh api repos/JeremieLitzler/semantic-release-script-testing/contents/release.sh?ref=<sha>` (see `transcript-cleaner-webapp/scripts/release/VENDORED.md`), and the migration playbook copies `release.sh` from the repo root.

a. **`release.sh` stays at the root.** Only `tests/` gets reorganised.
b. **Move it** (e.g. `src/release.sh` or `bin/release.sh`) and update VENDORED.md in every consumer plus the playbook.

➡️ Recommendation: **a, stays at the root**. Moving it breaks every consumer's sync command for no gain in testability.

### Answer to Q9

(b) with a agent-ready playbook to give to each consumer (2 at the moment).

## Q10 - Scraper artefacts in this slice

`FRENCH-GAS-STATION-SCRAPER.md`, `FRENCH-GAS-STATION-SCRAPER-RELEASES.md`, `FRENCH-GAS-STATION-SCRAPER-DRY-RUN-TERMINAL-OUTPUT.md` (~160 KB together) and `french-gas-station-replay-real-releases.sh` (hard-coded to a local path that no longer exists) are one-off records of a replay. Do they move in this slice?

a. **No, leave them to candidate 05**, which already decides what the cleaned-up history contains.
b. **Yes, move them out now** (destination decided in a later round).
c. **Turn the replay into a test**: a fixture that reproduces a few scraper releases.

➡️ Recommendation: **a**. This slice is about the test harness. The artefacts don't block it, and where they end up is tied to the history rewrite decision.

### Answer to Q10

(a)
