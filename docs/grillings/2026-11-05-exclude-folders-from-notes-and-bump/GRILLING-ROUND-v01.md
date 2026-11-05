# Grilling round v01 — leave out commits that only touch excluded folders

Issue: JeremieLitzler/semantic-release-script#107, on branch `issue-107-exclude-folders-from-notes-and-bump`.

Facts found in the repo, so you do not have to look them up:

- `scan_commits` builds `COMMITS` with `git log --no-merges --format=%H "$RANGE"`. `classify_commits` then classifies each one, `next_version` computes the bump from the categories, and the notes are built from the same arrays. An empty `COMMITS` stops with exit `2` ("no commit to release in range"). The setup report (`--check`) and a real run share `scan_commits`.
- `--check` currently refuses every option collected in `RELEASE_OPTIONS` (`--yes`, `--dry-run`, `--local`, `--level`, `--notes`, `--changelog`, `--summary`): "--check accepts only --trunk, --to, --since and --level-from". `--dry-run`, `--local`, `--to` and `--since` already work with whatever `scan_commits` returns.
- On a resume (a half-published release), the notes are rebuilt over the range the tag was cut on, through the same `scan_commits`. `--level` is ignored on a resume with a warning.
- `CONTEXT.md` has no term for this yet. Vocabulary in play: **Bump**, **Nothing to release**, **Resume**, **Preview**, **Consumer**.
- Option style today: long options with a value (`--since <ref>`, `--notes <path>`); none is repeatable yet.

## Q1 - Option name and shape

The issue leaves the name to this repo. It must be repeatable and name folders.

- A. `--exclude-folder <path>`, repeated: `--exclude-folder output --exclude-folder sources`.
- B. `--exclude-path <path>`, repeated.
- C. `--exclude-folders <a,b>`, one occurrence with a comma-separated list.
- D. Something else (say what).

➡️ Recommendation: A. The issue says "folders", so the name says what it takes. Repeating the option avoids a separator that a folder name could contain, and a consumer's workflow can build the arguments with a loop. "Path" (B) would suggest files or globs are accepted.

### Answer to Q1

D. `--exclude-paths <a|b>`
