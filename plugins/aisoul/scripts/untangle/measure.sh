#!/usr/bin/env bash
# Run every untangle measurement and print a summary.
# Git-based measurements run first; the ones that download tools run last and
# never stop the run if they fail.
#
#   measure.sh                 # default paths
#   measure.sh app/features/x  # scoped
#   UNTANGLE_SKIP_NET=1 measure.sh   # skip knip and dependency-cruiser
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "== locality";  bash "$DIR/locality.sh" "$@" || echo "locality failed"
echo "== churn";     bash "$DIR/churn.sh" "$@"    || echo "churn failed"
echo "== cochange";  bash "$DIR/cochange.sh" "$@" || echo "cochange failed"
echo "== patches";   bash "$DIR/patches.sh" "$@"  || echo "patches failed"

if [ -z "${UNTANGLE_SKIP_NET:-}" ]; then
  echo "== deps";       bash "$DIR/deps.sh" "$@"       || echo "deps failed"
  echo "== deadweight"; bash "$DIR/deadweight.sh" "$@" || echo "deadweight failed"
fi

echo "== commit: $(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
