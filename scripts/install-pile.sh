#!/usr/bin/env bash
# Installs pile and puts it on the job's PATH: a release of
# multipile/pile-cli, checked against the release's SHA256SUMS, or, when
# PILE_REF names a branch or tag of pile-cli, built from its source.
#
# PILE_VERSION picks the release:
#   0.1             the newest v0.1.x that is not a prerelease
#   latest          the newest release
#   0.1.3, v0.1.3   exactly that release
#
# Needs GH_TOKEN, and runs on a Linux or macOS runner. Sets the step output
# pile-version.
set -euo pipefail

repo=multipile/pile-cli
spec=${PILE_VERSION:-}
bin=${RUNNER_TEMP:-$(mktemp -d)}/pile-bin
mkdir -p "$bin"

finish() {
  echo "$bin" >> "${GITHUB_PATH:-/dev/null}"
  local version
  version=$("$bin/pile" version --format text | awk 'NR == 1 { print $2 }')
  echo "::notice::pile $version"
  echo "pile-version=$version" >> "${GITHUB_OUTPUT:-/dev/null}"
  if ! "$bin/pile" gitdiff --help > /dev/null 2>&1; then
    echo "::error::pile $version has no gitdiff command: it needs 0.1.3 or later"
    exit 1
  fi
}

if [ -n "${PILE_REF:-}" ]; then
  echo "::notice::building pile from $repo at $PILE_REF"
  # The runner's Rust may be older than the one pile-cli needs.
  if command -v rustup > /dev/null; then
    rustup update stable --no-self-update
  fi
  root=$(mktemp -d)
  cargo install --locked --quiet --root "$root" \
    --git "https://github.com/$repo" --branch "$PILE_REF" pile
  cp "$root/bin/pile" "$bin/pile"
  finish
  exit 0
fi

case "$spec" in
  latest)
    tag=$(gh release view --repo "$repo" --json tagName --jq .tagName)
    ;;
  v[0-9]*.[0-9]*.[0-9]* | [0-9]*.[0-9]*.[0-9]*)
    tag=v${spec#v}
    ;;
  [0-9]*.[0-9]* | v[0-9]*.[0-9]*)
    minor=${spec#v}
    tag=$(gh api --paginate "repos/$repo/releases" \
      --jq '.[] | select(.draft == false and .prerelease == false) | .tag_name' |
      grep -E "^v${minor//./\\.}\.[0-9]+$" | sort -V | tail -n 1 || true)
    if [ -z "$tag" ]; then
      echo "::error::no release of pile matches $spec (v$minor.x)"
      exit 1
    fi
    ;;
  *)
    echo "::error::pile-version is $spec: give a major.minor (0.1), latest, or a version (0.1.3)"
    exit 1
    ;;
esac

case "$(uname -s)" in
  Linux) os=linux ;;
  Darwin) os=darwin ;;
  *) echo "::error::no pile release for $(uname -s)"; exit 1 ;;
esac
case "$(uname -m)" in
  x86_64 | amd64) arch=amd64 ;;
  aarch64 | arm64) arch=arm64 ;;
  *) echo "::error::no pile release for $(uname -m)"; exit 1 ;;
esac

dir=$(mktemp -d)
if ! gh release download "$tag" --repo "$repo" --dir "$dir" \
  --pattern "pile-*-$os-$arch.tar.gz" --pattern SHA256SUMS; then
  echo "::error::could not download pile $tag for $os-$arch"
  exit 1
fi
if command -v sha256sum > /dev/null; then
  (cd "$dir" && sha256sum --check --ignore-missing SHA256SUMS)
else
  (cd "$dir" && grep -- "-$os-$arch.tar.gz" SHA256SUMS | shasum -a 256 --check)
fi
tar -xzf "$dir"/pile-*-"$os-$arch".tar.gz -C "$bin" pile
finish
