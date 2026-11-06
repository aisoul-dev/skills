#!/usr/bin/env bash
# Dead weight: unused files, exports and dependencies via knip.
# Every hit must be verified by grep before it becomes a finding:
# resolveComponent, <component :is>, string lookups, server routes and
# test-only usage give false positives. Writes $OUT/knip.txt.
set -euo pipefail
# shellcheck source=SCRIPTDIR/lib.sh
source "$(dirname "$0")/lib.sh"

set +e
run_dlx knip --reporter compact --no-exit-code > "$OUT/knip.txt" 2>&1
status=$?
set -e

echo "deadweight: exit $status, $(wc -l < "$OUT/knip.txt") lines -> $OUT/knip.txt"
