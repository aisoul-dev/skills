#!/usr/bin/env bash
# Where the spec for a branch probably is. Lists, mechanically:
#   1. ticket and issue references in the branch name and commit messages
#   2. spec files the branch itself adds or changes
#   3. spec files whose path names one of those tickets
#   4. spec files whose name shares words with the branch name, best first
# It judges nothing: read the candidates, and ask the user when none fits.
#
#   spec-find.sh [<branch or sha>]
#
# Env:
#   PR_BASE        base ref (default: origin/HEAD, else origin/main, else main)
#   PR_SPEC_DIRS   spec folders from the repo root, one per line (default:
#                  docs/specs specs docs/superpowers/specs .scratch docs)
#   PR_TICKET_RE   ticket pattern, ERE (default: [A-Z][A-Z0-9]*-[0-9]+, minus
#                  standards such as UTF-8, SHA-256, ISO-8601, RFC-...)
# Exit: 0 with at least one candidate file, 1 with none (ask the user),
#       2 on an empty range or an invalid PR_TICKET_RE.
set -euo pipefail
# shellcheck source=SCRIPTDIR/lib.sh
source "$(dirname "$0")/lib.sh"
require_repo pr-spec-find

branch="${1:-HEAD}"
resolve_base

if [ -z "$(git rev-list -1 "$BASE..$branch")" ]; then
  echo "pr-spec-find: $branch against $BASE: $(empty_range_hint)" >&2
  exit 2
fi

ticket_re="${PR_TICKET_RE:-[A-Z][A-Z0-9]*-[0-9]+}"
rc=0; grep -qE "$ticket_re" </dev/null 2>/dev/null || rc=$?
[ "$rc" -le 1 ] || { echo "pr-spec-find: PR_TICKET_RE is not a valid extended regex: $ticket_re" >&2; exit 2; }
STANDARDS='^(UTF|SHA|ISO|RFC|MD|ES|IEEE|ECMA|HTTP|TLS|SSL)-'

name="$(git rev-parse --abbrev-ref "$branch" 2>/dev/null || true)"
[ -n "$name" ] && [ "$name" != HEAD ] || name=""
label="${name:-$(git rev-parse --short "$branch")}"
dirs="${PR_SPEC_DIRS:-$(printf '%s\n' docs/specs specs docs/superpowers/specs .scratch docs)}"

messages="$(git log --format='%s%n%b' "$BASE..$branch")"
tickets="$( { grep -oE "$ticket_re" <<<"$name" || true; grep -oE "$ticket_re" <<<"$messages" || true; } \
  | { if [ -z "${PR_TICKET_RE:-}" ]; then grep -vE "$STANDARDS" || true; else cat; fi; } | sort -u)"
issues="$(grep -oE '(([Cc]loses|[Ff]ixes|[Rr]esolves)[[:space:]]+)?#[0-9]+|![0-9]+' <<<"$messages" | sort -u || true)"

# Spec-like files in the spec folders at the branch's version, from the repo
# root (--full-tree) and unquoted, so the result does not depend on the cwd or
# on non-ASCII names.
spec_files="$(
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    git -c core.quotePath=false ls-tree --full-tree -r --name-only "$branch" -- "${d%/}/" 2>/dev/null
  done <<<"$dirs" | grep -E '\.(md|mdx|txt|ya?ml)$' | sort -u || true
)"

as_list() { awk -v q='`' '{ print "- " q $0 q }'; }

echo "# Spec candidates: $label against $BASE"
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

found=0
echo "## Spec files changed by the branch"
echo
changed=""
if [ -n "$spec_files" ]; then
  changed="$(git -c core.quotePath=false diff --name-only "$BASE...$branch" | grep -Fxf <(printf '%s\n' "$spec_files") || true)"
fi
if [ -n "$changed" ]; then found=1; as_list <<<"$changed"; else echo "- none"; fi
echo

echo "## Spec files naming a ticket"
echo
by_ticket=""
if [ -n "$tickets" ] && [ -n "$spec_files" ]; then
  # Whole ticket only: SHOP-7 must not match SHOP-77.
  by_ticket="$(TICKETS="$tickets" awk '
    BEGIN { n = split(tolower(ENVIRON["TICKETS"]), t, "\n") }
    {
      p = tolower($0)
      for (i = 1; i <= n; i++) {
        if (t[i] == "") continue
        s = p; off = 0
        while ((k = index(s, t[i])) > 0) {
          pos = off + k
          before = (pos == 1) ? "" : substr(p, pos - 1, 1)
          after = substr(p, pos + length(t[i]), 1)
          if (before !~ /[[:alnum:]]/ && after !~ /[[:digit:]]/) { print $0; next }
          off = pos; s = substr(p, pos + 1)
        }
      }
    }' <<<"$spec_files" | sort -u)"
fi
if [ -n "$by_ticket" ]; then found=1; as_list <<<"$by_ticket"; else echo "- none"; fi
echo

echo "## Spec files sharing words with the branch name"
echo
if [ -z "$name" ]; then
  echo "- skipped: $label is not a branch name"
else
  # Words of the branch name without its type prefix, 3+ letters, lowercased,
  # minus the spec folders' own names, matched against file names only.
  folder_words="$(tr '/' '\n' <<<"$dirs" | tr '[:upper:]' '[:lower:]' | sort -u)"
  words="$(sed -E 's#^[^/]+/##' <<<"$name" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9\n' '\n' \
    | awk 'length >= 3' | sort -u | grep -vxFf <(printf '%s\n' "$folder_words") || true)"
  by_words=""
  if [ -n "$words" ] && [ -n "$spec_files" ]; then
    by_words="$(WORDS="$words" awk '
      BEGIN { n = split(ENVIRON["WORDS"], w, "\n") }
      {
        f = tolower($0); sub(/.*\//, "", f); score = 0
        for (i = 1; i <= n; i++) if (w[i] != "" && index(f, w[i])) score++
        if (score > 0) print score "\t" $0
      }' <<<"$spec_files" | sort -t$'\t' -k1,1nr -k2 | head -n 5)"
  fi
  if [ -n "$by_words" ]; then
    found=1
    awk -F'\t' '{ printf "- `%s` (%d matching word%s)\n", $2, $1, ($1 > 1 ? "s" : "") }' <<<"$by_words"
  else
    echo "- none"
  fi
fi

[ "$found" = 1 ]
