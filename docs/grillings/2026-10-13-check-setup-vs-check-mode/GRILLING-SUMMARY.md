# Grilling summary — check-setup.sh or a release.sh --check mode (#14)

## Shared understanding

#14 asked whether the full setup report should be a separate `check-setup.sh` or a `--check` mode of `release.sh`. It is a **`--check` mode of `release.sh`**. The deciding fact is that both consumers vendor `release.sh` as a single reviewed, pinned file (their `VENDORED.md` sync procedure is written for one file), so a second script would double what every sync copies and reviews; and a separate script could not share the preflight's checks with `release.sh` without sourcing it, a third file, or duplicating them. That moved single-file vendoring from "a default" to a hard constraint.

The separation of concerns you wanted is kept inside the file: each check is a function returning a result, with no release logic reachable from `--check`. The preflight keeps stopping at the first failure with today's wording and exit codes; `--check` runs every check and prints them all. The report is for a human, once (after vendoring, or after a refusal), so its output is readable text, not `key=value`.

`--check` covers the preflight and the guards, weighed against the target a release would use, so it answers "would a release refuse right now, and why?". It accepts only the options that name the target (`--trunk`, `--to`, `--since`) and refuses the others with exit `1`. It runs the same `git fetch --tags origin` a release does, so it writes nothing to the remote and no file, only local tag refs. It exits `0` when no check a release would refuse on fails, `3` when one does, `1` when it cannot run.

Your concern that `release.sh` is long, and whether Bash is the right technology (Rust was floated), is a different problem: a rewrite would change what consumers vendor and is far bigger than a setup check. It goes to its own issue. No ADR: the choice is recorded in the glossary only (`CONTEXT.md`, **Setup report**).

## Decisions

- Q1b (v02): single-file vendoring is a hard constraint, so no `check-setup.sh`.
- Q2 (v01): separation is by code path: shared check functions, a `--check` mode, no release logic reachable from it.
- Q3 (v01): the report is for a human, once; not a CI gate.
- Q4 (v02): length and language of `release.sh` are out of scope; they get a new issue.
- Q5 (v02): checks return results; preflight stops at the first, `--check` lists them all.
- Q6 (v03): the report runs the preflight and the guards, nothing new.
- Q7 (v03): exit `0` all pass (warnings allowed), `3` a refusing check fails, `1` it cannot run.
- Q8 (v03): `--check` accepts `--trunk`, `--to`, `--since`; any other option exits `1`.
- Q9 (v03): `--check` runs the same tag fetch a release does.
- Q10 (v03): create the new issue, no ADR, glossary only.
- Superseded: Q1 (v01) by Q1b (v02), which re-asked it with the consumers' facts.

## Decided without being grilled

- The option is named `--check`, as the issue wrote it.
- A half-published release on the target is reported as a state ("would resume at step 4"), not as a failure.
- `--check` runs before step 1: it decides no version and writes no summary.
- `CONTEXT.md` gained the term **Setup report**; **Preview** is left as it was, since a check is not a preview (it decides no version).
- Test coverage lands in the existing `tests/*.bats` suite (golden output for the report), with the fake `gh`.
