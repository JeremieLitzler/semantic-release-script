# Grilling summary — A promotion website for semantic-release-script

## Shared understanding

The project gets a one-page promotion site, modeled on the deadlinkprobe site (`deadlinkprobe_main/website/`): a hand-written static `index.html`, dark theme, mono type, Tailwind v4 compiled to a committed `style.css`. It lives in `website/` at the repo root, with its `package.json` inside that folder so the pure-bash root stays Node-free.

The audience is developers who want a semantic release without an npm tree, and the one action the page drives is "vendor `release.sh` into my repo". Stars and a comparison with the npm `semantic-release` are not the page's spine, and the npm package is not named.

The page keeps the reference's skeleton but not its content: hero (name, badges for version, bash 4+, GPL-3.0, the install call to action), a terminal example, features, how it works (the four steps of `release.sh`: evaluate the version, release notes, create and push the tag, publish the release), quick start, an options table, and a short CI usage section. Supported setups is a single link card to `docs/supported-setups.md`. The reference's "output" and "email" sections are dropped: there is no CSV or mail here. A new accent color (green suggested) and a new SVG logo/favicon, drafted for your review, set it apart from deadlinkprobe's cyan and red.

Hosting is Netlify, not GitHub Pages. Netlify deploys through a build hook called from the release workflow, like the reference, but as a separate job so a Netlify outage never turns a published release red, and a `deploy-site` manual input on `release.yml` lets a site-only fix ship without a version bump; Netlify's own auto-builds are stopped.

The version badge is not committed back to `main` as in the reference: the publish job runs from a throwaway `release/**` branch with a read-only default token, so the page instead fetches the latest release from the GitHub API at load, and the same fetch fills the tag in the pinned install `curl`. If the fetch fails the command shows a `<latest-tag>` placeholder and a link to the releases page, never an unpinned `main`.

The terminal example is a real `--dry-run` capture, since a skeptical visitor can catch an invented one. Your tagline draft's "No dependencies" was reopened because the script needs `git`, `bash` 4+ and `gh`; it becomes "Semantic release in one bash script. No npm tree. Just git, bash and gh."

## Decision index

- Q1, v01: audience is developers wanting a semantic release without npm; goal is to vendor `release.sh`.
- Q2, v01: the site lives in `website/` at the repo root.
- Q3, v01: hosted on Netlify (not GitHub Pages).
- Q4, v01: no custom domain in this work; you handle it.
- Q5, v01: static `index.html` plus Tailwind v4 CLI to a committed `style.css`, `package.json` inside `website/`.
- Q6, v01: reuse the dark theme and layout; new accent color; I draft a new SVG logo/favicon.
- Q7, v01: sections hero, terminal example, features, how it works, quick start, options, short CI usage, and a link card to supported setups.
- Q8, v01: hand-written copy, manual updates; an issue is filed for a `--help`-vs-options-table check.
- Q9, v02: deploys through a build hook called from the release workflow.
- Q10, v02: I write `website/netlify.toml`; you create and link the Netlify site.
- Q11, v02: the version badge is filled at load from the GitHub API, with a static "latest" fallback.
- Q12, v02: the install `curl` is pinned to the latest version tag, filled by the same fetch.
- Q13, v02: tagline wording is yours; reopened as Q16.
- Q14, v02: the terminal example is a real `--dry-run` capture.
- Q15, v02: the Q8 issue is filed now, as #88, labeled `needs-triage`.
- Q16, v03: tagline is "Semantic release in one bash script. No npm tree. Just git, bash and gh."
- Q17, v03: Netlify auto-builds are stopped, and `release.yml` gets a `workflow_dispatch` input `deploy-site` that calls the hook without a release.
- Q18, v03: the hook is called from a separate job `needs: publish`, gated on a release having been cut.
- Q19, v03: when the version fetch fails, the install command shows a `<latest-tag>` placeholder and a link to the releases page.

Superseded: Q13 by Q16 (the "No dependencies" wording). Q9 was refined by Q17 and Q18 (the hook's triggers), not replaced.

## Where the outcome lives

The scope and decisions were posted as the first comment of [#89](https://github.com/JeremieLitzler/semantic-release-script/issues/89). The options-table check is [#88](https://github.com/JeremieLitzler/semantic-release-script/issues/88).

## Decided without being grilled

Flagging so you can object before anything is built:

- The accent color is green (it was my suggestion in Q6; you chose that option but did not name a color).
- The page is in English, like the README and the reference.
- Dark theme only, no light-mode toggle, like the reference.
- No new `CONTEXT.md` term and no ADR came out of this session; the Netlify-hook choice looked reversible enough not to qualify. Say so if you want one.
- The `deploy-site` dispatch input is a change to `release.yml`'s inputs, whose publish flow uses a pinned `release.sh`; the pin itself is untouched.
- Breaking the work into issues and the implementation are separate steps.
