#!/usr/bin/env bash
# Review scope: how the branch stands against the remote base before any review.
#
#   scope.sh [<branch>]     # default: HEAD
#
# Prints commits behind and ahead, whether merging the base is clean, the
# conflicting files if not, the commit list and the diffstat.
# Env: PR_BASE (default: origin/HEAD, else origin/main), PR_NO_FETCH=1 to skip fetching.
# Exit: 0 up to date or clean merge, 3 behind with conflicts (stop the review).
set -euo pipefail

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "pr-scope: run this from inside a git repository" >&2
  exit 1
}

[ -n "${PR_NO_FETCH:-}" ] || git fetch -q origin 2>/dev/null || echo "scope: fetch failed, using local refs" >&2

base="${PR_BASE:-}"
if [ -z "$base" ]; then
  base="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  [ -n "$base" ] || base=origin/main
fi
git rev-parse --verify --quiet "$base" >/dev/null || { echo "scope: base '$base' not found; set PR_BASE" >&2; exit 1; }
branch="${1:-HEAD}"

behind="$(git rev-list --count "$branch..$base")"
ahead="$(git rev-list --count "$base..$branch")"

echo "# Scope: $branch against $base"
echo
echo "- Ahead: $ahead commits; behind: $behind commits"

status=0
if tree="$(git merge-tree --write-tree --name-only "$base" "$branch" 2>/dev/null)"; then
  echo "- Merge with $base: clean"
  if [ "$behind" -gt 0 ]; then
    echo "- Condition: update from $base before merging; gates on the branch do not prove the merged result"
  fi
else
  echo "- Merge with $base: **CONFLICTS**. Update from $base first; a review now is spent on code the resolution will change."
  echo "- Conflicting files:"
  # Output after the tree id: conflicted paths, then a blank line, then messages.
  awk 'NR == 1 { next } /^$/ { exit } { print "  - `" $0 "`" }' <<<"$tree"
  status=3
fi
echo

echo "## Commits"
echo
git log --oneline "$base..$branch" | sed 's/^/- /'
echo
echo "## Diffstat"
echo
echo '```text'
git -c core.quotePath=false diff --stat "$base...$branch"
echo '```'
exit "$status"
