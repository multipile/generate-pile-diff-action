# generate-pile-diff-action

A GitHub Action for repositories that declare piles. On a pull request it runs [`pile gitdiff`](https://github.com/multipile/pile-cli), which arranges the change by pile, each with what the pile is for. It does three things with the answer:

- It keeps **one comment** on the pull request with the piles it changed, and edits that comment on every push.
- It writes the same Markdown to the **job summary**.
- It fills a **prompt** with it, and hands the prompt on for an agent to review the pull request pile by pile.

The action reviews nothing itself. You pass the prompt to the agent action of your choice, such as [`anthropics/claude-code-action`](https://github.com/anthropics/claude-code-action), and that action writes the review and posts it.

## Use it

```yaml
name: piles
on:
  pull_request:
    types: [opened, synchronize, reopened, ready_for_review]

jobs:
  piles:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write # for the comments
      id-token: write # for claude-code-action
    steps:
      # The pull request's own head, with its history, so pile can find
      # where it left its base.
      - uses: actions/checkout@v5
        with:
          ref: ${{ github.event.pull_request.head.sha }}
          fetch-depth: 0

      - id: piles
        uses: multipile/generate-pile-diff-action@v0

      - if: steps.piles.outputs.changed-piles != '0' && !github.event.pull_request.draft
        uses: anthropics/claude-code-action@v1
        env:
          GH_TOKEN: ${{ github.token }} # for pile-review-comment
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          github_token: ${{ github.token }}
          plugin_marketplaces: https://github.com/multipile/multipile-agent-plugins.git
          plugins: gitrepo@multipile
          prompt: ${{ steps.piles.outputs.prompt }}
          # What pile guide review runs, and pile-review-comment to post.
          claude_args: |
            --allowedTools "Read,Glob,Grep,Write,Bash(pile:*),Bash(pile-review-comment:*),Bash(command -v pile),Bash(git fetch:*),Bash(git diff:*),Bash(git log:*),Bash(git show:*),Bash(git merge-base:*),Bash(gh pr view:*),Bash(gh pr diff:*)"
```

Two commands stay on the `PATH` for the rest of the job, for the agent:

- `pile`, so the agent can read the repository by pile.
- `pile-review-comment <file>`, which keeps the review's comment on this pull request: one comment marked `<!-- pile review -->`, edited on every run. It is all the agent needs to post. So the agent gets no `gh api` and no `gh pr comment`, and can't write anywhere else. It needs `GH_TOKEN` in the agent's step.

The action runs no agent, so it doesn't configure one. Which tools the agent may use is set in the agent's own step. The list above is what the default prompt leads to:

- `pile-review-comment`, which the prompt names.
- What `pile guide review` runs: `pile`, git commands that read, and `gh pr view`.
- Reading files, and writing the review's file.

When a release of `pile` changes its guide, the list may need to change with it.

Only the comment needs `pull-requests: write`. Without it, or with `comment: false`, `contents: read` is enough.

### The agent in another job

To run the agent in a job of its own, upload the prompt as an artifact:

```yaml
      - uses: actions/upload-artifact@v4
        with:
          name: pile-review-prompt
          path: ${{ steps.piles.outputs.prompt-file }}
```

The other job downloads it, and passes the file's contents as its prompt.

### Pull requests from forks

A pull request from a fork runs with a read-only token and no secrets. There, the action still makes the prompt. It skips the comment with a warning, and an agent that needs a secret can't run.

To review such pull requests, split the work in two:

1. A `pull_request` workflow runs this action, with `comment: false`, and uploads the prompt and the Markdown as an artifact.
2. A `workflow_run` workflow downloads them, posts the comment, and runs the agent.

The second workflow must not check out or run the pull request's code. See GitHub's [Preventing pwn requests](https://securitylab.github.com/resources/github-actions-preventing-pwn-requests/).

## Which `pile`

| `pile-version` | Installs |
| --- | --- |
| *(the default)* | the newest patch of the major.minor this release of the action was made for |
| `0.1` | the newest `v0.1.x` that is not a prerelease |
| `latest` | the newest release |
| `0.1.3`, `v0.1.3` | exactly that release |

The release is checked against its `SHA256SUMS` before it runs. `pile-ref` builds `pile` from a branch or tag of `multipile/pile-cli` instead, to try a version that is not released yet. It needs `cargo`.

## Inputs

| Input | Default | |
| --- | --- | --- |
| `pile-version` | `0.1` | which `pile` to install, as above |
| `pile-ref` | | build `pile` from this branch or tag instead |
| `base` | `origin/<the pull request's base branch>` | what the pull request is compared with, from where it left it (`pile gitdiff <base>...HEAD`) |
| `working-directory` | `.` | the repository to read |
| `template` | the action's own | a prompt template of your own, as a path from the working directory |
| `extra-instructions` | | text put in at `{{extra_instructions}}` |
| `comment` | `true` | keep one comment on the pull request with the piles it changed |
| `comment-author` | `github-actions[bot]` | whose comments are edited, the action's and the review's: set it when they are posted with a token other than `GITHUB_TOKEN` |
| `summary` | `true` | write the piles it changed to the job summary |
| `github-token` | `${{ github.token }}` | downloads the release and posts the comment |

## Outputs

| Output | |
| --- | --- |
| `prompt` | the prompt |
| `prompt-file` | the prompt's path |
| `markdown-file` | `pile gitdiff`'s answer in Markdown |
| `json-file` | `pile gitdiff`'s answer in JSON |
| `changed-piles` | how many piles the pull request changed |
| `pile-version` | the version of `pile` installed |
| `comment-url` | the comment's URL, when there is one |

## The comment

The Markdown starts with the line `<!-- pile gitdiff -->`. The action edits the comment by `comment-author` that starts with it. If there is no such comment, it adds one. When nothing changed, the comment is left alone.

## The prompt

The action's own template asks the agent to:

- carry out `pile guide review` of the gitrepo plugin
- hold each changed pile to the task in the title and description, and to the pile's intent
- post the review with `pile-review-comment`, as one comment edited on every run, and not repeat the table
- if that command isn't there, post one comment that starts with `<!-- pile review -->` some other way, and edit it on later runs

A template of your own may use these placeholders:

| Placeholder | Is filled with |
| --- | --- |
| `{{repository}}` | `owner/name` |
| `{{pr_number}}` | the pull request's number |
| `{{pr_title}}`, `{{pr_body}}` | its title and description |
| `{{base}}` | what it is compared with |
| `{{head_sha}}` | the commit it is at |
| `{{pile_gitdiff}}` | `pile gitdiff`'s Markdown |
| `{{extra_instructions}}` | the input of that name |

Each placeholder is filled once, and a value is never searched for placeholders of its own.

Whoever opens a pull request writes its title and description. So before they go into the prompt, the action takes out:
- HTML comments, except inside code, where they show
- invisible characters
- any tag that would close the `<pull-request-title>` or `<pull-request-description>` blocks the template puts them in

This makes hiding instructions harder, but doesn't make it impossible. Give the agent only the tools the review needs.

## Versions

Releases are tagged `v0.1.0`, `v0.1.1`, … and `v0` moves to the newest. To be sure of what runs, pin a full commit SHA.

## License

MIT
