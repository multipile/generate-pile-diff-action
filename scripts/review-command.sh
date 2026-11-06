#!/usr/bin/env bash
# Puts the command pile-review-comment on the job's PATH, for the agent that
# carries out the prompt. It does one thing: it keeps the review's comment,
# marked <!-- pile review -->, on this pull request. So the agent needs no
# general access to the GitHub API to post its review.
#
#   pile-review-comment <markdown file>
#   pile-review-comment <<'EOF' ... EOF     (the review on stdin)
#
# Reading stdin lets an agent post with one allowed command, and write no
# file: where an agent may write differs from one setup to another.
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
# Usage: pile-review-comment [<markdown file>]   (no file, or -, reads stdin)
set -euo pipefail
usage() {
  echo "usage: pile-review-comment [<markdown file>], or the review on stdin: pile-review-comment <<'EOF' ... EOF" >&2
  exit 2
}
if [ $# -gt 1 ]; then
  usage
fi
file=${1:--}
if [ "$file" = - ]; then
  file=$(mktemp)
  cat > "$file"
elif [ ! -f "$file" ]; then
  usage
fi
if [ ! -s "$file" ]; then
  echo "pile-review-comment: the review is empty" >&2
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
  # shellcheck disable=SC2016 # $file is the command's own variable.
  printf 'exec %q "$file" %q\n' "$here/sticky-comment.sh" '<!-- pile review -->'
} >> "$bin/pile-review-comment"
chmod +x "$bin/pile-review-comment"
echo "$bin" >> "${GITHUB_PATH:-/dev/null}"
