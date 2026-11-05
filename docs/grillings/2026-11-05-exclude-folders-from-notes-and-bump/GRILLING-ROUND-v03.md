# Grilling round v03 — leave out commits that only touch excluded paths

Issue: JeremieLitzler/semantic-release-script#107, on branch `issue-107-exclude-folders-from-notes-and-bump`.

## Settled in v02

- Q10: one argument only, as in Q1; the option is not meant to be repeated. What happens when it is repeated anyway is Q21.
- Q11: `|` is only a separator; entries are literal paths, no regex, no glob, `*` `?` `[` mean themselves; the README says to quote the value. Whether regex alternation comes later is to be grilled in its own issue (see below).
- Q12: an entry is anchored at the repository root and matched on whole path components; a trailing slash means the same; `docs/output` is not covered by `output`, the consumer lists it if it wants it.
- Q13: an entry may name a folder or a single file; it covers that exact path and everything under it.
- Q14: a commit touching no file is kept. Checked in the code: `release.sh` creates tags and GitHub releases only, never a commit, so the empty commit case can only come from a consumer's own history; the rule stays as a guard.
- Q15: renames count both the source and the destination as touched paths.
- Q16: `--check` accepts `--exclude-paths` and weighs the version on the commits that remain.
- Q17: the option is honoured on a resume; the retry must pass the same value.
- Q18: step 1 prints a `Commits excluded : N (only under: ...)` line and each excluded commit when the option is given; unchanged output without it (you edited the wording from "dropped" to "excluded", which Q24 carries into the vocabulary).
- Q19: no new key in the release summary.
- Q20: the release of the script is not part of the PR; it is cut on this repo once the grilling, the implementation and the validation are complete. Who cuts it and what "validation" covers is Q25.

## Reopened

Nothing.

## Notes

- Not done: the GitHub issue to grill regex alternation. My attempt to create it was denied by the permission classifier, so no issue exists yet. Tell me to retry (or create it yourself from the title "Grill whether --exclude-paths should accept regex alternation", label `needs-triage`), or I can write it as a file under `docs/` instead.
  - Retry, and if it fails again, provide me the details to create it myself.

## Q21 - Repeating the option anyway

Q10 settled that the option takes one argument. What happens on `--exclude-paths a --exclude-paths b`?

- A. A command-line mistake: exit `1` with "--exclude-paths can be given only once; list the paths with '|'".
- B. The last one wins, silently.
- C. Both are used.

➡️ Recommendation: A. It follows Q10 (one argument) and the issue's wording is answered by the `|` list. B silently stops applying `a`, which is worse than telling the caller; C reintroduces the second way in that you declined.

### Answer to Q21

A, obviously.

## Q22 - Values that are not a list of paths

Which values are refused, and with what exit code?

- A. Exit `1` (a mistake in the command line) when the value is empty or missing, when an entry is empty (`a||b`, `|a`, `a|`), is `.`, starts with `/`, or contains a `..` component. A leading `./` and trailing slashes are tolerated and normalised (`./output/` is `output`). Anything else is accepted, including an entry that matches nothing in the repository.
- B. Same as A, except an empty entry is ignored instead of refused.
- C. Nothing is validated; a bad entry simply matches nothing.

➡️ Recommendation: A. An entry that excludes everything (`.` or `/`) or reaches outside the repository would turn a typo into a release with no notes, and an empty entry is nearly always a stray `|` in a workflow that builds the value by concatenation. An entry that matches nothing is not refused, because a folder may exist only in later commits.

### Answer to Q22

A

## Q23 - Case

`--exclude-paths Output` is given and the commits touch `output/a.wav`.

- A. Case-sensitive, as git paths are: `Output` covers nothing.
- B. Case-insensitive.

➡️ Recommendation: A. Git treats the two as different paths on every platform; a consumer on Windows or macOS that names the wrong case gets what git would give it, and B would drop a commit under a path the consumer did not name on Linux.

### Answer to Q23

I'd go B, but I don't understand the Linux caveat.

## Q24 - Vocabulary for `CONTEXT.md`

The glossary needs terms for what this adds, and you wrote "excluded" in the output line. Proposed entries:

- **Excluded path**: an entry of the `--exclude-paths` list: a folder or a file, relative to the repository root, covering itself and everything under it.
- **Excluded commit**: a commit whose touched files are all under excluded paths (at least one file, renames counting both ends). It counts neither in the notes nor in the bump, and a range made only of them is **Nothing to release**.

The issue's "dropped" and "left out" are listed as terms to avoid.

- A. Take these two terms and the avoid list.
- B. Other names (say which).

➡️ Recommendation: A. "Excluded" is the word in the option name and in the output line you chose, so one word runs from the command line to the log to the glossary. The entries stay free of implementation details.

### Answer to Q24

A

## Q25 - Who cuts the release, and what validation covers

You said the release is the one this repo will have once the grilling, implementation and validation are complete. Proposed definition of done for the issue:

1. The PR is merged after the bats suite passes (in WSL) with new tests for each acceptance criterion and the golden files.
2. Validation: a `--dry-run` with `--exclude-paths 'output|sources'` against a clone of `coge-audio-meditation-guides`, read-only, to see the notes lose the commits that only touch those folders.
3. You push the `release/*` branch (or dispatch `publish`) to cut the release, and the issue is closed when it exists. I do not do it myself.

- A. That definition.
- B. Skip the dry run on `coge-audio-meditation-guides`: the bats tests are the validation.
- C. Other (say what).

➡️ Recommendation: A. The consumer is the reason the option exists, and a dry run against its real history is the only check that its `output/` and `sources/` commits come out as expected; it writes nothing. Cutting the release is outward-facing and stays yours.

### Answer to Q25

A
