# Grilling summary — control the release level from the release/\* branch name (#77)

## Shared understanding

A push to a `release/*` branch publishes, but the bump is decided by the commits, so the first major release (v1.0.0, from v0.4.0) is out of reach for CI. The contract settled here lets the branch name force the level, with `release.sh` as the one place that parses it.

The level is a path segment: `release/<level>/<id>`, for example `release/major/20261015.1`, or the bare `release/<level>` (see below). The accepted values are exactly `major`, `minor` and `patch`, in lowercase. A name with no such segment (`release/20261015.1`, `release/hotfix-login`, `main`) behaves exactly as today, with no extra output. A name whose segment merely looks like a level (`release/mayor/...`, `release/Major/...`) is ignored in the same way, not refused: the starting proposal leaned towards refusing it, and you chose to keep the contract to the three exact values.

The parsing is in `release.sh`, behind a new option `--level-from <ref>` that takes a branch name; the workflow passes `GITHUB_REF_NAME`, because CI checks out a detached `HEAD`. This was chosen over parsing in the workflow so that every consumer vendoring the script gets the same contract and each refusal is pinned by a bats test. The cost, accepted, is that the workflow runs a pinned copy of the script, so the contract cannot be used by CI until the pin moves.

The name-derived level is stricter than the explicit `--level`: if the name forces a level below what the commits imply (`release/patch/<id>` over a `feat`), the run is refused with exit `3`, in every mode that computes a version (a real run, `--dry-run`, `--local` and `--check`). Forcing up is allowed, which is the v1.0.0 case. `--level` keeps today's behaviour. Giving both `--level` and `--level-from` is a command-line mistake (exit `1`). On a resume, `--level-from` is ignored with a warning, like `--level`. A forced level over a range with no commit still exits `2`, "nothing to release". There is no dispatch input: only the branch name carries the level, and a dispatch from a `release/major/...` ref honours its name. The preview job passes the ref name too, so a dispatch preview from such a ref shows the forced version before the publish; on `main` nothing changes.

The value given to `--level-from` must be a branch, found locally (`refs/heads/<name>`) or on origin (`refs/remotes/origin/<name>`), whether or not its name carries a level; otherwise the run is refused with exit `1`, as is an empty value. This was settled while implementing #78, not in a grilling round: an empty `github.head_ref` on a `push` event, or a typo like `release/mayor/x` mapping to no branch, is a wrong usage rather than a name with no level. It narrows "behaves exactly as today" above to names of existing branches. The bare names `release/major`, `release/minor` and `release/patch`, with no id after the level, also force the level; `release/major-x/y` and the near-misses stay names with no level.

Hotfixes are out of scope: the patch-only path is `release/patch/<id>` cut from `main`, which the strictness above already holds to patch-only commits. A fix from a tag is the maintenance-line question closed in #13 and gets its own ticket if it ever matters.

v1.0.0 is cut without an intermediate v0.5.0. The implementation is typed `feat:`; once it is merged to `main`, `RELEASE_SCRIPT_REF` moves to the SHA of that merge commit (not a version tag, a one-time bend of the pin rule), then `release/major/<id>` is pushed from `main`. The range is v0.4.0 to `main`, so the v1.0.0 notes carry the feature under `Features` and the `ci:` commits under `Others`. You accepted that a forced level never changes the range, and asked that this be documented for future users.

That documentation is a hand-written summary of the major, `docs/release-<version>.md` (`release-1.0.0.md` first), not a copy of the release notes. It is a convention for every major, not enforced by the script, written and merged before the `release/major/<id>` push; its `docs:` commit lands in the range, under `Others`, and does not change the forced major. The GitHub release is not linked to it by any tooling: the README links it, and a line can be added by hand to the release. The README recommends an outline (what the major means, what breaks and what to change, the new things grouped by theme, a link to the range), with no template file.

The contract is documented in README "Cutting a release", in `CONTEXT.md` (a new term **Level segment**, and the **Bump** entry's "Avoid: level" note updated) and in an ADR in a new `docs/adr/`.

## Decision index

- Q1 (v01): the level is a path segment, `release/<level>/<id>` (bare `release/<level>` too, see Q25); values `major`, `minor`, `patch`.
- Q2 (v01): parsed in `release.sh`, not in the workflow; v1.0.0 needs the pin to move first.
- Q3 (v01): only the branch name carries the level; no dispatch input.
- Q4 (v01): a forced level over an empty range still exits `2`.
- Q5 (v01): a name forcing below what the commits imply is refused (exit `3`); forcing up is allowed; `--level` unchanged.
- Q6 (v02): the option is `--level-from <ref>`.
- Q7 (v02): a name with no level behaves as today, no extra output.
- Q8 (v02): a near-miss segment is ignored, not refused.
- Q9 (v02): `--level` with `--level-from` is exit `1`.
- Q10 (v02): no change on `main`; the preview job passes the ref name.
- Q11 (v02): superseded by Q12 and Q13, itself superseded by Q19.
- Q12 (v03): the implementation is typed `feat:`.
- Q13 (v03): no answer, see Q12; re-asked as Q19.
- Q14 (v03): hotfixes out of scope; `release/patch/<id>` is the patch-only path.
- Q15 (v03): `--level-from` is ignored with a warning on a resume.
- Q16 (v03): every mode that computes a version weighs the Q5 refusal, `--dry-run` included.
- Q17 (v03): README, `CONTEXT.md` term **Level segment**, and an ADR.
- Q18 (v04): thin v1.0.0 notes are acceptable, and must be documented.
- Q19 (v04): no v0.5.0; the pin moves to the feature's merge SHA, then `release/major/<id>`.

- Q20 (v05): not answered; reopened Q18 with the `docs/release-<version>.md` idea, re-asked as Q24.
- Q21 (v06): the summary of a major is a convention for every major.
- Q22 (v06): no tooling links the GitHub release to it; the README does.
- Q23 (v06): the README recommends an outline, with no template file.

- Q24 (implementation of #78, no round): `--level-from` must name an existing branch, locally or on origin, and an empty value is refused, both with exit `1`.

- Q25 (implementation of #78, no round): the bare `release/<level>` name forces the level too.

Superseded: Q11 by Q12, then Q13 by Q19; Q18 completed by Q21 to Q23 (the documentation it asked for is the major summary).
