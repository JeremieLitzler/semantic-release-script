#!/usr/bin/env bats
#
# The promotion website: the committed page, the Netlify config, the deploy
# wiring in the release workflow, and the version-fill script. Every test reads
# committed files; none touches the network or Netlify.

load helpers/common

SITE="${TESTS_DIR}/../website"
WORKFLOW="${TESTS_DIR}/../.github/workflows/release.yml"

# missing_local_references <html> — prints each local href/src of <html> that
# names no file of the site folder.
missing_local_references() {
  local ref path
  grep -oE '(href|src)="[^"]+"' "$1" | sed -E 's/^(href|src)="(.*)"$/\2/' |
    while read -r ref; do
      case "$ref" in
        http://* | https://* | mailto:* | \#*) continue ;;
      esac
      path="${ref%%[?#]*}"
      path="${path#./}"
      [[ -e "${SITE}/${path#/}" ]] || echo "$ref"
    done
}

# site_node <script> <arg> — runs <script> under node with the site folder as
# the working directory and <arg> as process.argv[1]. A WSL without node of its
# own still has the Windows one as node.exe, which takes a relative path.
site_node() {
  local node=node
  command -v node >/dev/null 2>&1 || node=node.exe
  (cd "$SITE" && "$node" -e "const m = require('./version-fill.js'); $1" "$2")
}

# fill <json> — fillVersion on a parsed API response, as JSON.
fill() {
  site_node 'console.log(JSON.stringify(m.fillVersion(JSON.parse(process.argv[1]))))' "$1"
}

# resolve_with <fetch-js> — resolveVersion with a fake fetch, as JSON.
resolve_with() {
  site_node 'm.resolveVersion(eval(process.argv[1])).then((r) => console.log(JSON.stringify(r)))' "$1"
}

# --- the page ----------------------------------------------------------------

@test "the page carries the tagline, the requirements and the title" {
  run cat "${SITE}/index.html"

  assert_output --partial "Semantic release in one bash script. No npm tree. Just git, bash and gh."
  assert_output --partial "<title>semantic-release-script"
  assert_output --partial 'name="description"'
  assert_output --partial 'bash</code> 4+'
}

@test "the page has every agreed section and a nav link to each" {
  local id
  for id in terminal-example features how-it-works quick-start options ci; do
    run grep -F "id=\"${id}\"" "${SITE}/index.html"
    assert_success
    run grep -F "href=\"#${id}\"" "${SITE}/index.html"
    assert_success
  done
}

@test "the page links the repository and the supported setups document" {
  run cat "${SITE}/index.html"

  assert_output --partial 'href="https://github.com/JeremieLitzler/semantic-release-script"'
  assert_output --partial 'docs/supported-setups.md'
}

@test "the page does not name the npm package it is an alternative to" {
  run grep -ciE 'npmjs|npm install|@semantic-release|semantic-release/' "${SITE}/index.html"

  assert_output "0"
}

@test "the page carries the social metadata and the favicon set" {
  run cat "${SITE}/index.html"

  assert_output --partial 'property="og:title"'
  assert_output --partial 'property="og:description"'
  assert_output --partial 'property="og:image"'
  assert_output --partial 'name="twitter:card"'
  assert_output --partial 'type="image/svg+xml"'
  assert_output --partial 'rel="shortcut icon"'
  assert_output --partial 'rel="apple-touch-icon"'
  assert_output --partial 'rel="manifest"'
}

@test "every local href and src resolves to a file of the site folder" {
  run missing_local_references "${SITE}/index.html"

  assert_output ""
}

@test "the favicon set and the manifest icons exist" {
  local f
  for f in favicon.svg favicon.ico favicon-96x96.png apple-touch-icon.png \
    web-app-manifest-192x192.png web-app-manifest-512x512.png; do
    [[ -s "${SITE}/icons/${f}" ]] || fail "missing icons/${f}"
  done
}

@test "the badge and the install command have a fallback in the markup, for a visitor without JavaScript" {
  run cat "${SITE}/index.html"

  assert_output --regexp 'data-version-badge>latest<'
  assert_output --partial '/&lt;latest-tag&gt;/scripts/release/release.sh'
  assert_output --partial 'data-install-fallback'
  assert_output --partial 'releases page'
}

@test "no install command in the markup tracks a branch" {
  run grep -E 'raw.githubusercontent.com/JeremieLitzler/semantic-release-script/(main|master|HEAD)/' "${SITE}/index.html"

  assert_failure
}

@test "the options table has a row for every flag of the help" {
  local flag
  for flag in --yes --dry-run --local --since --to --trunk --level --level-from --notes --changelog --summary --check --help; do
    run grep -F "code-inline\">${flag}" "${SITE}/index.html"
    assert_success
  done
}

# --- the Netlify config --------------------------------------------------------

