# Grilling summary — fixture test harness for release.sh

Session: 2026-09-10, rounds v01-v06. Source: candidate 01 of the architecture review in `my-claude-conversations/summaries/2026-09-10-stranded-release-tags-single-trunk-migration/architecture-review-20260910-091844.html`.

## Shared understanding

Until now, testing `release.sh` meant creating 7 throwaway issues on this repo's real GitHub tracker, committing 14 dummy commits onto `main`, and comparing the dry-run notes by eye against `COMMIT-MESSAGES.md`. That test data sits in the product's own history, and nothing checks it automatically. This slice replaces all of it with two bats suites and moves the script to the path consumers already use.

**The fixture suite** is the main one. Each test builds a throwaway git repo in a temp dir, with a bare repo in the same temp dir as `origin`. It then runs `release.sh --yes` with a fake `gh` first on `PATH`, and checks what comes back. `release.sh` gets no new variable for the tests; its existing call to `gh` by name is the seam. The fake is deliberately faithful where fidelity catches bugs:

- It keeps raw GitHub-shaped JSON and runs the real `--jq` expression through `jq`, so a broken expression fails the tests.
- It answers an undeclared issue number the way a real 404 does.
- Its `release create --verify-tag` refuses when the tag isn't in the bare `origin`.
- It logs every call, so "nothing was published" under `--dry-run` and `--local` can be checked.

Each test declares the GitHub state it needs with helper calls (`given_issue`, `given_pull_request`). The fixture builder fixes the author, committer and dates, and sets `core.autocrlf=false`, so hashes are stable on Windows and Linux alike. Notes are checked against golden files that hold those hashes literally, and `UPDATE_GOLDEN=1` regenerates them for review in git. The `--changelog` date is replaced with a placeholder before the diff and checked separately. Exit codes, tags, the version line and `gh` calls are checked inline with `bats-assert`.

`bats-core`, `bats-support` and `bats-assert` are pinned as git submodules under `tests/libs/`, and `jq` is the only other dev dependency. The suite is split by behaviour area (`version`, `notes`, `replay`, `publish`, `options`). It must pass on your Windows bash and on `ubuntu-latest` through a new `.github/workflows/test.yml` (every PR to `main`, every push to `main`), and CI is the reference when they disagree.

**The reference dataset** is the 14 commits that `COMMIT-MESSAGES.md` recorded, carried over verbatim, with extra commits **appended at the end** for the notes rules the original set missed: a PR reference, dedupe by issue, the `BREAKING-CHANGE:` synonym, "BREAKING CHANGE" in prose not counting, and a merge commit being ignored. One golden file then works as the readable spec of every notes rule. That's the role `COMMIT-MESSAGES.md` played, and it's why the dataset was extended rather than split (Q37b), a reversal of my first recommendation once the live suite started sharing the dataset. Bump levels (patch-only, minor-only), `--level`, replay, the first release and the options can't all live in one range, so they get focused scenarios. This slice is characterization only. Every test pins today's behaviour and passes. Stranded tags, shallow clones and non-monotonic versions (now defined in `CONTEXT.md`) are left to candidate 02, which writes them red first.

**The live suite** (`tests/live.bats`) came from you creating `JeremieLitzler/semantic-release-script-tests`. It doesn't replace the fake, it keeps it honest: a handful of opt-in tests (`LIVE=1`, skipped otherwise, never in CI, no secret) run a full publish against the sandbox with the real `gh`, then clean up. Each run:

