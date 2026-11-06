#!/usr/bin/env bash
# Makes a small repository of piles to run the action on: a top pile and
# two piles under it, a main branch, and a branch that changes one of them.
#
# Usage: fixture.sh <directory>
set -euo pipefail

dir=$1
mkdir -p "$dir"
cd "$dir"
git init --quiet --initial-branch main
git config user.name fixture
git config user.email fixture@example.com

pile() { # <path> <name> <headline>
  mkdir -p "$1/.pile"
  printf 'kind = gitpile\nversion = 1\nid = %s\nname = %s\n' \
    "$(od -An -tx1 -N16 /dev/urandom | tr -d ' \n')" "$2" > "$1/.pile/config"
  printf '%s\n\nRead this pile to find out how it works. Change it when it does something new.\n' \
    "$3" > "$1/.pile/intent.md"
}

pile . shop "A shop that sells one kind of tea, and everything it takes to run it."
pile web web "The pages a buyer sees, from the list of teas to the receipt."
pile billing billing "Takes a buyer's money once, and never twice, for what they ordered."
echo "# Shop" > README.md
echo "<h1>Teas</h1>" > web/index.html
echo "charge() { :; }" > billing/charge.sh
git add -A
git commit --quiet -m "A shop"

git switch --quiet -c change
echo "<p>Now with prices.</p>" >> web/index.html
git commit --quiet -am "Show prices"
