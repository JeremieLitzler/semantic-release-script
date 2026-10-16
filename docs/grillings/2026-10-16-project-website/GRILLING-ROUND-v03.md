# Grilling round v03 — A promotion website for semantic-release-script

## Settled in v02

- Q9: Netlify is deployed by a build hook called from the release workflow, like the reference (not by Netlify watching the repo).
- Q10: I write `website/netlify.toml`; you create and link the Netlify site, with the settings I list in the PR description.
- Q11: the version badge is filled at page load from the GitHub API's latest release, with a static "latest" fallback. No commit back to `main`.
- Q12: the install `curl` is pinned to the latest version tag, filled in by the same fetch as the badge.
- Q13: you wrote the tagline: "Semantic release in one bash script. No npm tree. No dependencies." (reopened below, see Reopened).
- Q14: the terminal example is a real `--dry-run` capture, pasted as static HTML.
- Q15: the Q8 issue is filed now, labeled `needs-triage`: [#88](https://github.com/JeremieLitzler/semantic-release-script/issues/88).

## Reopened

- Q13, as Q16: "No dependencies" is not true of this script. The README's requirements line is `git`, `bash` 4+ and the GitHub CLI already logged in. The tagline is yours to word, but a claim a visitor can disprove on the first line of the README undercuts a page whose point is trust (see Q14).

## Q16 - The "No dependencies" claim

A. Keep "No dependencies" as written.
B. "Semantic release in one bash script. No npm tree. Just git, bash and gh." Same rhythm, true.
C. "Semantic release in one bash script. No npm tree." and the subline lists the three requirements.

➡️ Recommendation: B. It keeps your three-beat tagline and states the real requirements in the place a visitor looks first. A makes the first requirement they hit (`gh auth login`) look like a broken promise.

### Answer to Q16

B

---

## Q17 - Does Netlify also build on every push

With a build hook (Q9 = B), the site is only guaranteed to redeploy on a release. But a Netlify site linked to a GitHub repo builds on every push to its production branch by default, unless auto-builds are stopped in the dashboard.

A. Stop auto-builds: the site changes only when a release is cut (the hook), and a site-only edit waits for the next release or a manual "Trigger deploy" in Netlify.
B. Leave auto-builds on: the hook becomes redundant (every merge to `main` already deploys), and Q9 is in effect "both".
C. Stop auto-builds, and add a `workflow_dispatch` input `deploy-site` to `release.yml` that calls the hook without a release.

➡️ Recommendation: C. The reason for the hook is that the site tracks releases, but a typo fix on the page should not wait for a version bump, and the dispatch is a one-line addition next to the existing `preview` and `publish` choices. If you would rather keep `release.yml`'s inputs untouched, A.

### Answer to Q17

C

---

## Q18 - Which release.yml conditions call the hook

The publish job already knows whether a release was cut (`steps.release.outputs.released == 'yes'`), and its `Report` step runs only then.

A. A step after `Report`, gated on `released == 'yes'`, using the secret `NETLIFY_BUILD_HOOK`; if the call fails, the job fails (the release is already published, so the job goes red with the tag live).
B. Same, with `continue-on-error: true` and a line in the job summary on failure, so a Netlify outage never turns a published release red.
C. A separate job `needs: publish`, so the hook's result is visible apart from the release's.

➡️ Recommendation: C. A release that is published must not show as failed because of a website, and a separate job still shows its own red/green. B hides the failure in a summary nobody reads; A conflates the two.

### Answer to Q18

C

---

## Q19 - The install command when the version fetch fails

Q12 = A fills the tag from the GitHub API at load. The call can fail (API rate limit, no JS, ad-blocker, offline).

A. Show the command with a literal `<latest-tag>` placeholder and a link to the releases page.
B. Show the command pinned to `main`, with a note to pin once the tag is known.
C. Hide the command and show only a link to the README's install section.

➡️ Recommendation: A. It stays honest and the visitor can still finish the job by hand; B would show an unpinned command, against the project's own advice. C removes the page's one call to action.

### Answer to Q19

A
