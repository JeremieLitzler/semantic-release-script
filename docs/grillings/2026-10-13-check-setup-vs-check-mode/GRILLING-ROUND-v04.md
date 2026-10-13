# Grilling round v04 — check-setup.sh or a release.sh --check mode (#14)

## Settled in v03

- Q6: the report runs the preflight and the guards, nothing new.
- Q7: exit `0` when no refusing check fails (warnings allowed), `3` when one does, `1` when `--check` cannot run.
- Q8: `--check` accepts `--trunk`, `--to`, `--since` and refuses every other option with exit `1`.
- Q9: `--check` runs the same `git fetch --tags origin` a release does (local tag refs only).
- Q10: option B: create the new issue for the length/language concern, no ADR, the decision lives in the glossary. I added **Setup report** to `CONTEXT.md` and have not created the issue yet.

## Q11 - Does `GRILLING-SUMMARY.md` match your understanding?

Read `GRILLING-SUMMARY.md` in this folder, especially the "Decided without being grilled" list and the paste-ready section for #14. Corrections edit the summary in place.

➡️ Recommendation: **Yes, with a look at "Decided without being grilled"**: the half-published release being a state rather than a failure is the one I would most like you to confirm, since it is a behaviour the report shows to a human. Next moves, once confirmed: create the length/language issue (I ask before creating it), then `to-spec`, `to-tickets` or `implement` for the `--check` mode itself.

### Answer to Q11

Yes
