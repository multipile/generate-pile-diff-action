#!/usr/bin/env bash
# Shows the diagrams the pull request's change touches: draws each with
# pile, publishes the pictures, and adds a section to pile gitdiff's
# Markdown, which the comment, the job summary and the prompt are made of.
# Runs in the repository to read.
#
# A diagram is touched when the pull request adds it, edits it, or changes
# a pile it shows (pile diagram list --since). An edited one is drawn as an
# animation from its first version to its second; one whose piles changed,
# with their boxes marked; an added one as it is.
#
# MODE is how they are shown: none, or branch, which commits the pictures
# to BRANCH in this repository through the API, and links each from the
# commit that holds it, so a later push changes no older comment. It needs
# contents: write, which a fork's pull request does not get: then the
# section names the diagrams and says why they are not shown.
#
# BASE is the revision the pull request is compared with, and MARKDOWN the
# file the section is added to. Needs GH_TOKEN, GITHUB_REPOSITORY and
# GITHUB_EVENT_PATH. Sets the step outputs diagrams (how many) and
# diagrams-url (the commit the pictures are in, if any).
set -euo pipefail
mode=${MODE:-none}
branch=${BRANCH:-multipile/assets}
case "$mode" in
  none) echo "diagrams=0" >> "${GITHUB_OUTPUT:-/dev/null}"; exit 0 ;;
  branch) ;;
  *) echo "::error::diagrams is none or branch, not $mode"; exit 1 ;;
esac
case "$branch" in
  '' | -* | *..* | *' '* | *[\"\\]*) echo "::error::$branch cannot be a branch's name"; exit 1 ;;
esac

since=$(git merge-base "$BASE" HEAD)
work=$(mktemp -d)
pile diagram list --since "$since" --format json > "$work/list.json"
jq -c '.result.diagrams[] | select(.change == "added" or .change == "edited" or .change == "piles")' \
  "$work/list.json" > "$work/touched.jsonl"
count=$(wc -l < "$work/touched.jsonl" | tr -d ' ')
echo "diagrams=$count" >> "${GITHUB_OUTPUT:-/dev/null}"
if [ "$count" = 0 ]; then
  echo "::notice::the pull request touches no diagram"
  exit 0
fi

# Draws each one: a file named by its place in the list, so no name a
# pull request wrote is ever a path.
n=0
: > "$work/drawn.tsv"
while IFS= read -r d; do
  n=$((n + 1))
  handle=$(jq -r .handle <<< "$d")
  change=$(jq -r .change <<< "$d")
  as=png
  if [ "$change" = edited ]; then as=gif; fi
  file="$work/$n.$as"
  if pile diagram render "$handle" --since "$since" --as "$as" -o "$file" --format json > "$work/$n.json"; then
    printf '%s\t%s\n' "$n" "$file" >> "$work/drawn.tsv"
  else
    echo "::warning::pile could not draw the diagram $handle: $(jq -r '.error.message // empty' "$work/$n.json" 2> /dev/null)"
  fi
done < "$work/touched.jsonl"

# Publishes the pictures as one commit on the branch: its tree holds only
# this run's pictures, under pr-<number>/<head>, and its parent is the
# branch as it is, so every earlier commit and its pictures stay.
pr=$(jq -r '.pull_request.number // "none"' "${GITHUB_EVENT_PATH:-/dev/null}" 2> /dev/null || echo none)
head=$(git rev-parse HEAD)
dir="pr-$pr/$head"
published=""
publish() {
  local entries="[]" n file blob parent tree commit
  while IFS=$'\t' read -r n file; do
    blob=$(base64 < "$file" | tr -d '\n' | jq -Rs '{content: ., encoding: "base64"}' |
      gh api "repos/$GITHUB_REPOSITORY/git/blobs" --input - --jq .sha) || return 1
    entries=$(jq -c --arg path "$dir/${file##*/}" --arg sha "$blob" \
      '. + [{path: $path, mode: "100644", type: "blob", sha: $sha}]' <<< "$entries")
  done < "$work/drawn.tsv"
  tree=$(jq -n --argjson tree "$entries" '{tree: $tree}' |
    gh api "repos/$GITHUB_REPOSITORY/git/trees" --input - --jq .sha) || return 1
  for _ in 1 2 3; do
    parent=$(gh api "repos/$GITHUB_REPOSITORY/git/ref/heads/$branch" --jq .object.sha 2> /dev/null || true)
    commit=$(jq -n --arg tree "$tree" --arg parent "$parent" --arg message "Diagrams of pull request #$pr at $head" \
      '{message: $message, tree: $tree, parents: (if $parent == "" then [] else [$parent] end)}' |
      gh api "repos/$GITHUB_REPOSITORY/git/commits" --input - --jq .sha) || return 1
    if [ -z "$parent" ]; then
      if gh api "repos/$GITHUB_REPOSITORY/git/refs" -f "ref=refs/heads/$branch" -f "sha=$commit" > /dev/null 2>&1; then
        published=$commit
        return 0
      fi
    elif gh api -X PATCH "repos/$GITHUB_REPOSITORY/git/refs/heads/$branch" -f "sha=$commit" -F force=false > /dev/null 2>&1; then
      published=$commit
      return 0
    fi
    # Another run moved the branch in between: build on where it is now.
  done
  return 1
}
reason=""
if [ -s "$work/drawn.tsv" ] && ! publish; then
  reason="the pictures could not be published to the branch $branch: the workflow needs contents: write, which a fork's pull request does not get"
  echo "::warning::$reason"
fi
echo "diagrams-url=${published:+https://github.com/$GITHUB_REPOSITORY/tree/$published/$dir}" >> "${GITHUB_OUTPUT:-/dev/null}"

# The section. Names and paths come from pile's answer about files the pull
# request wrote, so they go in code spans, cleaned of what would end one.
# shellcheck disable=SC2016 # The backticks are Markdown, not shell.
code() { printf '`%s`' "$(tr -d '`\r\n' <<< "$1")"; }
{
  echo
  echo "### Diagrams"
  echo
  if [ -n "$reason" ]; then
    echo "_${reason}._"
    echo
  fi
  n=0
  while IFS= read -r d; do
    n=$((n + 1))
    name=$(jq -r .name <<< "$d")
    path=$(jq -r .path <<< "$d")
    change=$(jq -r .change <<< "$d")
    case "$change" in
      added) what="added by this pull request" ;;
      edited) what="edited: from the base to this pull request" ;;
      *) what="shows piles this pull request changed: $(jq -r '.piles | join(", ")' <<< "$d" | tr -d '`\r\n')" ;;
    esac
    echo "**$(code "$name")** in $(code "$path"), $what"
    echo
    file=$(awk -F '\t' -v n="$n" '$1 == n { print $2 }' "$work/drawn.tsv")
    if [ -n "$published" ] && [ -n "$file" ]; then
      echo "![$(tr -d '[]`\r\n' <<< "$name")](https://github.com/$GITHUB_REPOSITORY/raw/$published/$dir/${file##*/})"
      echo
    fi
  done < "$work/touched.jsonl"
} >> "$MARKDOWN"
