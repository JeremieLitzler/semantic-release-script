# Grilling round v02 — leave out commits that only touch excluded paths

Issue: JeremieLitzler/semantic-release-script#107, on branch `issue-107-exclude-folders-from-notes-and-bump`.

Round files are never rewritten, so your Q1 answer reshapes the rest here: v01 Q2 to Q9 are superseded by Q10 to Q18 below. Do not answer v01 Q2 to Q9.

## Settled in v01

- Q1: the option is named `--exclude-paths` (not `--exclude-folder`) and takes one value that lists the paths with `|`, as in `--exclude-paths 'output|sources'`.

## Reopened

- v01 Q2 (what a name matches): "paths" and a `|` list change what an entry can be and what `|` means. Re-asked as Q11, Q12 and Q13.
- v01 Q3 to Q9: unchanged in substance, but reworded to say "excluded paths" instead of "excluded folders" and, for Q5, Q6 and Q7, to use the new option. Re-asked as Q14 to Q18.
- The issue says the option is "repeatable"; your Q1 answer is a list in one occurrence. Re-asked as Q10.

## Q10 - Repeating the option

The issue asks for a repeatable option. Yours takes a `|` list in one occurrence. What happens on `--exclude-paths a --exclude-paths b|c`?

- A. Both forms work and add up: the excluded paths are `a`, `b` and `c`.
- B. One occurrence only: a second `--exclude-paths` is a command-line mistake and exits `1`.
- C. The last occurrence wins.

➡️ Recommendation: A. It meets the issue's "repeatable" wording at the cost of a few lines, and the consumer can pick whichever its workflow builds more easily. C is a trap (an earlier path silently stops applying), and B refuses something the issue explicitly allows.

### Answer to Q10

I prefer one argument as chosen in Q1

## Q11 - What `|` means

A `|` between entries looks like a regex alternation, but the entries are paths.

- A. `|` is only a separator. Each entry is a literal path, with no regex and no glob. `*`, `?` and `[` mean themselves. The value must be quoted in a shell (`'output|sources'`), and the README says so.
- B. Entries are glob patterns (`*.wav|sources/**`).
- C. The whole value is an extended regex matched against each touched path.

➡️ Recommendation: A. The issue asks for named folders, and any pattern language (B or C) has to be defined, tested and refused-on-error forever. Literal entries also make the README one sentence long.

### Answer to Q11

A for now. But record an issue to grill the idea of regex alternation.

## Q12 - Where an entry is anchored

`--exclude-paths output` is given. Which touched files does `output` cover?

- A. Only the path `output` at the repository root: `output/a.wav` and `output/runs/b.wav`, but not `docs/output/x.md`. A trailing slash (`output/`) means the same, and a nested entry works (`audio/runs`). A match is on whole path components, so `output` does not cover `output-old/x`.
- B. Any path with that component at any depth (`output/` and `docs/output/`).

➡️ Recommendation: A. The consumer names root paths (`output`, `sources`), and `docs/output` stays in the notes. B silently drops commits under paths the consumer never named.

### Answer to Q12

A

if consumer has a `docs/output`, it should add it to the path list.

## Q13 - Folders only, or files too

The option is named `paths`, not `folders`, but the issue is about folders.

- A. An entry may name a folder or a single file (`CHANGELOG.md`): it covers that exact path and everything under it. The README says so.
- B. Folders only: the option is named `paths` but a file entry covers nothing and is refused (exit `1`).

➡️ Recommendation: A. With a literal root-anchored match (Q11 and Q12 recommended answers), a file needs no extra code and the name `paths` then tells the truth. B would need a check that an entry is a folder, which breaks for a folder that exists only in some commits of the range.

### Answer to Q13

A

## Q14 - A commit that touches no file

A commit made with `--allow-empty` (for instance `chore: trigger release`) touches no file, so "every file it touches is under an excluded path" is vacuously true.

- A. It is kept. A commit is dropped only when it touches at least one file and all of them are under excluded paths.
- B. It is dropped, following the literal rule.

