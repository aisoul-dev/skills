#!/usr/bin/env bash
# Diff size for a PR description: changed lines without excluded paths, and
# the shape that follows from them (small <= PR_SMALL_MAX lines, else large).
#
#   size.sh                 # current branch against the base
#   size.sh <branch>        # a branch against the base
#   size.sh --squash <sha>  # a squash-merged commit against its parent
#
# Env:
#   PR_BASE       base ref (default: origin/HEAD, else main)
#   PR_EXCLUDE    space-separated paths excluded on top of the defaults
#   PR_SMALL_MAX  threshold for the small shape (default 50)
set -euo pipefail

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "pr-size: run this from inside a git repository" >&2
  exit 1
}

SMALL_MAX="${PR_SMALL_MAX:-50}"
DEFAULT_EXCLUDE="docs pnpm-lock.yaml package-lock.json yarn.lock bun.lock bun.lockb"

pathspec=(.)
# shellcheck disable=SC2086  # word splitting of the exclude lists is intended
for p in $DEFAULT_EXCLUDE ${PR_EXCLUDE:-}; do
  pathspec+=(":(exclude)${p%/}")
done

if [ "${1:-}" = "--squash" ]; then
  sha="${2:?usage: size.sh --squash <sha>}"
  stat="$(git show --shortstat --format= "$sha" -- "${pathspec[@]}")"
  label="squash $sha (against $sha^)"
else
  base="${PR_BASE:-}"
  if [ -z "$base" ]; then
    base="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
    [ -n "$base" ] || { base=main; note=" (origin/HEAD not set, fell back to main)"; }
  fi
  branch="${1:-HEAD}"
  stat="$(git diff --shortstat "$base...$branch" -- "${pathspec[@]}")"
  label="$branch against $base${note:-}"
fi

ins="$(sed -nE 's/.* ([0-9]+) insertion.*/\1/p' <<<"$stat")"
del="$(sed -nE 's/.* ([0-9]+) deletion.*/\1/p' <<<"$stat")"
files="$(sed -nE 's/^ *([0-9]+) file.*/\1/p' <<<"$stat")"
ins="${ins:-0}"; del="${del:-0}"; files="${files:-0}"
total=$((ins + del))

if [ "$total" -le "$SMALL_MAX" ]; then
  shape="small"; budget=150
else
  shape="large"; budget=400
fi

echo "$label: $files files, +$ins -$del ($total changed lines, excluded: $DEFAULT_EXCLUDE ${PR_EXCLUDE:-})"
echo "shape: $shape (up to ~$budget words outside <details>)"
