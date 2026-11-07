#!/usr/bin/env bash
# Ratchet count: occurrences of a pattern added and removed by a branch.
#
#   ratchet.sh '<ERE>' [<branch>] [-- <pathspec>...]
#
# Example, explicit `any` in TypeScript and Vue:
#   ratchet.sh '(:|<|,|\bas)\s*any\b' -- '*.ts' '*.vue'
#
# Prints "added N, removed M, net D" and exits 0 when net < 0, 1 when net == 0,
# 2 when net > 0, so a caller can map it to the project's rule.
# Env: PR_BASE (default: origin/HEAD, else origin/main, else main).
set -euo pipefail
# shellcheck source=SCRIPTDIR/lib.sh
source "$(dirname "$0")/lib.sh"
require_repo pr-ratchet

re="${1:?usage: ratchet.sh '<ERE>' [<branch>] [-- <pathspec>...]}"
shift
branch=HEAD
if [ "${1:-}" != "" ] && [ "${1:-}" != "--" ]; then branch="$1"; shift; fi
[ "${1:-}" = "--" ] && shift

resolve_base
base="$BASE"

diff="$(git diff -U0 "$base...$branch" -- "$@")"
count() { grep -E "$1" <<<"$diff" | grep -oE "$re" | wc -l | tr -d ' ' || true; }
added="$(count '^\+[^+]')"
removed="$(count '^-[^-]')"
net=$((added - removed))
echo "added $added, removed $removed, net $net"
if [ "$net" -lt 0 ]; then exit 0; elif [ "$net" -eq 0 ]; then exit 1; else exit 2; fi
