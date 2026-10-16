# The level from a branch name is parsed in release.sh, and is stricter than --level

A `release/major/<id>` branch forces the bump (#77). Two decisions came with it.

## Parsing sits in `release.sh`, not in the workflow

`release.sh` takes `--level-from <ref>` and reads the level segment itself. The workflow only passes `GITHUB_REF_NAME`, because CI checks out a detached `HEAD`.

The alternative was to parse the name in the workflow and pass `--level`. It would have been live at once, since the workflow is the part that changes fastest.

We chose the script because every consumer vendoring it then gets the same contract, and each refusal is pinned by a bats test, which a workflow step cannot be.

The cost, accepted: the workflow runs a pinned copy of `release.sh` (`RELEASE_SCRIPT_REF`), so CI cannot use the contract until the pin moves. That is a two-step move, merge the feature then point the pin at its commit, instead of one change.

## The name-derived level is stricter than `--level`

A name forcing a level below what the commits imply (`release/patch/<id>` over a `feat`) is refused with exit `3`, in every mode that computes a version. Forcing up is allowed, which is how the first major is cut. `--level` keeps its behaviour and is never refused for being lower.

The asymmetry is deliberate. `--level` is the caller's own word on the command line. A branch name is a label chosen earlier, and it can drift from the commits that land on it, so a lower level would publish less than the changes carry. Making `--level` strict as well would break its current users, and making the name lenient would let a mislabelled branch under-version a release.

Giving both options is a command-line mistake (exit `1`).
