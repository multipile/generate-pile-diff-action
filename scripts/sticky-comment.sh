#!/usr/bin/env bash
# Keeps one comment on the pull request up to date: the comment by AUTHOR
# whose body starts with the marker is edited, and if there is none, one is
# added. A comment already the same is left alone.
#
# Usage: sticky-comment.sh <markdown file> [<marker>]
# With no marker, the file's first line is the marker. With one, the marker
# is put first in the comment, unless the file starts with it already.
#
# Needs GH_TOKEN, GITHUB_REPOSITORY and GITHUB_EVENT_PATH. AUTHOR defaults
# to github-actions[bot], the login GITHUB_TOKEN posts as. Sets the step
# output comment-url, and prints the URL. A comment it cannot post is a
# warning, not a failure: the token of a fork's pull request cannot write.
set -euo pipefail

file=$1
marker=${2:-$(head -n 1 "$file")}
author=${AUTHOR:-github-actions[bot]}
case "$marker" in
  '<!--'*'-->') ;;
  *) echo "::error::the marker must be an HTML comment, <!-- ... -->: $marker"; exit 1 ;;
esac
if [[ $marker == *[\"\\]* ]]; then
  echo "::error::the marker may not hold a quote or a backslash: $marker"
  exit 1
fi

body=$(mktemp)
if [ "$(head -n 1 "$file")" = "$marker" ]; then
  cat "$file" > "$body"
else
  { echo "$marker"; cat "$file"; } > "$body"
fi

pr=$(jq -r '.pull_request.number // empty' "${GITHUB_EVENT_PATH:-/dev/null}" 2> /dev/null || true)
if [ -z "$pr" ]; then
  echo "::notice::this is not a pull request, so no comment is posted"
  exit 0
fi

warn() {
  echo "::warning::could not $1 the comment on pull request #$pr: the token needs pull-requests: write, which a fork's pull request does not get"
  exit 0
}

found=$(gh api --paginate "repos/$GITHUB_REPOSITORY/issues/$pr/comments" \
  --jq ".[] | select(.user.login == \"$author\" and (.body | startswith(\"$marker\"))) | [.id, .html_url] | @tsv" |
  sed -n 1p) || warn read
id=${found%%$'\t'*}
url=${found#*$'\t'}

if [ -n "$found" ]; then
  old=$(gh api "repos/$GITHUB_REPOSITORY/issues/comments/$id" --jq .body) || warn read
  if [ "$old" = "$(cat "$body")" ]; then
    echo "::notice::the comment is up to date: $url"
  else
    url=$(gh api --method PATCH "repos/$GITHUB_REPOSITORY/issues/comments/$id" \
      -F "body=@$body" --jq .html_url) || warn edit
    echo "::notice::edited the comment: $url"
  fi
else
  url=$(gh api --method POST "repos/$GITHUB_REPOSITORY/issues/$pr/comments" \
    -F "body=@$body" --jq .html_url) || warn post
  echo "::notice::posted the comment: $url"
fi
echo "comment-url=$url" >> "${GITHUB_OUTPUT:-/dev/null}"
