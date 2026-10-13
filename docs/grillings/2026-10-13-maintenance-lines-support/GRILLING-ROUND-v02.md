# Grilling round v02 — Maintenance lines support (#13)

## Settled in v01

- Q1: none of your repos releases an older major today, and none is about to (answer A).

## Reopened

- Q2: you answered "Unsure" (C) without naming a project, so whether any project could gain outside users who pin an old major is not settled. It comes back as Q2b with a narrower ask, and Q3 is decided in a way that does not wait on it.

## Q2b - Which project, if any, could gain outside users pinning an old major?

You were unsure in Q2. Name the project and the reason, or say none comes to mind. A published library, a public API or a CLI others install and pin are the cases that count; an app or script only you run does not.

A. None comes to mind: treat Q2 as A.
B. Project(s): <name them and say why>.

➡️ Recommendation: A. Unsure with no candidate in mind is, for a decision you can revisit cheaply (see Q3), the same as no. If you can name one, B, and we weigh scoping the guard to the line for that project only.

### Answer to Q2b

A

---

## Q3 - What status does U2 (maintenance lines) get in the supported-setup map?

#26 needs this. The options, from cheapest to dearest:

A. **Unsupported, and the docs say so.** `CONTEXT.md` keeps "the one trunk"; `docs/supported-setups.md` lists U2 as unsupported. No detection of a maintenance line by name: the guards that exist or are planned (`off-trunk` today, "baseline is the highest version tag" in #22) refuse a release run from one as a side effect, and the setup report (#31) explains that refusal.
B. **Unsupported, and refused by name.** As A, plus the setup report and `release.sh` recognise a maintenance line (for instance a `N.x` branch, or a tag higher than the baseline reachable from another long-lived branch) and refuse with a message that says "maintenance lines are not supported". Costs a detection rule and its tests.
C. **Supported.** Scope the #22 guard to the line being released (highest version tag within the same major, or on the same branch). Costs the rule, a `--line` style option, a new Trunk definition, and fixture tests per line.

➡️ Recommendation: A. Q1 says you have no use for one, and #22 already makes the refusal happen without a detection rule that could misfire on a stranded tag (a maintenance line and a stranded tag look the same from the tags alone, which is why B needs a branch-name heuristic). If a project ever needs one, reopening #13 then is cheap: nothing in A makes C harder to add later. That also means no ADR: the choice is easy to reverse, which fails the ADR test.

### Answer to Q3

A