1. refuses any repo but the sandbox, and works in a fresh clone in a temp dir;
2. resets the sandbox's `main` to `Initial commit` and pushes the reference dataset;
3. releases with `--yes` (always `v1.0.0`, because of the dataset's `feat!`);
4. normalises the repo name and hashes on both sides, then diffs the notes against the reference golden;
5. deletes the release and tag and resets `main`, but only on success, so a failure stays visible on GitHub until the next run's reset.

The sandbox's issues and closed PR are seeded once by a committed, idempotent seed script. It writes one number map, holding each item's number and plain title, that both suites read. Commit subjects, numbers and titles are therefore identical in both suites.

**The reorganisation**:

- `release.sh` moves to `scripts/release/release.sh`, with nothing left at the root. You overrode my recommendation to keep it at the root, so upstream and consumers share one path.
- The old test assets are deleted: `tests/create-dummy-issues.sh`, `tests/generate-dummy-changes.sh`, `tests/dummy-issues.env`, `tests/CHANGELOG.md`, `COMMIT-MESSAGES.md` and `DUMMY-COMMITS-TARGET.md`. Their dataset lives on in the fixture builder, with plain issue titles instead of the old `feat:` markers.
- The scraper artefacts and the dummy issues #2-#8 are left for candidate 05.
- The two consumers (`transcript-cleaner-webapp`, `french-gas-stations-scraper`) aren't touched now. This slice writes a standing sync playbook at `my-claude-conversations/prompts/2026-09-10-release-sh-sync/SYNC-PLAYBOOK.md`. It's in that repo because it exists on every computer you use, and it switches the repo name to `JeremieLitzler/semantic-release-script`. Candidates 02-05 amend it, and each consumer runs it once, after candidate 05's history rewrite, so the path, repo name and pin change in a single sync.

## Decision index

- Q1 (v01): bats-core is the test runner; dev-only, `release.sh` stays dependency-free.
- Q2 (v01): a fake `gh` first on `PATH`; no injectable variable in `release.sh`.
- Q3 (v01): a bare repo in each test's temp dir is `origin`.
- Q4 (v01): characterization only; gap scenarios go to candidate 02, red first. Glossary terms added to `CONTEXT.md`.
- Q5 (v01): old test assets deleted in the same change; dummy issues #2-#8 go with candidate 05.
- Q7 (v01): golden files for notes; inline assertions for exit code, tags, version line and `gh` calls.
- Q8 (v01): `.github/workflows/test.yml` on PRs and pushes to `main`, `ubuntu-latest`.
- Q9 (v01): `release.sh` moves out of the root, with an agent-ready playbook for the 2 consumers.
- Q10 (v01): scraper artefacts are left to candidate 05.
- Q6b (v02): the live suite is opt-in and local, with no CI secret.
- Q6c (v02): the live run does a full publish in the sandbox, then cleans up.
- Q11 (v02): new path `scripts/release/release.sh`.
- Q12 (v02): the playbook lives in `my-claude-conversations/prompts/`.
- Q13 (v02): consumers run the playbook once, after candidate 05.
- Q14 (v02): the playbook switches every reference to `JeremieLitzler/semantic-release-script`.
- Q19 (v02): fixed identity, dates and `core.autocrlf=false`; literal hashes in goldens.
- Q20 (v02): `UPDATE_GOLDEN=1` regenerates goldens.
- Q21 (v02): the changelog date is replaced by a placeholder, and its format checked separately.
- Q22 (v02): bats-assert + bats-support.
- Q23 (v02): git submodules under `tests/libs/`.
- Q24 (v02): one `.bats` file per behaviour area, plus `helpers/`, `golden/`, `live.bats`.
- Q25 (v02): must pass on your Windows bash and on CI; CI is the reference.
- Q26 (v03): two suites: offline fixtures for coverage, live sandbox to keep the fake honest.
- Q15b (v03): the fake pipes raw JSON through real `jq` with the given `--jq`.
- Q16b (v03): per-test `given_*` helper calls; an undeclared number answers like a 404.
- Q17b (v03): the fake logs every call, including the notes file.
- Q18b (v03): the fake's `--verify-tag` checks the bare `origin`.
- Q27 (v03): a standing sync playbook; consumers' `VENDORED.md` shrinks to provenance plus a pointer.
- Q28 (v03): each live run resets the sandbox's `main` to `Initial commit` before and after.
- Q29 (v03): the sandbox's issues and PR are seeded once and kept.
- Q30 (v03): nothing stays at the root after the move.
- Q31 (v04): the playbook's path is `prompts/2026-09-10-release-sh-sync/SYNC-PLAYBOOK.md`.
- Q32 (v04): the playbook is written in this slice and amended by candidates 02-05.
- Q33 (v04): a committed, idempotent seed script.
- Q34 (v04): the live run uses the reference dataset, not a separate small seed.
- Q35 (v04): the live test only ever targets the sandbox, in a fresh temp clone.
- Q36 (v04): after a failed live run, the sandbox is left for inspection.
- Q38 (v04): `live.bats` skips unless `LIVE=1`.
- Q39 (v04): human gates are out of scope; the exit-0-without-a-terminal finding goes to candidate 04.
- Q40 (v05): extending the dataset is justified by the live suite sharing it, not by readability.
- Q37b (v05): the reference dataset is extended by appending commits for the missing rules.
- Q41 (v05): one committed number map shared by both suites.
- Q42b (v06): plain issue titles in the seed.
- Q43 (v06): the live notes are normalised (repo name, hashes) and diffed against the reference golden.

Superseded: Q6 by Q6b and Q6c, after you answered it by creating the sandbox. Q15-Q18 by Q15b-Q18b, after they were answered "seems related to Q6b" and Q26 separated the two suites. Q37 by Q37b, after your question was answered in Q40. Q42 by Q42b, after your "(a)" and your edit to `create-dummy-issues.sh` disagreed. My proposed small seed in Q34 was replaced by the reference dataset.

## Decided without grilling: object before implementation

- **Submodule versions**: bats-core, bats-support and bats-assert are pinned to their latest release tags at implementation time.
- **Unused issue**: the seed skips the old issue #4 ("dark mode for the dashboard"), since no commit references it. The dedupe-by-issue commits reuse an existing feature issue rather than a new one.
- **Fake repo name**: the fixture suite's fake `gh repo view` answers with a placeholder repo name (e.g. `fixture-owner/fixture-repo`), which Q43's normalisation replaces.
- **File names**: the seed script is `tests/live/seed-sandbox.sh` and the number map is `tests/fixtures/reference-issues.env`.
- **Bump-level scenarios**: the patch-only and minor-only scenarios may run on prefixes of the reference dataset (as the old README rehearsal did) rather than on separate commits.
- **Docs**: README's "Testing it" and usage paths are rewritten for the new layout, and `AGENTS.md` gets a one-line pointer on how to run the suites.
- **CI setup**: CI checks out with submodules and relies on the `jq` preinstalled on `ubuntu-latest`. The live suite shows as skipped there.
- **Commit scope**: `CONTEXT.md` and this grilling folder are committed with the slice.
