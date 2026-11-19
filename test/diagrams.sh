#!/usr/bin/env bash
# Checks the section scripts/diagrams.sh writes, for each answer pile
# diagram list --since can give. It runs the script with a pile that gives
# a written answer and draws an empty picture, and a gh that takes every
# call, so it needs neither a pile nor GitHub.
#
# Usage: test/diagrams.sh
set -euo pipefail

script=$(cd "$(dirname "$0")/.." && pwd)/scripts/diagrams.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir "$work/bin" "$work/repo"
cat > "$work/bin/pile" << 'STUB'
#!/usr/bin/env bash
# pile diagram list gives the answer in $LIST. pile diagram render writes
# an empty picture to the file -o names.
case "$2" in
  list) cat "$LIST" ;;
  render)
    while [ $# -gt 0 ]; do
      if [ "$1" = -o ]; then : > "$2"; fi
      shift
    done
    echo '{"ok": true}'
    ;;
esac
STUB
cat > "$work/bin/gh" << 'STUB'
#!/usr/bin/env bash
# Every call is answered with one id, as a blob's, a tree's, a commit's
# and the branch's.
case " $* " in *" --input "*) cat > /dev/null ;; esac
echo aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
STUB
chmod +x "$work/bin/pile" "$work/bin/gh"

git -C "$work/repo" init --quiet --initial-branch main
git -C "$work/repo" -c user.name=test -c user.email=test@example.com \
  commit --quiet --allow-empty -m "A repository"
head=$(git -C "$work/repo" rev-parse HEAD)
echo '{"pull_request": {"number": 7}}' > "$work/event.json"
pictures="https://github.com/owner/name/raw/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/pr-7/$head"

failed=0
# check <name> <the diagrams of pile's answer> <how many are shown>: the
# section the script writes is the one on stdin.
check() {
  local name=$1 diagrams=$2 count=$3
  cat > "$work/expected.md"
  printf '{"ok": true, "result": {"diagrams": %s}}\n' "$diagrams" > "$work/list.json"
  : > "$work/markdown.md"
  : > "$work/output"
  if ! (cd "$work/repo" && PATH="$work/bin:$PATH" LIST="$work/list.json" MODE=branch BASE=main \
    MARKDOWN="$work/markdown.md" GH_TOKEN=none GITHUB_REPOSITORY=owner/name \
    GITHUB_EVENT_PATH="$work/event.json" GITHUB_OUTPUT="$work/output" "$script" > "$work/log" 2>&1); then
    echo "not ok: $name: the script failed"
    cat "$work/log"
    failed=1
  elif ! diff "$work/expected.md" "$work/markdown.md"; then
    echo "not ok: $name: the section is not the expected one"
    failed=1
  elif ! grep -qx "diagrams=$count" "$work/output"; then
    echo "not ok: $name: the output diagrams is not $count"
    cat "$work/output"
    failed=1
  else
    echo "ok: $name"
  fi
}

# One diagram of the answer: <name> <change, as JSON> <more fields>.
diagram() {
  printf '{"name": "%s", "handle": "%s", "path": ":/.pile/diagrams/%s.diagram", "change": %s%s}' \
    "$1" "$1" "$1" "$2" "${3:+, $3}"
}

check "touched lists piles, nodes and links, and misses are said" "[$(diagram shop '"piles"' \
  '"piles": ["@web"], "touched": ["@web", "external:bank", "@web relies-on @billing"], "misses": ["@orders", "@orders relies-on @billing"]')]" 1 << EOF_

### Diagrams

**\`shop\`** in \`:/.pile/diagrams/shop.diagram\`, shows what this pull request changed: \`@web\`, \`external:bank\`, \`@web relies-on @billing\`

It misses \`@orders\`, \`@orders relies-on @billing\`, which the diagram should show.

![shop]($pictures/1.png)

EOF_

check "an older pile, with neither field, is shown as before" "[$(diagram shop '"piles"' \
  '"piles": ["@web", "@billing"]'), $(diagram flow '"edited"' '"piles": []'), $(diagram new '"added"' '"piles": []'), $(diagram gone '"removed"' '"piles": []'), $(diagram same null '"piles": []')]" 3 << EOF_

### Diagrams

**\`shop\`** in \`:/.pile/diagrams/shop.diagram\`, shows piles this pull request changed: @web, @billing

![shop]($pictures/1.png)

**\`flow\`** in \`:/.pile/diagrams/flow.diagram\`, edited: from the base to this pull request

![flow]($pictures/2.gif)

**\`new\`** in \`:/.pile/diagrams/new.diagram\`, added by this pull request

![new]($pictures/3.png)

EOF_

check "empty misses say nothing" "[$(diagram shop '"piles"' \
  '"piles": ["@web"], "touched": ["@web"], "misses": []'), $(diagram same null '"piles": [], "touched": [], "misses": []')]" 1 << EOF_

### Diagrams

**\`shop\`** in \`:/.pile/diagrams/shop.diagram\`, shows what this pull request changed: \`@web\`

![shop]($pictures/1.png)

EOF_

check "a diagram that misses something is shown, unless it is removed" "[$(diagram same null \
  '"piles": [], "touched": [], "misses": ["@orders"]'), $(diagram flow '"edited"' '"piles": [], "misses": ["@orders"]'), $(diagram gone '"removed"' '"piles": [], "misses": ["@orders"]')]" 2 << EOF_

### Diagrams

**\`same\`** in \`:/.pile/diagrams/same.diagram\`, not changed by this pull request

It misses \`@orders\`, which the diagram should show.

![same]($pictures/1.png)

**\`flow\`** in \`:/.pile/diagrams/flow.diagram\`, edited: from the base to this pull request

It misses \`@orders\`, which the diagram should show.

![flow]($pictures/2.gif)

EOF_

# shellcheck disable=SC2016 # The backticks are the answer's, not shell.
check "a reference cannot end its code span" "[$(diagram shop '"piles"' \
  '"piles": [], "touched": ["@we`b"], "misses": ["@or`ders\n"]')]" 1 << EOF_

### Diagrams

**\`shop\`** in \`:/.pile/diagrams/shop.diagram\`, shows what this pull request changed: \`@web\`

It misses \`@orders\`, which the diagram should show.

![shop]($pictures/1.png)

EOF_

check "no diagram touched adds no section" "[$(diagram same null '"piles": []')]" 0 << EOF_
EOF_

exit "$failed"
