# Grilling round v01 — Maintenance lines support (#13)

Starting point: #13 asks whether `release.sh` supports **maintenance lines** (a second long-lived branch releasing an older major, e.g. `v1.2.1` on `1.x` while the trunk is at `v2.0.0`), or rules them out. You said the repo exists to automate semantic releases for your own projects and you doubt you need this.

Facts found in the repo, so you don't have to look them up:

- `CONTEXT.md` already defines the **Trunk** as "the one long-lived branch of a repository that releases are cut from" and **Non-monotonic version** as a single-trunk concept. The glossary already leans toward ruling maintenance lines out.
- `release.sh` already refuses to tag a commit the trunk cannot reach (`verify_trunk_contains`, refusal `off-trunk`). A release run from a `1.x` branch carrying commits the trunk lacks is therefore refused today, unless `--trunk 1.x` is passed.
- #22 (baseline must be the highest version tag) is the guard that conflicts with maintenance lines; #26 documents the setup map and needs U2's status from this issue.

## Q1 - Do any of your repos release an older major today?

Think of every consumer of the vendored script (`transcript-cleaner-webapp`, `french-gas-stations-scraper`, this repo, and any other you plan to add).

A. No, every one of them releases from a single trunk only.
B. Yes, at least one has (or had) a branch like `1.x` that receives its own releases.
C. Not today, but one is likely to soon (say which).

➡️ Recommendation: A. Your repos are personal, and a personal project nobody else pins to an old major has no reason to patch one: you move forward and release a new patch on the trunk.

### Answer to Q1

A

---

## Q2 - Who would ever need a patch on an old major?

A maintenance line only pays off when someone else is stuck on an older major and cannot upgrade: a published library, a public API, a CLI others pin. Is any of your projects like that, or could one become so?

A. No: they are apps, scripts or tools only you run, so upgrading to the latest major is always an option.
B. One of them is a library or tool with outside users who may pin an old major.
C. Unsure.

➡️ Recommendation: A. If it holds, the cost of a maintenance line (a baseline guard scoped per line, a setup map entry, tests) buys nothing. If B or C, say which project, since that is the only case where the "scope the guard to the line" option is worth weighing.

### Answer to Q2

C