➡️ Recommendation: A. The consumer asked to drop commits that are about the excluded paths; an empty commit is about nothing, and dropping it would change today's behaviour for a consumer that releases through an empty commit.

### Answer to Q14

A, but I doubt the repo's script create empty commit on cutting a release.

## Q15 - Renames and moves

A commit renames `output/a.wav` to `docs/a.wav` (or the reverse). Git can report this as one rename or as a delete plus an add.

- A. Both the source and the destination count as touched paths (rename detection off). That commit touches `docs/`, so it is kept; `output/a.wav` renamed to `output/b.wav` touches only `output/`, so it is dropped.
- B. Only the destination counts.

➡️ Recommendation: A. The rule is "every file it touches"; a file that left an excluded path was touched there, and a move into or out of one is the kind of commit a developer log should keep.

### Answer to Q15

A

## Q16 - `--check`

Today `--check` refuses every release-shaping option. The acceptance criteria say `--check` honours the new option.

- A. `--check` accepts `--exclude-paths` next to `--trunk`, `--to`, `--since` and `--level-from`, and weighs the version on the commits that remain (an all-dropped range reports "nothing to release", as an empty range does). The refusal message lists it among the accepted options.
- B. `--check` keeps refusing it.

➡️ Recommendation: A. The setup report weighs what a release would compute, and with the option that is a different range; a report that ignored it would approve or refuse a release the real run would not make.

### Answer to Q16

A

## Q17 - A resume with the option

A run died after pushing `v1.2.0`. The next run is a resume, and its notes are rebuilt over the range the tag was cut on.

- A. The option is honoured on a resume exactly as on a release: the caller passes the same value and gets the same notes. The README says the retry must pass the same value.
- B. The option is ignored on a resume with a warning, like `--level`: the notes are rebuilt over every commit of the range.

➡️ Recommendation: A. The consumer's workflow passes the same arguments on every run, so A reproduces the notes the first run wrote; B would publish notes that differ from the ones the version was computed from.

### Answer to Q17

A

## Q18 - What the run says about dropped commits

A developer reading a release's log should be able to see why a commit they pushed is missing.

- A. Step 1 prints, when the option is given, one extra line `Commits excluded : N (only under: output, sources)` and each dropped commit's short hash and subject, dimmed, after the kept ones. Without the option the output is byte-identical to today.
- B. Only the count, no list.
- C. Nothing: the commit is simply absent.

➡️ Recommendation: A. A silent drop is the hardest thing to debug in a release; the list costs a few lines and appears only when the option is used. "Without the option, nothing changes" stays true.

### Answer to Q18

A

## Q19 - The release summary

The **release summary** (`--summary`) holds the tag, the version, the bump, the baseline and whether a GitHub release was created.

- A. No new key. The summary describes the release, not how its commits were chosen.
- B. Add a `dropped=N` key.

➡️ Recommendation: A. No consumer asked for it, the issue does not list it, and each key is a contract the golden files and the README must carry from then on.

### Answer to Q19

A

## Q20 - What "cut a release of the script" means for this issue

The issue ends with "Then cut a release of the script that a consumer can pin". The repository's own release is cut by its workflow once changes are on `main`, and moving a consumer to it is a separate guide (`docs/agents/upgrade-release-sh.md`).

- A. The PR delivers the code, the bats tests and golden files, the README section and a `CONTEXT.md` entry. After it merges, you cut the release (a `feat` makes it `v1.1.0`) through the usual `release/*` flow, and the issue is closed when it exists. I do not push a `release/*` branch or dispatch the workflow without you saying so.
- B. The PR also includes the repo's own workflow pin bump to the new version.

➡️ Recommendation: A. A pin to a release that does not exist yet cannot go in the same PR (the previous bump, #105, was its own issue after v1.0.1 existed), and publishing a release is an outward-facing action that stays yours.

### Answer to Q20

It is the release that we'll have on this repo once the grilling, implementation and validation is complete.
