#!/usr/bin/env bash
# Where the spec for a branch probably is. Lists, mechanically:
#   1. ticket and issue references in the branch name and commit messages
#   2. spec files the branch itself adds or changes
#   3. spec files whose path names one of those tickets
#   4. spec files whose path shares words with the branch name, best first
# It judges nothing: read the candidates, and ask the user when none fits.
#
#   spec-find.sh [<branch>]
#
# Env:
#   PR_BASE        base ref (default: origin/HEAD, else origin/main, else main)
#   PR_SPEC_DIRS   spec folders, one per line (default: docs/specs specs
#                  docs/superpowers/specs .scratch docs)
#   PR_TICKET_RE   ticket pattern, ERE (default: [A-Z][A-Z0-9]+-[0-9]+)
# Exit: 0 with at least one candidate file, 1 with none (ask the user).
set -euo pipefail
# shellcheck source=SCRIPTDIR/lib.sh
source "$(dirname "$0")/lib.sh"
require_repo pr-spec-find

branch="${1:-HEAD}"
resolve_base
name="$(git rev-parse --abbrev-ref "$branch" 2>/dev/null || echo "$branch")"
dirs="${PR_SPEC_DIRS:-$(printf '%s\n' docs/specs specs docs/superpowers/specs .scratch docs)}"
ticket_re="${PR_TICKET_RE:-[A-Z][A-Z0-9]+-[0-9]+}"

messages="$(git log --format='%s%n%b' "$BASE..$branch")"
tickets="$( { grep -oE "$ticket_re" <<<"$name" || true; grep -oE "$ticket_re" <<<"$messages" || true; } | sort -u)"
issues="$(grep -oE '(([Cc]loses|[Ff]ixes|[Rr]esolves)[[:space:]]+)?#[0-9]+|![0-9]+' <<<"$messages" | sort -u || true)"

# Spec-like files in the spec folders that exist, at the branch's version.
spec_files="$(
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    git ls-tree -r --name-only "$branch" -- "${d%/}/" 2>/dev/null
  done <<<"$dirs" | grep -E '\.(md|mdx|txt|ya?ml)$' | sort -u || true
)"

echo "# Spec candidates: $name against $BASE"
echo
echo "## References"
echo
if [ -z "$tickets$issues" ]; then
  echo "- none in the branch name or commit messages"
else
  while IFS= read -r t; do [ -n "$t" ] && echo "- ticket \`$t\`"; done <<<"$tickets"
  while IFS= read -r i; do [ -n "$i" ] && echo "- issue \`$i\`"; done <<<"$issues"
fi
echo

as_list() { awk -v q='`' '{ print "- " q $0 q }'; }

found=0
echo "## Spec files changed by the branch"
echo
changed="$(git -c core.quotePath=false diff --name-only "$BASE...$branch" | grep -Fxf <(printf '%s\n' "$spec_files") || true)"
if [ -n "$changed" ]; then found=1; as_list <<<"$changed"; else echo "- none"; fi
echo

echo "## Spec files naming a ticket"
echo
by_ticket=""
if [ -n "$tickets" ] && [ -n "$spec_files" ]; then
  by_ticket="$(grep -iFf <(printf '%s\n' "$tickets") <<<"$spec_files" || true)"
fi
if [ -n "$by_ticket" ]; then found=1; as_list <<<"$by_ticket"; else echo "- none"; fi
echo

echo "## Spec files sharing words with the branch name"
echo
# Words of the branch name without its type prefix, 3+ letters, lowercased.
words="$(sed -E 's#^[^/]+/##' <<<"$name" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9\n' '\n' | awk 'length >= 3' | sort -u)"
by_words=""
if [ -n "$words" ] && [ -n "$spec_files" ]; then
  by_words="$(WORDS="$words" awk '
    BEGIN { n = split(ENVIRON["WORDS"], w, "\n") }
    {
      p = tolower($0); score = 0
      for (i = 1; i <= n; i++) if (w[i] != "" && index(p, w[i])) score++
      if (score > 0) print score "\t" $0
    }' <<<"$spec_files" | sort -t$'\t' -k1,1nr -k2 | head -n 5)"
fi
if [ -n "$by_words" ]; then
  found=1
  awk -F'\t' '{ printf "- `%s` (%d matching word%s)\n", $2, $1, ($1 > 1 ? "s" : "") }' <<<"$by_words"
else
  echo "- none"
fi

[ "$found" = 1 ]
