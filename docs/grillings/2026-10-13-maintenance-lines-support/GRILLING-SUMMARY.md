# Grilling summary — Maintenance lines support (#13)

## Shared understanding

`release.sh` does not support maintenance lines. The repo exists to automate semantic releases for your own projects, none of which releases an older major today or has a candidate for it, and none has outside users who would pin an old major. A maintenance line would cost a baseline guard scoped to the line being released, a new definition of the trunk, an option to name the line and fixture tests per line, for no user.

The starting proposal offered two options: rule maintenance lines out, or scope the #22 guard to the line. The first was chosen, at its cheapest: unsupported and documented as such, without a detection rule. The guards that exist or are planned (`off-trunk`, and "baseline is the highest version tag" in #22) refuse a release cut from a line as a side effect, and the setup report (#31) explains that refusal. A detection rule by name was rejected: a maintenance line and a stranded tag look alike from the tags alone, so it would need a branch-name heuristic that can misfire.

The choice is easy to reverse (nothing here makes supporting lines harder to add later), so it gets no ADR. The term is recorded in `CONTEXT.md` as **Maintenance line**.

## Decision index

- Q1 (v01): none of your repos releases an older major today, and none is about to.
- Q2 (v01): unsure, no project named. Superseded by Q2b.
- Q2b (v02): no project comes to mind that could gain outside users pinning an old major.
- Q3 (v02): U2 is unsupported and the docs say so, with no detection of a line by name.

Superseded: Q2 by Q2b.
