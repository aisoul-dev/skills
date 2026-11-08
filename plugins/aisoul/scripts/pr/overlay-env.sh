#!/usr/bin/env bash
# Turns a pr-risk or pr-review overlay into the environment the scripts read.
#
#   eval "$(bash overlay-env.sh .claude/aisoul/pr-risk.md)"
#
# Reads, per "## <Heading>" section, the first ```text block (or, for the base
# and the ticket pattern, the first `inline code`):
#   Base / Base branch           -> PR_BASE
#   Sensitive paths              -> PR_RISK_SENSITIVE   (one regex per line)
#   Excluded from code signals   -> PR_RISK_EXCLUDE     (one regex per line)
#   Error reporting              -> PR_RISK_REPORTING   (lines joined with |)
#   Feature flags                -> PR_RISK_FLAGS       (lines joined with |)
#   Spec folders                 -> PR_SPEC_DIRS        (one folder per line)
#   Ticket pattern               -> PR_TICKET_RE        (first `inline code`)
# Prints nothing for a missing file or section, so the defaults apply.
set -euo pipefail

file="${1:?usage: overlay-env.sh <overlay.md>}"
[ -f "$file" ] || exit 0

awk '
  function emit(name, value) {
    gsub(/\047/, "\047\\\047\047", value)
    printf "export %s=\047%s\047\n", name, value
  }
  function flush() {
    if (sec == "" ) return
    if (sec ~ /^Base( branch)?$/ && inline != "") emit("PR_BASE", inline)
    else if (sec == "Sensitive paths" && block != "") emit("PR_RISK_SENSITIVE", block)
    else if (sec == "Excluded from code signals" && block != "") emit("PR_RISK_EXCLUDE", block)
    else if (sec == "Error reporting" && block != "") { gsub(/\n/, "|", block); emit("PR_RISK_REPORTING", block) }
    else if (sec == "Feature flags" && block != "") { gsub(/\n/, "|", block); emit("PR_RISK_FLAGS", block) }
    else if (sec == "Spec folders" && block != "") emit("PR_SPEC_DIRS", block)
    else if (sec == "Ticket pattern" && inline != "") emit("PR_TICKET_RE", inline)
  }
  /^## / { flush(); sec = substr($0, 4); sub(/[[:space:]]+$/, "", sec); block = ""; inline = ""; inblock = 0; done = 0; next }
  /^<!--/ { incomment = 1 }
  incomment { if ($0 ~ /-->/) incomment = 0; next }
  /^```text[[:space:]]*$/ && !done { inblock = 1; next }
  /^```/ && inblock { inblock = 0; done = 1; next }
  inblock { if ($0 != "") block = (block == "" ? $0 : block "\n" $0); next }
  inline == "" && match($0, /`[^`]+`/) { inline = substr($0, RSTART + 1, RLENGTH - 2) }
  END { flush() }
' "$file"
