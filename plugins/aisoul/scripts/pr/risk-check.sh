#!/usr/bin/env bash
# Checks a merge-risk assessment against the pr-risk output format.
#
#   risk-check.sh <file>
#
# Fails (exit 1) on: no "**Merge risk: low|medium|high" headline with a rule
# number, a dimension missing or out of order, a dimension without a verdict,
# a non-✅ dimension without a "Lower it:" bullet, no "**Not assessed:**" line,
# more than PR_RISK_WORDS words (default 250), a bare #<number> outside code,
# an em dash outside code.
set -euo pipefail

file="${1:?usage: risk-check.sh <file>}"
[ -f "$file" ] || { echo "pr-risk-check: no such file: $file" >&2; exit 1; }
budget="${PR_RISK_WORDS:-250}"

status=0
fail() { echo "FAIL  $*"; status=1; }
ok()   { echo "ok    $*"; }

# Prose: no fenced blocks, no inline code, no HTML comments.
# shellcheck disable=SC2016  # the backticks are literal, not command substitution
prose="$(awk '
  /^[[:space:]]*```/ { fence = !fence; next }
  fence { next }
  { line = $0; gsub(/<!--.*-->/, "", line); gsub(/`[^`]*`/, "", line); print NR ": " line }
' "$file")"

if grep -qE '^1: \*\*Merge risk: (low|medium|high)( \(was (low|medium|high)\))?\*\*.*\(rule [1-5]\)[[:space:]]*$' <<<"$prose"; then
  ok "headline with level and rule"
else
  fail "first line must be '**Merge risk: <low|medium|high>**: <why> (rule N)', ending with the rule"
fi

# Dimensions in order, each with a verdict; non-✅ ones need a Lower it bullet.
result="$(awk '
  BEGIN {
    split("Scope fit|Blast radius|Verification|Reversibility|Observability", want, "|")
    n = 0; cur = ""
  }
  function close_dim() {
    if (cur != "" && verdict != "ok" && !lower) print "nolower " cur
  }
  /^\*\*(Scope fit|Blast radius|Verification|Reversibility|Observability)\*\*/ {
    close_dim()
    name = $0; sub(/^\*\*/, "", name); sub(/\*\*.*/, "", name)
    n++
    if (want[n] != name) print "order " name
    cur = name; lower = 0
    if ($0 ~ /✅/) verdict = "ok"
    else if ($0 ~ /👀|⚠|❓/) verdict = "risk"
    else { verdict = "none"; print "verdict " name }
    next
  }
  /^\*\*Not assessed:\*\*/ { close_dim(); cur = ""; notassessed = 1; next }
  /^[[:space:]]*- Lower it:/ { lower = 1 }
  END {
    close_dim()
    if (n != 5) print "count " n
    if (!notassessed) print "notassessed"
  }
' "$file")"

if [ -z "$result" ]; then
  ok "five dimensions in order, each with a verdict and, when not ✅, a Lower it"
else
  while IFS= read -r r; do
    case "$r" in
      order*)   fail "dimension out of order: ${r#order }" ;;
      verdict*) fail "no verdict on: ${r#verdict }" ;;
      nolower*) fail "no '- Lower it:' bullet under: ${r#nolower }" ;;
      count*)   fail "expected 5 dimensions, found ${r#count }" ;;
      notassessed) fail "no **Not assessed:** line" ;;
    esac
  done <<<"$result"
fi

words="$(wc -w < "$file" | tr -d ' ')"
if [ "$words" -le "$budget" ]; then ok "words: $words / $budget"; else fail "words: $words / $budget"; fi

bare="$(grep -E '^[0-9]+: (.*[^&[:alnum:]/])?#[0-9]' <<<"$prose" || true)"
if [ -z "$bare" ]; then ok "no bare #<number> outside code"; else fail "bare #<number> outside code:"; printf '      %s\n' "$bare"; fi

em="$(printf '\xe2\x80\x94')"
dash="$(grep -F "$em" <<<"$prose" | cut -d: -f1 | paste -sd, - || true)"
if [ -z "$dash" ]; then ok "no em dash in prose"; else fail "em dash in prose on lines: $dash"; fi

exit "$status"
