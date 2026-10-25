# Upgrading a consumer to a new `release.sh`

How to move one repository listed in [CONSUMERS.md](../../CONSUMERS.md) to a newer `release.sh`. Every consumer downloads the script at the SHA held in `RELEASE_SCRIPT_REF`, in `.github/workflows/release.yml`; upgrading means moving that pin and adapting the workflow to what changed. Do one consumer at a time, and run every command from that consumer's clone.

Set these first:

```bash
OLD=$(grep -oP 'RELEASE_SCRIPT_REF: \K[0-9a-f]{40}' .github/workflows/release.yml)
NEW_TAG=vX.Y.Z                                   # the release to move to
NEW=$(gh api repos/JeremieLitzler/semantic-release-script/commits/$NEW_TAG -q .sha)
TRUNK=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)   # main or develop
```

Pin a SHA, never a tag name: a tag can be moved, a SHA cannot.

## 1. Create the issue

Check that no open issue already covers it (`gh issue list --state open --search release.sh`), then:

```bash
gh issue create --label enhancement \
  --title "Bump release.sh to $NEW_TAG" \
  --body "Move \`RELEASE_SCRIPT_REF\` in \`.github/workflows/release.yml\` from \`$OLD\` to \`$NEW\` ($NEW_TAG).

- Release notes: https://github.com/JeremieLitzler/semantic-release-script/releases/tag/$NEW_TAG
- Script changes: https://github.com/JeremieLitzler/semantic-release-script/compare/$OLD...$NEW
- Adjust the workflow to any changed flag, exit code or \`--summary\` key.
- Dry-run the new script, and the preview job from the PR branch, before merging."
```

Use only a label that exists in the repo (`gh label list`).

## 2. Integrate the new version

Branch from the trunk: `git switch $TRUNK && git pull --ff-only && git switch -c ci/<issue>-bump-release-sh`.

Read what changed before editing anything:

- the release notes of every tag between the old and the new pin (`gh release list -R JeremieLitzler/semantic-release-script`);
- the diff of the script itself: `gh api "repos/JeremieLitzler/semantic-release-script/compare/$OLD...$NEW" -q '.files[] | select(.filename=="scripts/release/release.sh") | .patch'`;
- the README of the new tag: its option table, exit codes and `--summary` keys.

The flags, the exit codes and the `--summary` keys only change in a major. On a minor or a patch, moving the pin is usually the whole change; on a major, expect workflow edits. Then:

1. Set `RELEASE_SCRIPT_REF` to `$NEW`, and the comment above it to the tag and short SHA (`# Tag vX.Y.Z (commit abc1234): <one-line reason>`). The SHA appears once; both download steps (preview and publish) read it.
2. Check every place the workflow calls the script or reads its output against the new README: the flags passed (`--dry-run`, `--yes`, `--level-from`, `--summary`, `--notes`), the exit codes the steps branch on (`0`, `2`), and the `grep` of `--summary` keys feeding `$GITHUB_OUTPUT`.
3. Keep what is specific to this consumer: the trunk name in the job conditions and the `release/*` containment check, the test job's commands (or its absence), the `deploy-site` job.
4. Update the consumer's own docs only where they name the old version or SHA.

Commit as `ci: bump release.sh to $NEW_TAG (#<issue>)`.

## 3. Dry-run the integration

Locally, with the exact script the workflow will download:

```bash
curl -fsSL "https://raw.githubusercontent.com/JeremieLitzler/semantic-release-script/$NEW/scripts/release/release.sh" -o "$TMP/release.sh"
git fetch --tags --force origin
bash "$TMP/release.sh" --check --trunk "$TRUNK" --to "origin/$TRUNK"
bash "$TMP/release.sh" --dry-run --yes --trunk "$TRUNK" --to "origin/$TRUNK" --summary "$TMP/release.env" --notes "$TMP/notes.md"
```

`$TMP` is any scratch directory outside the clone. Expect `--check` to exit `0`, and the dry run to exit `0` (a release is pending; read `$TMP/release.env` for the version) or `2` (nothing to release). Exit `3` is a guard refusing: read the reason it prints before going further. `stale-tags` on a local clone is fixed by the `git fetch --tags --force origin` above; on Windows, run it under Git Bash or WSL.

On CI, once the branch is pushed, dispatch the preview job from it. A dispatch runs on the last commit of the chosen ref (its `GITHUB_SHA`), so the run uses the branch's workflow file and its new pin before the merge; the workflow must also exist on the default branch, which it does. A preview never writes a tag:

```bash
git push -u origin HEAD
gh workflow run release.yml --ref "$(git branch --show-current)" -f action=preview
gh run watch "$(gh run list -w release.yml -L 1 --json databaseId -q '.[0].databaseId')"
```

The job summary must show the pending version and notes, or "Nothing to release". A preview from a branch the trunk does not contain only warns (`off-trunk`), it does not fail.

## 4. Open the PR

```bash
gh pr create --base "$TRUNK" --title "ci: bump release.sh to $NEW_TAG" --body "Closes #<issue>

- \`RELEASE_SCRIPT_REF\`: \`$OLD\` > \`$NEW\` ($NEW_TAG).
- Workflow changes: <none, or what was adapted and why>.
- Local \`--check\`: exit <code>. Local \`--dry-run\`: exit <code>, <version or nothing to release>.
- Preview dispatched from this branch: <run URL>."
```

End the body with the attribution lines the session requires. After the merge, the push to the trunk runs the preview again with the new script; the next `release/*` push publishes with it.

Last, update the consumer's entry in [CONSUMERS.md](../../CONSUMERS.md) (pinned SHA and version) in a PR on this repository.
