#!/usr/bin/env bash
# Makes the prompt: fills a template's {{placeholders}} with the pull
# request and pile gitdiff's Markdown. Each placeholder is filled once, and
# a value is never read again for placeholders of its own.
#
# TEMPLATE is a template of the caller's, as a path from the working
# directory. Empty, it is the action's own. MARKDOWN is pile gitdiff's
# answer, BASE what it compared with, and EXTRA_INSTRUCTIONS any text the
# caller added. The pull request comes from GITHUB_EVENT_PATH.
#
# Sets the step outputs prompt and prompt-file.
set -euo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
template=${TEMPLATE:-$here/templates/review.md}
if [ ! -f "$template" ]; then
  echo "::error::the template $template is not a file"
  exit 1
fi

event=${GITHUB_EVENT_PATH:-/dev/null}
field() {
  jq -r "$1 // empty" "$event" 2> /dev/null || true
}

# The title and the body are written by whoever opened the pull request.
# Hidden text is taken out: HTML comments outside code, and invisible
# characters. So is anything that would close the tags the template puts
# them in.
untrusted() {
  # shellcheck disable=SC2016 # Python, not shell.
  python3 -I -c '
import re, sys
text = sys.stdin.read()
# Code, in a fence or between backticks, is shown as it is written, so an
# HTML comment in it hides nothing and is kept.
parts = re.split(r"(```.*?(?:```|\Z)|`[^`\n]+`)", text, flags=re.S)
for i in range(0, len(parts), 2):
    parts[i] = re.sub(r"<!--.*?(?:-->|\Z)", "", parts[i], flags=re.S)
text = "".join(parts)
text = re.sub(r"[\u200b-\u200f\u202a-\u202e\u2060-\u2064\ufeff\U000e0000-\U000e007f]", "", text)
text = re.sub(r"</?\s*pull-request-[a-z-]*\s*>", "", text, flags=re.I)
sys.stdout.write(text)
'
}

export V_repository=${GITHUB_REPOSITORY:-}
V_pr_number=$(field .pull_request.number)
V_head_sha=$(field .pull_request.head.sha)
V_pr_title=$(field .pull_request.title | untrusted)
V_pr_body=$(field .pull_request.body | untrusted)
V_base=${BASE:-}
V_pile_gitdiff=$(cat "$MARKDOWN")
V_extra_instructions=${EXTRA_INSTRUCTIONS:-}
if [ -z "$V_head_sha" ]; then
  V_head_sha=$(git rev-parse HEAD)
fi
export V_pr_number V_head_sha V_pr_title V_pr_body V_base V_pile_gitdiff \
  V_extra_instructions

out=${RUNNER_TEMP:-$(mktemp -d)}/pile-gitdiff
mkdir -p "$out"
prompt=$out/prompt.md

awk '
  {
    line = $0
    done = ""
    while (match(line, /[{][{][a-z_]+[}][}]/)) {
      name = substr(line, RSTART + 2, RLENGTH - 4)
      if (("V_" name) in ENVIRON) {
        value = ENVIRON["V_" name]
      } else {
        value = substr(line, RSTART, RLENGTH)
        unknown[name] = 1
      }
      done = done substr(line, 1, RSTART - 1) value
      line = substr(line, RSTART + RLENGTH)
    }
    print done line
  }
  END {
    for (name in unknown) {
      printf "::warning::the template has {{%s}}, which the action does not fill\n", name > "/dev/stderr"
    }
  }
' "$template" > "$prompt"

delimiter=prompt_$(od -An -tx1 -N16 /dev/urandom | tr -d ' \n')
{
  echo "prompt-file=$prompt"
  echo "prompt<<$delimiter"
  cat "$prompt"
  echo "$delimiter"
} >> "${GITHUB_OUTPUT:-/dev/null}"
echo "::notice::the prompt is $(wc -c < "$prompt" | tr -d ' ') bytes: $prompt"
