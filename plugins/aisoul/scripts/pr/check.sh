#!/usr/bin/env bash
# Mechanical checks for a PR description before it is handed over.
#
#   check.sh <file> <small|large>
#
# Fails (exit 1) on:
#   - word budget exceeded (words outside <details> blocks; title, table pipes
#     and separator rows not counted; code blocks outside <details> count)
#   - no line starting with **Not checked:**
#   - small: any ## heading; large: no ## What / ## Evidence, or the
#     Not checked line is not inside ## Evidence
#   - a bare #<number> in prose (anywhere, <details> included: GitHub autolinks it)
#   - an em dash in prose (pasted output in code blocks stays verbatim)
#
# A <details> block starts at a line that begins with <details> or
# <details ...> and ends at a line that is only </details>. A mention of the
# tag inside a sentence or in backticks does not start one.
# Env: PR_BUDGET overrides the word budget.
set -euo pipefail

file="${1:?usage: check.sh <file> <small|large>}"
shape="${2:?usage: check.sh <file> <small|large>}"
[ -f "$file" ] || { echo "pr-check: no such file: $file" >&2; exit 1; }

case "$shape" in
  small) budget="${PR_BUDGET:-150}" ;;
  large) budget="${PR_BUDGET:-400}" ;;
  *) echo "pr-check: shape must be small or large" >&2; exit 1 ;;
esac

status=0
fail() { echo "FAIL  $*"; status=1; }
ok()   { echo "ok    $*"; }

# --- the text that counts towards the budget ---------------------------------
counted="$(awk '
  indet { if ($0 ~ /^[[:space:]]*<\/details>[[:space:]]*$/) indet = 0; next }
  /^[[:space:]]*```/ { fence = !fence; print; next }
  fence { print; next }
  /^[[:space:]]*<details([[:space:]][^>]*)?>/ { if ($0 !~ /<\/details>/) indet = 1; next }
  /^# / && !titled { titled = 1; next }
  /^[[:space:]]*\|[ :|-]*$/ { next }
  { gsub(/\|/, " "); print }
' "$file")"
unclosed="$(awk '
  indet { if ($0 ~ /^[[:space:]]*<\/details>[[:space:]]*$/) indet = 0; next }
  /^[[:space:]]*```/ { fence = !fence; next }
  fence { next }
  /^[[:space:]]*<details([[:space:]][^>]*)?>/ { if ($0 !~ /<\/details>/) { indet = 1; start = NR } }
  END { if (indet) print start }
' "$file")"

words="$(wc -w <<<"$counted" | tr -d ' ')"
if [ -n "$unclosed" ]; then
  fail "<details> opened on line $unclosed is never closed by a line that is only </details>"
elif [ "$words" -le "$budget" ]; then
  ok "words: $words / $budget"
else
  fail "words: $words / $budget (move long proof into <details> or cut)"
fi

# --- prose: no fenced blocks, no inline code, no HTML comments, with line numbers
# shellcheck disable=SC2016  # the backticks are literal, not command substitution
prose="$(awk '
  /^[[:space:]]*```/ { fence = !fence; next }
  fence { next }
  {
    line = $0
    if (incomment) {
      if (index(line, "-->")) { line = substr(line, index(line, "-->") + 3); incomment = 0 } else next
    }
    while ((s = index(line, "<!--")) > 0) {
      rest = substr(line, s + 4)
      e = index(rest, "-->")
      if (e) { line = substr(line, 1, s - 1) substr(rest, e + 3) }
      else { line = substr(line, 1, s - 1); incomment = 1; break }
    }
    gsub(/`[^`]*`/, "", line)
    print NR ": " line
  }
' "$file")"

# --- headings and the Not checked line, outside code -------------------------
outside_code="$(awk '/^[[:space:]]*```/ { fence = !fence; next } !fence { print NR ": " $0 }' "$file")"

if grep -qE '^[0-9]+: \*\*Not checked:\*\*' <<<"$outside_code"; then
  ok "Not checked line present"
else
  fail "no **Not checked:** line"
fi

if [ "$shape" = small ]; then
  n="$(grep -cE '^[0-9]+: ## ' <<<"$outside_code" || true)"
  if [ "$n" -gt 0 ]; then fail "small description has ## headings: $n"; else ok "no ## headings"; fi
else
  for h in What Evidence; do
    if grep -qE "^[0-9]+: ## $h\b" <<<"$outside_code"; then ok "## $h present"; else fail "no ## $h section"; fi
  done
  where="$(awk -F': ' '
    { sub(/^[0-9]+: /, "") }
    /^## / { sec = $0 }
    /^\*\*Not checked:\*\*/ { print sec; exit }
  ' <<<"$outside_code")"
  if [ "$where" = "## Evidence" ]; then
    ok "Not checked line is in ## Evidence"
  elif grep -qE '^[0-9]+: \*\*Not checked:\*\*' <<<"$outside_code"; then
    fail "Not checked line is in '${where:-before any section}', expected ## Evidence"
  fi
fi

# --- bare #<number> -----------------------------------------------------------
bare="$(grep -E '^[0-9]+: (.*[^&[:alnum:]/])?#[0-9]' <<<"$prose" || true)"
if [ -z "$bare" ]; then
  ok "no bare #<number> outside code"
else
  fail "bare #<number> outside code (GitHub autolinks it):"
  printf '      %s\n' "$bare"
fi

# --- em dash in prose ---------------------------------------------------------
em="$(printf '\xe2\x80\x94')"
dash="$(grep -F "$em" <<<"$prose" | cut -d: -f1 | paste -sd, - || true)"
if [ -z "$dash" ]; then
  ok "no em dash in prose"
else
  fail "em dash in prose on lines: $dash"
fi

exit "$status"
