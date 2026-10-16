// version-fill.js — fills the version badge and the pinned install command
// from the latest GitHub release. The pure part (fillVersion, resolveVersion)
// is what the bats suite runs under node; the DOM part runs only in a browser.
(function (root) {
  "use strict";

  var REPO = "JeremieLitzler/semantic-release-script";
  var API = "https://api.github.com/repos/" + REPO + "/releases/latest";
  var RELEASES_URL = "https://github.com/" + REPO + "/releases";
  var PLACEHOLDER = "<latest-tag>";
  var TAG = /^v\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.+-]+)?$/;

  function installCommand(tag) {
    return (
      "curl -fsSL https://raw.githubusercontent.com/" + REPO + "/" + tag +
      "/scripts/release/release.sh -o release.sh && chmod +x release.sh"
    );
  }

  // fillVersion — what the page shows for a parsed API response. Anything but
  // an object carrying a version tag yields the fallback: the "latest" badge
  // and the placeholder command, never a command that tracks a branch.
  function fillVersion(release) {
    var tag = release && typeof release === "object" ? release.tag_name : null;
    if (typeof tag === "string" && TAG.test(tag)) {
      return { ok: true, badge: tag, tag: tag, command: installCommand(tag), releasesUrl: RELEASES_URL };
    }
    return { ok: false, badge: "latest", tag: PLACEHOLDER, command: installCommand(PLACEHOLDER), releasesUrl: RELEASES_URL };
  }

  // resolveVersion — fetches the latest release with the given fetch and
  // never rejects: a network error, a non-2xx status and a body that is not
  // JSON all land on the fallback.
  function resolveVersion(fetchImpl) {
    return Promise.resolve()
      .then(function () { return fetchImpl(API, { headers: { Accept: "application/vnd.github+json" } }); })
      .then(function (res) {
        if (!res || !res.ok) { return null; }
        return res.json();
      })
      .catch(function () { return null; })
      .then(fillVersion);
  }

  function apply(doc, result) {
    var badge = doc.querySelectorAll("[data-version-badge]");
    var cmd = doc.querySelectorAll("[data-install-command]");
    var note = doc.querySelectorAll("[data-install-fallback]");
    var i;
    for (i = 0; i < badge.length; i++) { badge[i].textContent = result.badge; }
    for (i = 0; i < cmd.length; i++) { cmd[i].textContent = result.command; }
    for (i = 0; i < note.length; i++) { note[i].hidden = result.ok; }
  }

  var api = { fillVersion: fillVersion, resolveVersion: resolveVersion, installCommand: installCommand };

  if (typeof module !== "undefined" && module.exports) {
    module.exports = api;
  } else if (root.document && root.fetch) {
    resolveVersion(root.fetch.bind(root)).then(function (result) { apply(root.document, result); });
  }
})(typeof window !== "undefined" ? window : globalThis);
