# Grilling round v04 — A promotion website for semantic-release-script

## Settled in v03

- Q16: tagline is "Semantic release in one bash script. No npm tree. Just git, bash and gh."
- Q17: Netlify auto-builds are stopped, and `release.yml` gets a `workflow_dispatch` input `deploy-site` that calls the hook without a release.
- Q18: the hook is called from a separate job `needs: publish`, so Netlify's result is visible apart from the release's.
- Q19: when the version fetch fails, the install command shows a `<latest-tag>` placeholder and a link to the releases page.

## Q20 - Does the summary match your understanding

Read `GRILLING-SUMMARY.md`, including its "Decided without being grilled" list.

A. Yes, it matches.
B. No: I correct it in the file, or in the answer below.

➡️ Recommendation: A once you have checked the "Decided without being grilled" list, in particular the green accent and the `deploy-site` input in `release.yml`. Corrections edit the summary in place; only one that reopens a real decision opens a new round.

### Answer to Q20

A.

Notes:

- remove paste-ready section and move it the issue's comments
- What prompt would be good to generate a nice and humble logo from a image model?
