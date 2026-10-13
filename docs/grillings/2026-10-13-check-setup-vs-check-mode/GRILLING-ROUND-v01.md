# Grilling round v01 — check-setup.sh or a release.sh --check mode (#14)

Facts found in the repo, so you don't have to: `release.sh` is one 889-line file; its preflight (`release.sh:494-531`) is inline top-level code that calls `die` on the first failing check (bash version, `git`, `gh`, inside a work tree, `gh auth status`, `gh repo view`, trunk resolution) and only `warn`s on branch name and dirty tree. `CONTEXT.md` defines a **Vendored copy** as "the script as committed inside a consumer, pinned to an upstream commit and synced only on purpose"; today 2 personal client projects are the consumers.

## Q1 - Is single-file vendoring a hard constraint, or a default?

The issue states that consumers vendor `release.sh` as a single file "on purpose", and that a second script "doubles what every sync copies and reviews". It also asks that the checks be "one module shared with `release.sh`'s own preflight". Those two statements pull against each other under option A (separate script): sharing code between two files means either `check-setup.sh` sources `release.sh` (or a lib file, which is a third file), or the checks are duplicated.

A. Hard constraint: a consumer vendors exactly one file, whatever the cost to structure.
B. A default: a second vendored file is acceptable if the separation is worth it, with only 2 consumers today.
C. Hard for `release.sh` (it must run alone), but a companion script is optional: a consumer who doesn't vendor it loses only the report.

➡️ Recommendation: **C**. `release.sh` must always run alone, because that is what the consumers rely on and what a sync copies. A companion that is strictly optional costs the consumers nothing and keeps your separation of concerns, but then the "shared module" can only be satisfied by the companion depending on `release.sh`, never the reverse.

### Answer to Q1

Check https://github.com/JeremieLitzler/transcript-cleaner-webapp and https://github.com/JeremieLitzler/french-gas-stations-scraper that uses an old version.

Potentially, two more projects will use it.

---

## Q2 - What exactly is the concern you want separated?

You said you prefer to keep separation of concerns in mind. There are three different things that could be separated, and they lead to different designs:

A. The **file**: release logic in `release.sh`, diagnostics in their own script.
B. The **code path**: one file, but the checks live in functions that `release.sh`'s preflight and a `--check` mode both call, with no release logic reachable from `--check`.
C. The **outcome**: the preflight refuses on the first failure (a guard's job), the report lists every check with its explanation and fix (a different job), whatever the file layout.

➡️ Recommendation: **B and C together** (they are not exclusive). The concern that matters is that checks are written once, return a result instead of calling `die`, and that two callers decide what to do with that result: the preflight stops on the first failure, the report prints them all. Whether that lives in one file or two is then a packaging question, answered by Q1 and Q3.

### Answer to Q2

I understand. So B.

My concern was a very long script. Maybe the technology use (Bash-only) isn't the best. Maybe Rust (I am not familiar with)?

---

## Q3 - Who runs the setup report, and when?

The shape of the report depends on its reader:

A. **A human, once**, right after vendoring `release.sh` into a consumer, or when a run refuses and they want to know why.
B. **CI**, on every pipeline, as a step before the release, reading an exit code.
C. **Both**.

This also decides whether the report may need to run when the script is not yet vendored (e.g. checking a machine before adding the file), which only a separate script could do.

➡️ Recommendation: **A**. With 2 consumers and a script that already refuses with a named reason and exit `3`, the gap the issue fills is a human who wants the full picture at once, not a CI gate. If a CI need appears, `--dry-run` already exercises the real preflight.

### Answer to Q3

A
