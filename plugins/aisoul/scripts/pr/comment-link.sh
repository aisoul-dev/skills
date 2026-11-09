#!/usr/bin/env bash
# Link and placement line for a paste-ready review comment.
#
#   comment-link.sh <path> <line> [<end line>] [<branch>]
#
# Prints two lines:
#   1. the GitHub URL at the pushed commit of the branch, with ?plain=1 for
#      Markdown so the line anchor works
#   2. where to put the comment, since GitHub accepts inline comments only on
#      lines its diff view shows (changed lines plus 3 lines of context):
#        **File:** `<path>` · **Line:** <n>          (line is in the diff)
#        **File:** `<path>` · **Lines:** <n>–<m>
#        **File:** `<path>` · file-level comment (L<n> is outside the diff)
#        **Where:** general PR comment (about `<path>:<n>`)
# Env: PR_BASE (default: origin/HEAD, else origin/main, else main), PR_REPO to override owner/repo.
# Exit 1 when the branch is not pushed (a local-only sha gives a 404), on a
# detached HEAD without a branch argument, or when the line is past the end of
# the pushed file. Warns when the local file differs from the pushed one.
set -euo pipefail
# shellcheck source=SCRIPTDIR/lib.sh
source "$(dirname "$0")/lib.sh"
require_repo pr-comment-link

path="${1:?usage: comment-link.sh <path> <line> [<end line>] [<branch>]}"
line="${2:?usage: comment-link.sh <path> <line> [<end line>] [<branch>]}"
end="${3:-}"
branch="${4:-}"
if [ -n "$end" ] && ! [[ "$end" =~ ^[0-9]+$ ]]; then branch="$end"; end=""; fi
if [ -z "$branch" ]; then
  branch="$(git rev-parse --abbrev-ref HEAD)"
  [ "$branch" != HEAD ] || { echo "comment-link: detached HEAD; pass the branch name as the last argument" >&2; exit 1; }
fi

resolve_base
base="$BASE"

repo="${PR_REPO:-}"
if [ -z "$repo" ]; then
  url="$(git config --get remote.origin.url)"   # raw, before insteadOf rewriting
  # https://host/owner/repo(.git), git@host:owner/repo(.git), ssh-alias:owner/repo(.git)
  repo="$(sed -E 's#^[a-z]+://[^/]+/##; s#^[^/:]+:##; s#\.git$##' <<<"$url")"
fi

sha="$(git rev-parse --verify --quiet "origin/${branch#origin/}" || true)"
[ -n "$sha" ] || { echo "comment-link: origin/${branch#origin/} not found; push the branch first (a local sha gives a 404)" >&2; exit 1; }

# Line numbers must come from the pushed version, which is what the link shows.
total="$(git show "$sha:$path" 2>/dev/null | wc -l | tr -d ' ')" || total=0
[ "$total" -gt 0 ] || { echo "comment-link: $path does not exist at $(git rev-parse --short "$sha")" >&2; exit 1; }
[ "${end:-$line}" -le "$total" ] || { echo "comment-link: $path has $total lines at $(git rev-parse --short "$sha"), not ${end:-$line}" >&2; exit 1; }
if [ -f "$path" ] && ! git show "$sha:$path" | cmp -s - "$path"; then
  echo "comment-link: warning: local $path differs from the pushed version; check that line $line still points at the same code" >&2
fi

plain=""
case "$path" in *.md|*.mdx|*.markdown) plain="?plain=1" ;; esac
anchor="#L$line"; [ -n "$end" ] && anchor="#L$line-L$end"
echo "https://github.com/$repo/blob/$sha/$path$plain$anchor"

# Is the line (or range) inside one hunk of GitHub's view (3 lines of context)?
in_diff="$(git diff -U3 "$base...$sha" -- "$path" | awk -v a="$line" -v b="${end:-$line}" '
  /^@@/ {
    split($3, p, ","); s = substr(p[1], 2) + 0; n = (p[2] == "" ? 1 : p[2] + 0)
    if (n > 0 && a >= s && b <= s + n - 1) hit = 1
    any = 1
  }
  END { print (hit ? "line" : (any ? "file" : "none")) }
')"

case "$in_diff" in
  line)
    if [ -n "$end" ]; then echo "**File:** \`$path\` · **Lines:** ${line}–${end}"
    else echo "**File:** \`$path\` · **Line:** $line"; fi ;;
  file) echo "**File:** \`$path\` · file-level comment (L$line is outside the diff)" ;;
  *)    echo "**Where:** general PR comment (about \`$path:$line\`)" ;;
esac
