# Grilling round v02 — A promotion website for semantic-release-script

## Settled in v01

- Q1: the audience is developers who want a semantic release without npm, and the goal is "vendor `release.sh` into my repo" (stars and comparisons are secondary call-outs).
- Q2: the site lives in `website/` at the repo root.
- Q3: hosted on Netlify, because that is where you host your projects (not GitHub Pages).
- Q4: no custom domain in the site's work; you will take care of it yourself.
- Q5: hand-written static `index.html` plus Tailwind v4 CLI compiling `tailwind.css` to a committed `style.css`, with the `package.json` kept inside `website/`.
- Q6: dark theme and layout reused, a new accent color, and a new logo/favicon that I draft as SVG for your review.
- Q7: sections 1 to 6 (hero, terminal example, features, how it works, quick start, options) plus a short section 8 (CI usage), and section 7 (supported setups) as a single link card. The reference's "output" and "email" sections are dropped.
- Q8: hand-written copy, accept manual updates; a GitHub issue for the `--help`-vs-options-table check (option B) is to be filed. When I file it is Q15 below.

Correction to my v01 preamble: I wrote that this repo has no workflow. That was wrong. `.github/workflows/release.yml` exists (preview on push to `main`, publish on `release/**` or manual dispatch) and `test.yml` too. It matters for Q9 and Q11. I also checked the 4 steps against `release.sh`: Step 1 evaluate the version, Step 2 release notes, Step 3 create and push the tag, Step 4 publish the release. The "how it works" section follows these.

## Q9 - How a deploy reaches Netlify

The reference triggers a Netlify build hook from its release workflow, so the site redeploys only when a release is cut. Here the release workflow publishes from `release/**` branches and only holds `contents: write`.

A. Netlify watches the repo: base directory `website/`, no build command (the compiled `style.css` is committed), publish directory `.`. Every push to `main` that touches `website/` deploys, with an `ignore` command in `netlify.toml` to skip pushes that don't.
B. A build hook called from `release.yml`, like the reference: deploys only on release; needs a `NETLIFY_BUILD_HOOK` secret and a new workflow step.
C. Both: Netlify watches the repo, and the release also triggers a deploy.

➡️ Recommendation: A. A site edit should ship when merged, not wait for the next release, and A adds no secret and no change to the release workflow that your pinned `release.sh` flow depends on. B only makes sense if the site must mirror released state exactly, which Q11 can solve differently.

### Answer to Q9

B

---

## Q10 - Who sets up what on Netlify

I can write `website/netlify.toml` (base, publish, ignore rule, headers) and the docs. Creating the Netlify site and linking it to the GitHub repo needs your account.

A. I write `netlify.toml`; you create and link the Netlify site, using the settings I list in the PR description.
B. No `netlify.toml`: you configure everything in the Netlify dashboard.

➡️ Recommendation: A. The settings live in the repo and are reviewable, and the dashboard then only needs the repo link.

### Answer to Q10

A

---

## Q11 - How the version badge stays current

The reference rewrites the badge with `sed` and commits to `main` from the release workflow with `[skip ci] [deploy]`. Here the publish job checks out a `release/**` commit with a read-only default token and then deletes that branch. A commit back to `main` would need a write token on a possibly protected branch.

A. The page fetches the latest release from the GitHub API at load (`/repos/JeremieLitzler/semantic-release-script/releases/latest`) and fills the badge; the static markup says "latest" if the fetch fails. No commit, no workflow change.
B. A static shields.io image badge (`github/v/release`): no JS, no commit; the look differs from the reference's `.badge`.
C. A workflow step commits the version into `index.html` on `main`, like the reference.
D. A hand-written version, updated by hand.

➡️ Recommendation: A. It keeps the site's look, needs no token or branch permission, and works even if the site is never redeployed. The unauthenticated API limit (60 requests per hour per IP) is fine for a badge.

### Answer to Q11

A

---

## Q12 - What the install command shows

Quick start must tell a visitor how to get `release.sh`. This repo's own workflow fetches it with `curl` from `raw.githubusercontent.com` pinned to a commit SHA, with the comment "Pin the SHA, not the tag name: a tag can be moved, a SHA cannot."

A. A `curl` pinned to the latest version tag, the tag filled in by the same fetch as the badge (needs Q11 = A).
B. A `curl` pinned to a literal `<commit-sha>` placeholder, with a sentence on why you pin.
C. A `curl` from `main`, unpinned.
D. `git clone` the repo and copy the file.

➡️ Recommendation: A if Q11 = A, since it is copy-pasteable and moves with each release; otherwise B. C contradicts the project's own advice to pin. Your project's README pitches vendoring, so I would also check how README words it before writing the copy.

### Answer to Q12

A

---

## Q13 - Tagline and positioning

The reference's tagline is "Find broken links before your users do." Draft for this project: "Semantic release in one bash script. No npm tree." with a subline: "Reads your conventional commits, picks the version, writes the notes, tags, and publishes — with a human gate before each step."

A. Use the draft, and never name `semantic-release` (npm) on the page.
B. Use the draft, and name `semantic-release` once in the subline as the thing this replaces.
C. You write the tagline.

➡️ Recommendation: A. Naming the npm package invites a feature comparison you do not want (Q1 settled that this is not the page's spine). The "no npm tree" phrase already carries the contrast.

### Answer to Q13

C: "Semantic release in one bash script. No npm tree. No dependencies."

---

## Q14 - Where the terminal example comes from

The reference shows a terminal block. For this project it would show a `--dry-run`.

A. A real `--dry-run` captured from this repo (or the fixture repo the tests use), pasted as static HTML, with the output trimmed only for length.
B. A hand-written, plausible-looking output.

➡️ Recommendation: A. A promotion page for a release tool that shows output the tool never printed would be the one thing a skeptical visitor could catch. The cost is that the block freezes at one version of the output; Q8 already accepts that kind of drift.

### Answer to Q14

A

---

## Q15 - Filing the Q8 issue

You asked for an issue for the `--help`-vs-options-table check. Filing it is outward-facing (it lands in `JeremieLitzler/semantic-release-script`).

A. File it now, labeled `needs-triage`.
B. File it at the end of this session, together with the website's own issue(s), once the plan is agreed.
C. File it when the website's first PR merges, since the check cannot exist before the options table does.

➡️ Recommendation: B. Its text is better once the options table exists in the plan, and it can be filed in one pass next to the main issue, with the `needs-triage` label.

### Answer to Q15

A
