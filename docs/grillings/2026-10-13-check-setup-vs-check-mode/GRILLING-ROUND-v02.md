# Grilling round v02 — check-setup.sh or a release.sh --check mode (#14)

## Settled in v01

- Q2: the separation of concerns is **B**: checks live in functions that `release.sh`'s preflight and a `--check` mode both call, and no release logic is reachable from `--check`. (Option C, preflight stops on the first failure while the report lists all, was part of my recommendation and you answered "So B", so I treat C as not yet settled and ask it in Q5.)
- Q3: the setup report is for **a human, once** (after vendoring, or after a refusal), not a CI gate.

## Reopened

- Q1 (single-file vendoring: hard constraint or default?) came back as **Q1b**: you pointed me at the two consumers instead of picking an option. I read them; the facts are below and the question is unchanged.
- Q2's answer carried a second, separate decision (the script is long, maybe Bash is the wrong technology). It gets its own slot as **Q4**.

## Facts found in the two consumers

- Both vendor `scripts/release/release.sh` from `semantic-release-script-testing` (not this repo), pinned to commit `de0a43a`, each with a `VENDORED.md` that says "synced only on purpose, reviewed line by line, never tracked automatically". `french-gas-stations-scraper` holds it byte-for-byte except one hunk; `transcript-cleaner-webapp` the same hunk plus a note that it was verified byte-for-byte against the other consumer.
- Their `VENDORED.md` sync procedure is "diff the upstream file, review, replace the file", and it is written for exactly one file. A second file would add a second diff, a second pinned-commit story and a second review.
- Both run it in GitHub Actions on `ubuntu-latest` with `--yes`; the only tools there are `git`, `bash`, `gh`. The publish job also adds two guards of its own that `release.sh` does not carry (a `release/*` ref the trunk doesn't contain, an orphaned tag left on the remote). Those are checks of the kind the report could one day cover.
- Both consumers still carry a version older than this repo's current `release.sh`, so they will pick up whatever #14 decides at their next sync.

## Q1b - Is single-file vendoring a hard constraint, or a default?

The issue states that consumers vendor `release.sh` as a single file "on purpose", and that a second script "doubles what every sync copies and reviews". It also asks that the checks be "one module shared with `release.sh`'s own preflight". Those two statements pull against each other under option A (separate script): sharing code between two files means either `check-setup.sh` sources `release.sh` (or a lib file, which is a third file), or the checks are duplicated.

A. Hard constraint: a consumer vendors exactly one file, whatever the cost to structure.
B. A default: a second vendored file is acceptable if the separation is worth it, with only 2 consumers today (potentially 4).
C. Hard for `release.sh` (it must run alone), but a companion script is optional: a consumer who doesn't vendor it loses only the report.

➡️ Recommendation: **A**, now that I have read the consumers. Your Q2 answer (B) already puts the checks in one file's functions, and both `VENDORED.md` files are built around one file and one reviewed diff. **C** only works if the companion depends on `release.sh`, and each consumer would then carry a half-feature. With 2 to 4 consumers a second file is cheap today, but it buys little: the report is for a human, once (Q3).

### Answer to Q1b

First, `semantic-release-script-testing` was this repo: I renamed it.

So, A

---

## Q4 - Is the length of `release.sh` a problem to solve in #14?

You wrote that your concern was a very long script, and wondered about a language other than Bash (Rust). `release.sh` is 889 lines and every consumer vendors it whole. A `--check` mode adds code to it; a separate script moves code out of it.

This is a question about scope, before it is a question about language:

A. Yes: the length is the real driver of #14, and the language question must be answered first.
B. No: #14 only decides where the setup check lives; length and language belong to their own issue, if ever.
C. Partly: #14 picks the layout, but with a stated size budget for the `--check` code.

➡️ Recommendation: **B**. A rewrite changes what a consumer vendors (a compiled binary instead of a file you review line by line, and CI on `ubuntu-latest` would have to build or download it), which contradicts the `VENDORED.md` model in both consumers and is far bigger than a setup check. If you pick A, I will ask the language question next round with the vendoring trade-offs spelled out.

### Answer to Q4

B, so a new issue needs to be created.

---

## Q5 - Should the report list every failing check, while the preflight keeps stopping at the first?

Today the preflight calls `die` on the first failing check (`release.sh:496-513`). Your Q2 answer fixes where the checks live; this fixes how they are evaluated:

A. Yes: each check returns a result; the preflight stops at the first failure (same refusal, same exit code as today), `--check` runs all checks and prints every result with the reason and the fix.
B. No: `--check` stops at the first failure too, which is simply the preflight run alone.

➡️ Recommendation: **A**. The whole point of a report over a refusal is the full picture at once, and the preflight's behaviour for existing callers (exit codes, wording, the tests in `tests/options.bats`) stays exactly as it is.

### Answer to Q5

A
