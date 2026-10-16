# The website

The one-page promotion site, deployed on Netlify. Hand-written static HTML, with Tailwind v4 compiled into a committed `style.css`. Its tooling stays in this folder: the repository root stays Node-free, and this folder is not part of what a consumer vendors.

## Edit

- `index.html`: the page. `version-fill.js` fills the version badge and the pinned install command from the latest GitHub release, and falls back to `latest` and a `<latest-tag>` placeholder.
- `tailwind.css`: the theme and components. After editing it or the classes in `index.html`, rebuild the stylesheet and commit `style.css`:

  ```bash
  cd website
  npm install
  npm run build
  ```

- Preview: open `index.html` in a browser, or run `npx serve .` here.

CI does not check that `style.css` matches a fresh build, so rebuild it before you commit.

## Deploy

`netlify.toml` sits at the repository root, the only place Netlify reads it without a dashboard base directory. It states the base and publish directories and that there is no build command. An `ignore` rule skips every build that is not a build hook build, so pushes and pull requests do not deploy. The release workflow calls the Netlify build hook after a release is cut, and its `deploy-site` dispatch input calls it without one.
