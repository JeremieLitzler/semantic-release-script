# AGENTS.md

## Agent skills

### Issue tracker

Issues are tracked in GitHub Issues for JeremieLitzler/semantic-release-script, via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Uses the five default triage labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Tests

Testing a change to `scripts/release/release.sh`: run `tests/libs/bats-core/bin/bats tests/` (after `git submodule update --init`). Golden files, the fake `gh` and the opt-in live suite are explained in README's "Testing it".

### Domain docs

Single-context: one `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
