# The release.sh download is repeated in each job, not shared through an action

Consumer workflows (this repository's `release.yml`, and those modelled on it) fetch the pinned `release.sh` in the `preview` job and again in the `publish` job (#100).

## The step stays in each job

The step is a `curl` of the file at `RELEASE_SCRIPT_REF` and a `chmod +x`. The jobs are mutually exclusive (a push to `main` or a `preview` dispatch, against a push to `release/*` or a `publish` dispatch), so a run downloads the script once. The SHA is declared once, at the workflow level.

The alternative was a composite action or a reusable workflow published from this repository. We kept the duplication because the action would carry its own ref, a second pin that can drift from `RELEASE_SCRIPT_REF`, and a new public surface to version and test, to save two commands.

The cost, accepted: a consumer that flags the repeated step in review is told it is intended, and a change to the step is made in each job.

Revisit if the step grows beyond the download, or if several consumers need to change it together.
