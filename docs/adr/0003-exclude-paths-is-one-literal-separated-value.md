# `--exclude-paths` is one `|`-separated value of literal, root-anchored entries

`release.sh` takes `--exclude-paths <a|b>` to keep **excluded commits** out of the notes and the bump (#107, #110).

## The contract

The option is given once, with one value whose entries are separated by `|`. An entry is a literal path anchored at the repository root, a folder or a file, matched by whole path component and case-sensitively. It covers itself and everything under it.

## Alternatives declined

- **A repeatable option** (`--exclude-path output --exclude-path sources`). A repeated option has no natural place in a workflow that builds one command line, and a second occurrence that silently replaced the first would hide a list. One value makes a repeat a mistake, refused with exit `1`.
- **Globs.** They need a dialect (is `*` one component or many, does `**` exist), and a wrong glob excludes more than named. A literal entry excludes exactly what was listed.
- **Regex.** The same dialect problem, and `|` would then be both the list separator and regex alternation. Regex is left to its own issue.

The cost, accepted: a path containing `|` cannot be excluded, and the value must be quoted in a shell.
