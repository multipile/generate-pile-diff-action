#!/usr/bin/env bash
# Makes a small repository of piles to run the action on: a top pile and
# two piles under it, a main branch, and a branch that changes one of them.
#
# With diagrams, the repository also declares what its piles rely on, and
# keeps a diagram of it whose boxes and lines stand for those nodes and
# links, and which says what it should show. Its branch then changes a link
# the diagram draws, and adds a pile the diagram should show and does not.
#
# Usage: fixture.sh <directory> [diagrams]
set -euo pipefail

dir=$1
with=${2:-}
case "$with" in
  '' | diagrams) ;;
  *) echo "fixture.sh: the second argument is diagrams, or nothing, not $with" >&2; exit 1 ;;
esac
mkdir -p "$dir"
cd "$dir"
git init --quiet --initial-branch main
git config user.name fixture
git config user.email fixture@example.com

pile() { # <path> <name> <headline> [<kind>]
  mkdir -p "$1/.pile"
  printf 'kind = %s\nversion = 1\nid = %s\nname = %s\n' \
    "${4:-gitpile}" "$(od -An -tx1 -N16 /dev/urandom | tr -d ' \n')" "$2" > "$1/.pile/config"
  printf '%s\n\nRead this pile to find out how it works. Change it when it does something new.\n' \
    "$3" > "$1/.pile/intent.md"
}

pile . shop "A shop that sells one kind of tea, and everything it takes to run it."
pile web web "The pages a buyer sees, from the list of teas to the receipt."
pile billing billing "Takes a buyer's money once, and never twice, for what they ordered."
echo "# Shop" > README.md
echo "<h1>Teas</h1>" > web/index.html
echo "charge() { :; }" > billing/charge.sh

# The id a pile was given, read back from its config.
id_of() { awk '$1 == "id" { print $3 }' "$1/.pile/config"; }
# A link from the pile at <path> to <target>.
relies_on() { # <path> <target> <title>
  printf 'version = "gitpile/1"\n\n[[edges]]\ntype = "relies-on"\ntarget = "%s"\ntitle = "%s"\n' \
    "$2" "$3" > "$1/.pile/links.toml"
}

if [ "$with" = diagrams ]; then
  pile piles piles "The words the shop's piles are declared in." auxiliary-gitpile
  cat > piles/.pile/types.toml << 'EOF'
version = "gitpile/1"

[[node-types]]
name = "external"
title = "something outside the repository that a pile relies on"

[[edge-types]]
name = "relies-on"
title = "one pile relies on another, or on something outside the repository"
source = ["pile"]
target = ["pile", "external"]
EOF
  cat > .pile/nodes.toml << 'EOF'
version = "gitpile/1"

[[nodes]]
type = "external"
name = "bank"
title = "the bank that moves a buyer's money"
EOF
  relies_on web "@billing" "charges a buyer through"
  relies_on billing "external:bank" "moves the money through"
  # A box stands for a pile by its id, and for the bank by the id of the
  # pile that declares it. The diagram should show whatever relies on
  # billing.
  mkdir -p .pile/diagrams
  cat > .pile/diagrams/shop.diagram << EOF
diagram dependency version=1 {
  title "What the shop relies on"
  desc "The pages charge through billing, and billing moves the money through the bank."

  box web     pile:id="$(id_of web)"
  box billing pile:id="$(id_of billing)" focal=#true
  box bank    pile:id="$(id_of .)" pile:node-type=external as=external

  line web billing  pile:edge="relies-on"
  line billing bank pile:edge="relies-on"

  meta pile {
    boxes {
      include #"?- edge(_, Node, "relies-on", @billing)."#
    }
  }
}
EOF
fi
git add -A
git commit --quiet -m "A shop"

git switch --quiet -c change
if [ "$with" = diagrams ]; then
  # The link the diagram's first line stands for says something else, and
  # a new pile relies on billing, which the diagram does not draw.
  relies_on web "@billing" "takes a buyer's money through"
  pile orders orders "What a buyer ordered, kept until it is sent."
  relies_on orders "@billing" "asks for each order's money from"
  echo "order() { :; }" > orders/order.sh
  git add -A
  git commit --quiet -m "Keep orders"
else
  echo "<p>Now with prices.</p>" >> web/index.html
  git commit --quiet -am "Show prices"
fi
