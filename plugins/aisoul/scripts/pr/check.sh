#!/usr/bin/env bash
# Mechanical checks for a PR description before it is handed over.
#
#   check.sh <file> <small|large>
#
# Fails (exit 1) on: word budget exceeded, no "Not checked" line, `##`
# headings in a small description, a bare #<number> outside code, an em dash.
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

# Words outside <details>, without the title line, table separator rows and pipes.
words="$(sed -e '/<details>/,/<\/details>/d' -e '/^# /d' -e '/^|[ :|-]*$/d' -e 's/|//g' "$file" | wc -w | tr -d ' ')"
if [ "$words" -le "$budget" ]; then
  ok "words: $words / $budget"
else
  fail "words: $words / $budget (move long proof into <details> or cut)"
fi

if grep -q '\*\*Not checked:\*\*' "$file"; then
  ok "Not checked line present"
else
  fail "no **Not checked:** line"
fi

if [ "$shape" = small ]; then
  if grep -qE '^## ' "$file"; then
    fail "small description has ## headings: $(grep -cE '^## ' "$file")"
  else
    ok "no ## headings"
  fi
fi

# Prose only: drop fenced blocks, HTML comments and inline code, then look for #<digit>.
# shellcheck disable=SC2016  # the backticks are literal, not command substitution
prose="$(awk '/^```/ { fence = !fence; next } !fence' "$file" \
  | sed -e 's/<!--.*-->//g' -e 's/`[^`]*`//g')"
bare="$(grep -nE '(^|[^&[:alnum:]/])#[0-9]' <<<"$prose" || true)"
if [ -z "$bare" ]; then
  ok "no bare #<number> outside code"
else
  fail "bare #<number> outside code (GitHub autolinks it):"
  printf '      %s\n' "$bare"
fi

em="$(printf '\xe2\x80\x94')"
if grep -q "$em" "$file"; then
  fail "em dash on lines: $(grep -n "$em" "$file" | cut -d: -f1 | paste -sd, -)"
else
  ok "no em dash"
fi

exit "$status"
