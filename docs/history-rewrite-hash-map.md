# History rewrite hash map (#32)

Old `main` tip `3471cf7` is kept as branch `backup/pre-rewrite-main`. Dropped: the 14 dummy commits `fb24541`..`0adb5b2`, the merge `5106ecd`, and the commit that only renamed a scraper file. The scraper replay files are removed from every commit that carried them.

| Old | New | Subject |
| --- | --- | --- |
| `39cbf35` | `39cbf35` | Initial commit |
| `5b6e626` | `43274bc` | feat: add the semantic release script (#1) |
| `98bb9fa` | `02de0dd` | docs: explain how to cut the first release (#1) |
| `76da044` | `fb3cc28` | test: record the dummy data set and the release output (#1) |
| `69bca42` | `0e5b77c` | feat: replay historical commit ranges to rebuild past releases |
| `9283f36` | `b72c717` | fix: dedupe release notes by issue, keeping the most significant category |
| `55f239c` | `f460d0f` | docs: reconstruct french-gas-stations-scraper release history |
| `de0a43a` | `dc3096a` | fix: resolve current version from --since when it is not a tag |
| `00708f7` | `b75d08c` | test: replace real-GitHub test data with fixture-built bats suites (#12) |
| `303ae78` | `49d580a` | refactor: resolve the baseline in one function (#18) |
| `ea5a488` | `8164be0` | refactor: give the unknown-ref refusal one home (#18) |
| `62a5150` | `8f415dc` | feat: resolve the trunk from GitHub's default branch (#19) |
| `22bb0d5` | `f6eb31d` | docs: refresh the two header comments the trunk change left behind |
| `499fc41` | `ff77ca9` | feat: define the exit codes, one of them for nothing to release (#20) |
| `8704869` | `395d528` | feat: skip the human gates under --dry-run (#21) |
| `55597bd` | `4986344` | feat: refuse to compute a version from a shallow clone (#23) |
| `692186b` | `00d1979` | feat: refuse to compute a version when the tag fetch fails (#24) |
| `2f4f371` | `6edecbd` | fix: carry git's own reason into the stale-tags refusal (#24) |
| `322691b` | `6b1aa61` | feat: refuse to tag a ref the trunk does not contain (#25) |
| `0ba3879` | `33bd686` | refactor: name baseline_refusal's second detail for what it holds (#25) |
| `12b4020` | `a0fdd5f` | refactor: rename baseline_refusal to refusal (#45) |
| `2a1a614` | `00afe57` | fix: fail a gate that cannot open a terminal (#27) |
| `01912cd` | `7eb8663` | docs: define gate and preview in the glossary |
| `0da12ca` | `225092b` | docs: name the gate with no terminal where the code is declared |
| `b973e46` | `dc8fd42` | test: ask setsid for --wait rather than for its name |
| `447b6ca` | `8dd47d6` | feat: resume a half-published release at step 4 (#28) |
| `402696b` | `ea2db10` | fix: weigh the guards on a resume, and its two lookups (#28) |
| `f9af138` | `340701b` | docs: name the repository as it is now, not as it was |
| `ea4fad1` | `ed1ba4b` | feat: write a machine-readable release summary with --summary (#29) |
| `fe7059c` | `b607b47` | docs: rule maintenance lines out and name them in the glossary (#13) |
| `b1285b7` | `f5c6537` | docs: decide on a --check mode and name the setup report (#14) |
| `d7ae57b` | `c6dd600` | refactor: preflight checks return results instead of dying (#56) |
| `1213775` | `88f5fef` | test: pin the preflight failures that had no test (#56) |
| `eaaa839` | `051b3c8` | test: pin the preflight exit code and its first-failure order (#56) |
| `d656683` | `8802ba9` | test: keep bash on the PATH that hides a tool (#56) |
| `eb869ab` | `c8ca44e` | feat: --check prints the environment setup report (#57) |
| `923a0e5` | `ff9aca8` | test: pin the --check lines of the usage text (#57) |
| `c91b7b2` | `03bc6a5` | feat: --check weighs the tag and version guards against the target (#58) |
| `498655f` | `3a6c79d` | fix: spell out the unit separator, and give tag-taken a fix (#58) |
| `520e938` | `acfcf59` | fix: --changelog writes the release notes under each heading (#36) |
| `6497ec0` | `ce681fa` | feat: refuse a release when the baseline is not the highest version tag (#22) |
| `3471cf7` | `2d5e059` | fix: hold the baseline guard to version tags, and list only the stranded ones above it (#22) |
