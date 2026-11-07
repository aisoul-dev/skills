#!/usr/bin/env bash
# Stacked branches: remote branches built on this branch's own commits.
#
#   stacked.sh [<branch>] [-- <path>...]
#
# For each stacked branch B: its own changes counted from the merge base with
# this branch (not HEAD..B, which a later merge of the base turns into a
# reversed copy of the base), whether it merges cleanly with this branch and
# with the base, and how far behind the base it is. With paths, also B's diff
# for those paths, to see whether B fixes a finding.
# Env: PR_BASE (default: origin/HEAD, else origin/main).
set -euo pipefail

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "pr-stacked: run this from inside a git repository" >&2
  exit 1
}

branch=HEAD
if [ "${1:-}" != "" ] && [ "${1:-}" != "--" ]; then branch="$1"; shift; fi
[ "${1:-}" = "--" ] && shift
paths=("$@")

base="${PR_BASE:-}"
if [ -z "$base" ]; then
  base="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  [ -n "$base" ] || base=origin/main
fi

self_remote=""
self_name="$(git rev-parse --abbrev-ref "$branch" 2>/dev/null || true)"
[ -n "$self_name" ] && [ "$self_name" != HEAD ] && self_remote="origin/$self_name"
head_sha="$(git rev-parse "$branch")"

stacked="$(
  for c in $(git rev-list --no-merges "$base..$branch"); do
    git branch -r --contains "$c"
  done | sed 's/^[ *]*//' | grep -v -- '->' | sort -u | while read -r b; do
    [ "$b" = "$self_remote" ] && continue
    [ "$b" = "$base" ] && continue
    # Not stacked if it holds only this branch's own commits: same tip or an
    # ancestor (an older push of this branch, or a branch this one is built on).
    [ "$(git rev-parse "$b")" = "$head_sha" ] && continue
    git merge-base --is-ancestor "$b" "$head_sha" && continue
    echo "$b"
  done
)"

echo "# Stacked on $branch"
echo
if [ -z "$stacked" ]; then
  echo "- none"
  exit 0
fi

merge_state() { git merge-tree --write-tree "$1" "$2" >/dev/null 2>&1 && echo clean || echo CONFLICTS; }

while read -r b; do
  mb="$(git merge-base "$branch" "$b")"
  echo "## \`$b\`"
  echo
  echo "- Own changes (from merge base $(git rev-parse --short "$mb")): $(git diff --shortstat "$mb" "$b" | sed 's/^ //')"
  echo "- Merge with $branch: $(merge_state "$branch" "$b"); with $base: $(merge_state "$base" "$b")"
  echo "- Behind $base: $(git rev-list --count "$b..$base") commits"
  if [ "${#paths[@]}" -gt 0 ]; then
    echo
    echo '```diff'
    git -c core.quotePath=false diff "$mb" "$b" -- "${paths[@]}"
    echo '```'
  fi
  echo
done <<<"$stacked"
