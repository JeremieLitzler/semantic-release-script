# Grilling round v04 — leave out commits that only touch excluded paths

Issue: JeremieLitzler/semantic-release-script#107, on branch `issue-107-exclude-folders-from-notes-and-bump`.

## Settled in v03

- Q21: `--exclude-paths` given twice is a command-line mistake, exit `1`.
- Q22: exit `1` when the value is empty or missing, when an entry is empty, is `.`, starts with `/` or has a `..` component; a leading `./` and trailing slashes are normalised; an entry that matches nothing is accepted.
- Q24: the terms **Excluded path** and **Excluded commit** go into `CONTEXT.md`, with "dropped" and "left out" as terms to avoid.
- Q25: definition of done: the PR is merged after the bats suite passes with a test per acceptance criterion; a read-only `--dry-run --exclude-paths 'output|sources'` against a clone of `coge-audio-meditation-guides` validates it; you cut the release, I do not.

## Reopened

- Q23 (case): your answer was "I'd go B, but I don't understand the Linux caveat", which is a question and a lean, not a decision. The caveat is explained in Q26, and the decision is re-asked as Q27.

## Notes

- The GitHub issue to grill regex alternation is still not created. I retried and the permission classifier denied it again, with the reason "External System Writes", so I stopped there. To create it yourself:
  - Title: `Grill whether --exclude-paths should accept regex alternation`
  - Label: `needs-triage`
  - Body: `Spun out of the grilling of #107 (Q11, docs/grillings/2026-11-05-exclude-folders-from-notes-and-bump/GRILLING-ROUND-v02.md). --exclude-paths takes a '|'-separated list of literal paths: '|' is only a separator, with no regex and no glob. The '|' looks like a regex alternation, so a consumer may expect 'output|sources/.*\.wav' to work. To grill later: should entries become patterns (regex or glob), what it costs (definition, tests, refusals on a bad pattern), and whether the literal-path form stays.`
  - Command: `gh issue create --title "..." --label needs-triage --body "..."` in the repo, or tell me to run it after you allow it (for instance with the `! gh issue create ...` prefix).

Jeremie: I created it.

## Q26 - The case caveat: do you want two paths that differ only by case to stay distinct?

What I meant: git stores paths case-sensitively. On Linux (where GitHub Actions runs `release.sh`) a repository can hold both `Output/` and `output/` as two separate folders, and git reports them as two separate paths. On Windows and macOS the default filesystem folds the two, so a working copy there rarely has both, but the commit history can still contain both.

With a case-insensitive match, `--exclude-paths output` would also exclude `Output/`, even when the consumer meant only `output/`. With a case-sensitive match it excludes exactly `output/`, and `Output` has to be listed to be excluded too.

The cost of case-insensitivity is that it can drop a commit under a folder the consumer never named, in the rare repository that has both. The cost of case-sensitivity is that a consumer who mistypes the case on Windows or macOS gets an exclusion that silently matches nothing.

- A. Yes: two paths that differ only by case stay distinct, as in git.
- B. No: they are the same path for this option.

➡️ Recommendation: A. It is the only reading that never excludes more than what was named, and the rule of the option is already "exactly the paths you list" (Q12). The mistyped-case risk is real but visible: Q18's `Commits excluded : N` line shows 0 and the commit is in the notes.

### Answer to Q26

I understand. The docs must be very clear about this then.

Let's go for A

## Q27 - Case-sensitivity of the match (re-asks Q23)

`--exclude-paths Output` is given and the commits touch `output/a.wav`.

- A. Case-sensitive, as git paths are: `Output` covers nothing.
- B. Case-insensitive.

➡️ Recommendation: A, following Q26's recommendation. If you answered B to Q26, this is B.

### Answer to Q27

A

## Q28 - A commit that touches excluded and non-excluded paths

The scenario you flagged. A commit `feat: add a meditation guide` touches `output/guide-12.wav` (excluded), `sources/talk.pdf` (excluded) and `README.md` (not excluded), with `--exclude-paths 'output|sources'`.

- A. It stays in the notes: a commit is excluded only when every file it touches is under an excluded path, so one non-excluded file keeps it. It appears under its usual section (a `feat` under features), counts in the bump exactly as without the option (here a minor bump), and shows in the notes with its full subject and hash, unchanged. The commit's excluded files are not hidden or listed; the option filters commits, not files.
- B. It stays in the notes, but only for the bump, not listed (the notes show nothing for it).
- C. Other (say what).

➡️ Recommendation: A. It is the issue's second acceptance criterion, "a commit touching an excluded folder and another path stays in the notes", and a commit is the unit of the notes and of the bump: a half-kept commit would make the notes and the bump disagree. A test pins this scenario next to the all-excluded one and the empty-commit one.

### Answer to Q28

That's what I wanted. Go for A
