#!/usr/bin/env bash
# Diff size for a PR description: changed lines without excluded paths, and
# the shape that follows from them (small <= PR_SMALL_MAX lines, else large).
#
#   size.sh                 # current branch against the base
#   size.sh <branch>        # a branch against the base
#   size.sh --squash <sha>  # a squash or merge commit against its first parent
#
# Env:
#   PR_BASE       base ref (default: origin/HEAD, else origin/main, else main)
#   PR_EXCLUDE    space-separated paths excluded on top of the defaults
#   PR_SMALL_MAX  threshold for the small shape (default 50)
set -euo pipefail

# shellcheck source=SCRIPTDIR/lib.sh
source "$(dirname "$0")/lib.sh"
require_repo pr-size

SMALL_MAX="${PR_SMALL_MAX:-50}"
DEFAULT_EXCLUDE="docs pnpm-lock.yaml package-lock.json yarn.lock bun.lock bun.lockb"

pathspec=(.)
# shellcheck disable=SC2086  # word splitting of the exclude lists is intended
for p in $DEFAULT_EXCLUDE ${PR_EXCLUDE:-}; do
  pathspec+=(":(exclude)${p%/}")
done

if [ "${1:-}" = "--squash" ]; then
  sha="${2:?usage: size.sh --squash <sha>}"
  stat="$(git diff --shortstat "$sha^1" "$sha" -- "${pathspec[@]}")"
  raw="$(git diff --shortstat "$sha^1" "$sha")"
  label="commit $sha (against its first parent; a merge commit counts its whole PR)"
else
  resolve_base
  base="$BASE"; note="$BASE_NOTE"
  branch="${1:-HEAD}"
  stat="$(git diff --shortstat "$base...$branch" -- "${pathspec[@]}")"
  raw="$(git diff --shortstat "$base...$branch")"
  label="$branch against $base${note:-}"
fi

if [ -z "$raw" ]; then
  echo "$label: empty diff. $(empty_range_hint)" >&2
  exit 2
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

excluded="$DEFAULT_EXCLUDE${PR_EXCLUDE:+ $PR_EXCLUDE}"
echo "$label: $files files, +$ins -$del ($total changed lines, excluded: ${excluded})"
echo "shape: $shape (up to ~$budget words outside <details>)"
