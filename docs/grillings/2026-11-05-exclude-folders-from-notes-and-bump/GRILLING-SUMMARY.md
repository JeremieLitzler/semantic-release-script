# Grilling summary — leave out commits that only touch excluded paths

Issue: JeremieLitzler/semantic-release-script#107, on branch `issue-107-exclude-folders-from-notes-and-bump`.

## Shared understanding

A consumer such as coge-audio-meditation-guides keeps recorded audio (`output/`) and source material (`sources/`) in its repository, and the commits that only touch them are noise in a developer log. `release.sh` gets one option, `--exclude-paths`, whose single value lists the paths to exclude with `|`: `--exclude-paths 'output|sources'`.

The issue asked for a repeatable option naming folders. The grilling moved to a single argument with a list (Q1, Q10, Q21): one way in means one contract, and repeating the option is a command-line mistake (exit `1`). It is called `paths` rather than `folders` because an entry may be a file as well as a folder (Q13). The `|` is only a separator: entries are literal, with no regex and no glob (Q11); whether regex alternation should come later is a separate issue to grill.

An entry is anchored at the repository root and matched on whole path components, case-sensitively as git is (Q12, Q26, Q27). `output` covers `output/a.wav` but not `docs/output/x` nor `Output/x`; a consumer who wants those lists them. The README must be very clear about this, including the quoting of the value in a shell.

A commit is an excluded commit only when it touches at least one file and every touched file is under an excluded path (Q14, Q15, Q28). A commit that also touches anything else stays, under its usual section, and counts in the bump in full. A commit that touches no file stays: `release.sh` never makes an empty commit, so the case can only come from a consumer's own history. A rename counts both its source and its destination. An excluded commit counts neither in the notes nor in the bump, and a range made only of them is nothing to release (exit `2`).

Bad values are refused with exit `1`: an empty or missing value, an empty entry, `.`, an absolute entry or one with a `..` component. A leading `./` and trailing slashes are normalised, and an entry that matches nothing is accepted (Q22).

`--check` accepts the option and weighs the version on the commits that remain (Q16). `--dry-run`, `--local`, `--to` and `--since` honour it unchanged, and a resume honours it too, so the retry must pass the same value (Q17). Step 1 prints a `Commits excluded : N (only under: ...)` line and each excluded commit when the option is given, and its output is unchanged without it (Q18). The release summary gets no new key (Q19). The vocabulary is **Excluded path** and **Excluded commit**, now in `CONTEXT.md` (Q24).

The release of the script is not part of the PR. Definition of done: tests for each acceptance criterion pass, a read-only dry run on a clone of coge-audio-meditation-guides shows the expected notes, and the human cuts the release (Q20, Q25).

## Decision index

- Q1, v01: the option is `--exclude-paths`, one value, paths separated by `|`.
- Q10, v02: one argument only, as in Q1.
- Q11, v02: `|` is only a separator; literal entries, no regex, no glob; regex alternation to be grilled in its own issue.
- Q12, v02: entries are anchored at the repository root and matched on whole components.
- Q13, v02: an entry may be a folder or a file.
- Q14, v02: a commit touching no file is kept.
- Q15, v02: renames count both ends.
- Q16, v02: `--check` accepts the option.
- Q17, v02: a resume honours the option.
- Q18, v02: step 1 prints the excluded count and commits, only when the option is given.
- Q19, v02: no new key in the release summary.
- Q20, v02: the release is cut on this repo once grilling, implementation and validation are done.
- Q21, v03: repeating the option is a mistake, exit `1`.
- Q22, v03: bad values are refused with exit `1`; `./` and trailing slashes normalised.
- Q24, v03: terms **Excluded path** and **Excluded commit**.
- Q25, v03: definition of done: bats tests, a read-only dry run on the consumer, the human cuts the release.
- Q26, v04: two paths differing only by case stay distinct.
- Q27, v04: the match is case-sensitive.
- Q28, v04: a commit touching excluded and other paths stays in the notes and counts in the bump.
- Superseded: Q2 to Q9 of v01 by Q10 to Q20 of v02; Q23 of v03 by Q26 and Q27 of v04.

## Never grilled, decided here

Say so if you object to any of these before the implementation starts.

- An ADR `docs/adr/0003-...` for the contract of the option (single `|`-separated value, literal and root-anchored entries, not repeatable). It meets the three tests: costly to change once consumers pin it, surprising next to the issue's "repeatable", and a real trade-off. I propose to write it with the implementation, not now.
  - Agreed
- Where the README documents the option: its options reference and a short section next to "Cutting a release", covering the quoting, the case-sensitivity, the resume rule and the `docs/output` example.
  - Agreed
- Exit code and wording of the refusals (`1`, "--exclude-paths ..."), and the new tests and golden files: bats cases for every acceptance criterion plus the Q14, Q15, Q22 and Q28 scenarios.
  - OK
- A `--level` or `--level-from` over a range made only of excluded commits still exits `2`, as over an empty range, before any level is applied.
  - Correct

## Paste-ready: comment for issue #107

Grilled on this issue; the decisions differ from the text above in the following ways.

The option is `--exclude-paths`, taking one value that lists the paths with `|` (`--exclude-paths 'output|sources'`), not a repeatable option. Giving it twice is a command-line mistake (exit `1`). It is `paths`, not `folders`, because an entry may also be a single file. Entries are literal (no regex, no glob), anchored at the repository root, matched on whole path components and case-sensitively: `output` does not cover `docs/output` or `Output`.

A commit is left out only when it touches at least one file and all of them are under an excluded path; renames count both ends. A commit that also touches anything else stays in the notes under its usual section and counts in the bump in full. A commit that touches no file stays. An excluded commit counts neither in the notes nor in the bump, and a range made only of them exits `2`.

Empty or missing values, empty entries, `.`, absolute entries and `..` components are refused (exit `1`). `--check`, `--dry-run`, `--local`, `--to`, `--since` and a resume all honour the option. Step 1 lists the excluded commits when it is given. The release summary gets no new key.

Regex alternation is left for a separate issue. The release of the script is cut by me once the tests pass and a dry run on coge-audio-meditation-guides shows the expected notes.
