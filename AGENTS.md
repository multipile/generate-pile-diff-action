# AGENTS.md

## Piles

This repository declares piles: subtrees that each have a `.pile/` directory whose `intent.md` says why they are one thing. Read a pile's intent before you change the pile, and keep it true in the same commit. `pile doctor` (or `piles.sh check` of the gitrepo plugin) must pass before a commit.

## What this is

A composite GitHub Action, `multipile/generate-pile-diff-action`. `action.yml` at the top is what users see. Each step runs a script in `scripts/`. The default prompt is in `templates/`. The README documents every input and output: change it in the same commit as `action.yml`.

## Rules

- **Bash only.** No Node, no build, and no `dist/`. A script may use only what every GitHub-hosted runner has: bash, git, `gh`, `jq`, `python3`, and coreutils (or their macOS equivalents). It must work on Linux and macOS.
- **No `${{ }}` inside `run:`.** Pass every value through `env:`, so text from a pull request is never run as shell.
- **What the pull request's author wrote is untrusted.** It reaches the prompt only through `render.sh`'s cleaning, and only inside its blocks.
- **The action reviews nothing.** It makes the prompt. What an agent does with the prompt is the template's business, and the user's.

## Check a change

```sh
shellcheck scripts/*.sh test/*.sh
```

CI runs the action on a repository that `test/fixture.sh` makes, on each runner and with each kind of `pile-version`. On a pull request, it also runs the action on the pull request itself.

## Release

`main` only changes through a pull request. A release is a tag `vX.Y.Z` on `main`, a GitHub release, and the tag `v0` moved to the same commit. When `pile` releases a new minor version, the default of `pile-version` moves to it, in a release of its own.
