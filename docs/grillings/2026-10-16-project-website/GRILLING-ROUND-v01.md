# Grilling round v01 — A promotion website for semantic-release-script

Facts gathered before asking. The reference site (`deadlinkprobe_main/website/`) is a single static `index.html` styled with Tailwind v4 (`tailwind.css` compiled to `style.css`), dark theme (`#0d1117`), mono font, a fixed nav, a hero with logo + badges + tagline, then sections: terminal example, features, how it works, quick start, options, output, email. It carries a version badge that its release workflow rewrites with `sed`, commits with `[skip ci] [deploy]`, then triggers a Netlify build hook. This repo has no `website/` folder, no workflow, no homepage URL set on GitHub, a GPL-3.0 license, and a single `scripts/release/release.sh`.

## Q1 - Audience and goal

Who is the site for, and what should a visitor do after reading it?

A. Developers who want a semantic release without npm: goal is "vendor `release.sh` into my repo" (copy/curl the script, read the README).
B. Same audience, but the goal is "star the repo / follow the project".
C. A broader audience (teams evaluating release tooling), with a comparison against semantic-release (npm) as the centerpiece.

➡️ Recommendation: A. The project is a single vendorable script, so the one action that matters is "get the script and run a dry run". Stars and comparisons can be secondary call-outs, not the page's spine.

### Answer to Q1

A

---

## Q2 - Where the site lives in the repo

A. `website/` at the repo root, mirroring the reference.
B. `docs/` (publishable as-is by GitHub Pages from `/docs`), next to the existing `docs/adr`, `docs/grillings`, etc.
C. A separate repo.

➡️ Recommendation: A. `docs/` already holds agent and decision records, and mixing a published site into it would publish internal grilling files; a `website/` folder mirrors the reference and keeps the vendoring story clean (the site is not part of what consumers copy).

### Answer to Q2

A

---

## Q3 - Hosting and deploy

The reference uses Netlify with a build hook called from the release workflow. This repo has no workflow yet.

A. GitHub Pages, deployed by a GitHub Actions workflow publishing `website/`.
B. Netlify, like the reference (needs a Netlify site and a `NETLIFY_BUILD_HOOK` secret).
C. Something else (Cloudflare Pages, Vercel...).

➡️ Recommendation: A. Zero external account, the repo is already on GitHub, and the URL (`jeremielitzler.github.io/semantic-release-script`) is a natural `homepageUrl`. Choose B only if you want the same pipeline as deadlinkprobe for consistency.

### Answer to Q3

B, because that's where I host my projects.

---

## Q4 - Custom domain

A. None for now: use the default hosting URL.
B. A custom domain (tell me which).

➡️ Recommendation: A. A domain can be added later with a `CNAME` and no change to the page; only `og:` and canonical URLs would need a one-line update.

### Answer to Q4

A, I'll take care of this.

---

## Q5 - Tech stack

A. Same as the reference: hand-written static `index.html` + Tailwind v4 CLI compiling `tailwind.css` to a committed `style.css`.
B. Static HTML + Tailwind via CDN script (no build step, no `package.json`).
C. Plain hand-written CSS, no Tailwind.
D. A static-site generator (Astro, Eleventy...).

➡️ Recommendation: A. "Similar likeness" is easiest to honor by reusing the same classes and CSS, and a committed `style.css` means the deploy needs no Node. The cost is a `package.json` in a pure-bash repo, kept inside `website/` so the root stays Node-free.

### Answer to Q5

A

---

## Q6 - Branding

The reference has a logo (probe icon), a two-color wordmark (`dead` red, `link` cyan) and a cyan-accented dark theme. This project has no logo or color identity.

A. Reuse the dark theme and layout, pick a new accent color and a simple wordmark in text only (no logo).
B. Same, plus a new logo/favicon that I draft as SVG for your review.
C. You provide a logo and palette.

➡️ Recommendation: B. A favicon and og image are needed anyway for a shareable link, and an SVG draft costs little; you can swap it later. Suggested accent: green (a release/"go" connotation), distinct from deadlinkprobe's cyan/red.

### Answer to Q6

B

---

## Q7 - Sections

The reference's sections map to this project like so. Which do you want?

1. Hero: name, tagline, badges (version, bash 4+, GPL-3.0), install CTA
2. Terminal example: a `--dry-run` output (version, notes, gates)
3. Features: conventional commits, human gate per step, `--dry-run`, half-published resume, `--level-from` branch names, `--check` setup report, no npm
4. How it works: the 4 steps (read commits, decide version, write notes, tag + GitHub release)
5. Quick start: vendor + run
6. Options: the CLI flags table
7. Supported setups (link to `docs/supported-setups.md`)
8. CI usage (dry-run preview in a runner, `--yes`)

➡️ Recommendation: 1 to 6 plus a short 8, with 7 as a single link card. Drop the reference's "output" and "email" sections: there is no CSV or mail here. I would confirm step count (4) against the README before writing.

### Answer to Q7

Go for Recommendation

---

## Q8 - Content source and drift

Options, flags and behaviors are documented in README and `release.sh`. A hand-written page will drift when they change.

A. Hand-written copy; accept manual updates, only the version badge is automated.
B. Hand-written copy, plus a test or CI check that fails if a flag in `release.sh --help` is missing from the site's options table.
C. Generate the options table from `release.sh --help` at build time.

➡️ Recommendation: A for the first version. B or C is worth a later issue once the page exists; building tooling before the page would delay the actual goal.

### Answer to Q8

A, but add issue for B
