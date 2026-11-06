#!/usr/bin/env bash
# Arranges the pull request by pile: pile gitdiff from where HEAD left the
# base to HEAD, in Markdown and in JSON. Runs in the repository to read.
#
# BASE is the revision to compare with. Empty, it is the pull request's
# target, origin/$GITHUB_BASE_REF.
#
# Sets the step outputs base, markdown-file, json-file and changed-piles.
set -euo pipefail

base=${BASE:-}
if [ -z "$base" ]; then
  if [ -z "${GITHUB_BASE_REF:-}" ]; then
    echo "::error::this is not a pull request, so there is no base to compare with: set the input base"
    exit 1
  fi
  base=origin/$GITHUB_BASE_REF
fi

if ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo "::error::$(pwd) is not a git repository: check it out first"
  exit 1
fi
if [ "$(git rev-parse --is-shallow-repository)" = true ]; then
  echo "::error::the checkout is shallow, so pile cannot find where HEAD left $base: check out with fetch-depth: 0"
  exit 1
fi
if ! git rev-parse --verify --quiet "$base^{commit}" > /dev/null; then
  echo "::error::$base names no revision here: fetch it, or set the input base"
  exit 1
fi

out=${RUNNER_TEMP:-$(mktemp -d)}/pile-gitdiff
mkdir -p "$out"
pile gitdiff "$base...HEAD" --format markdown > "$out/pile-gitdiff.md"
pile gitdiff "$base...HEAD" --format json > "$out/pile-gitdiff.json"

changed=$(jq -r '.result.total.changed' "$out/pile-gitdiff.json")
echo "::notice::piles changed from where HEAD left $base: $changed"

{
  echo "base=$base"
  echo "markdown-file=$out/pile-gitdiff.md"
  echo "json-file=$out/pile-gitdiff.json"
  echo "changed-piles=$changed"
} >> "${GITHUB_OUTPUT:-/dev/null}"