@test "netlify.toml, at the repository root where Netlify reads it, states the base and publish directories and no build command" {
  run cat "${TESTS_DIR}/../netlify.toml"

  assert_output --partial 'base = "website"'
  assert_output --partial 'publish = "."'
  assert_output --partial 'command = ""'
  assert_output --partial 'NODE_ENV = "production"'
}

@test "the site's tooling stays in its folder: the repository root has no package.json" {
  [[ -f "${SITE}/package.json" ]]
  [[ ! -e "${TESTS_DIR}/../package.json" ]]
}

# --- the deploy wiring ---------------------------------------------------------

@test "release.yml offers deploy-site as a separate dispatch action" {
  run cat "$WORKFLOW"

  assert_output --partial 'options: [preview, publish, deploy-site]'
}

@test "the deploy-site job runs after publish, gated on a release having been cut, with the secret" {
  run sed -n '/^  deploy-site:/,$p' "$WORKFLOW"

  assert_success
  assert_output --partial 'needs: publish'
  assert_output --partial "needs.publish.outputs.released == 'yes'"
  assert_output --partial "inputs.action == 'deploy-site'"
  assert_output --partial 'secrets.NETLIFY_BUILD_HOOK'
  assert_output --partial 'curl -fsS -X POST'
}

@test "the publish job exports whether a release was cut, and knows nothing of Netlify" {
  run sed -n '/^  publish:/,/^  deploy-site:/p' "$WORKFLOW"

  assert_output --partial 'released: ${{ steps.release.outputs.released }}'
  refute_output --partial 'NETLIFY'
}

@test "the release.sh pin of the workflow is unchanged" {
  run grep -E '^  RELEASE_SCRIPT_REF: ' "$WORKFLOW"

  assert_output "  RELEASE_SCRIPT_REF: 1e09fa09c72cfcd064a77e0d4a86f52dfd46e49c"
}

@test "the guard and its ref refusal are unchanged by the deploy-site action" {
  run sed -n '/^  guard:/,/^  test:/p' "$WORKFLOW"

  assert_output --partial "inputs.action == 'publish'"
  assert_output --partial 'publish runs from main or a release/* branch'
}

# --- the version fill ----------------------------------------------------------

@test "a normal response fills the badge and the pinned command" {
  run fill '{"tag_name":"v1.2.3","name":"v1.2.3"}'

  assert_success
  assert_equal "$(jq -r .badge <<<"$output")" "v1.2.3"
  assert_equal "$(jq -r .command <<<"$output")" \
    "curl -fsSL https://raw.githubusercontent.com/JeremieLitzler/semantic-release-script/v1.2.3/scripts/release/release.sh -o release.sh && chmod +x release.sh"
  assert_equal "$(jq -r .ok <<<"$output")" "true"
}

@test "a response without a tag yields the latest badge and the placeholder command" {
  run fill '{"name":"no tag here"}'

  assert_success
  assert_equal "$(jq -r .badge <<<"$output")" "latest"
  assert_equal "$(jq -r .command <<<"$output")" \
    "curl -fsSL https://raw.githubusercontent.com/JeremieLitzler/semantic-release-script/<latest-tag>/scripts/release/release.sh -o release.sh && chmod +x release.sh"
}

@test "a tag that is not a version tag is not trusted into the command" {
  run fill '{"tag_name":"main"}'
  assert_equal "$(jq -r .badge <<<"$output")" "latest"

  run fill '{"tag_name":"v1.0.0/../../evil"}'
  assert_equal "$(jq -r .badge <<<"$output")" "latest"

  run fill 'null'
  assert_equal "$(jq -r .badge <<<"$output")" "latest"
}

@test "a failed fetch yields the fallback, never an unpinned URL" {
  run resolve_with '() => Promise.reject(new Error("offline"))'

  assert_success
  assert_equal "$(jq -r .badge <<<"$output")" "latest"
  assert_equal "$(jq -r .tag <<<"$output")" "<latest-tag>"
  refute_output --regexp 'semantic-release-script/(main|master|HEAD)/'
}

@test "a non-2xx response yields the fallback" {
  run resolve_with '() => Promise.resolve({ ok: false, status: 403 })'

  assert_equal "$(jq -r .badge <<<"$output")" "latest"
}

@test "a malformed body yields the fallback" {
  run resolve_with '() => Promise.resolve({ ok: true, json: () => Promise.reject(new SyntaxError("bad")) })'

  assert_success
  assert_equal "$(jq -r .badge <<<"$output")" "latest"
}

@test "a good fetch fills the badge and the tag" {
  run resolve_with '() => Promise.resolve({ ok: true, json: () => Promise.resolve({ tag_name: "v0.5.0" }) })'

  assert_equal "$(jq -r .badge <<<"$output")" "v0.5.0"
  assert_equal "$(jq -r .tag <<<"$output")" "v0.5.0"
}
