#!/usr/bin/env bash
# Puts the command pile-review-comment on the job's PATH, for the agent that
# carries out the prompt. It does one thing: it keeps the review's comment,
# marked <!-- pile review -->, on this pull request. So the agent needs no
# general access to the GitHub API to post its review.
#
#   pile-review-comment <markdown file>
#
# The command needs GH_TOKEN in the agent's environment.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
bin=${RUNNER_TEMP:-$(mktemp -d)}/pile-review-bin
mkdir -p "$bin"

# The command's own text is quoted, so nothing in it expands here.
cat > "$bin/pile-review-comment" << 'EOF'
#!/usr/bin/env bash
# Keeps the review comment, marked <!-- pile review -->, on this pull request.
# Usage: pile-review-comment <markdown file>
set -euo pipefail
if [ $# -ne 1 ] || [ ! -f "$1" ]; then
  echo "usage: pile-review-comment <markdown file>" >&2
  exit 2
fi
if [ -z "${GH_TOKEN:-}" ]; then
  echo "pile-review-comment: GH_TOKEN is not set: give the agent's step GH_TOKEN: \${{ github.token }}" >&2
  exit 1
fi
EOF
{
  printf 'export AUTHOR=%q GITHUB_REPOSITORY=%q GITHUB_EVENT_PATH=%q\n' \
    "${AUTHOR:-github-actions[bot]}" "${GITHUB_REPOSITORY:-}" "${GITHUB_EVENT_PATH:-}"
  # shellcheck disable=SC2016 # $1 is the command's own argument.
  printf 'exec %q "$1" %q\n' "$here/sticky-comment.sh" '<!-- pile review -->'
} >> "$bin/pile-review-comment"
chmod +x "$bin/pile-review-comment"
echo "$bin" >> "${GITHUB_PATH:-/dev/null}"
