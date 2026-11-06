#!/usr/bin/env bash
# Dependency direction: run dependency-cruiser with the rules in depcruise.cjs.
# Uses pnpm dlx / npx, adds nothing to the project. Writes $OUT/depcruise.txt.
#
# Auto-imported components and composables have no import statement, so this
# graph does not see them. Cover those with grep.
set -euo pipefail
# shellcheck source=SCRIPTDIR/lib.sh
source "$(dirname "$0")/lib.sh"

if [ -z "${UNTANGLE_TSCONFIG:-}" ]; then
  for f in .nuxt/tsconfig.app.json .nuxt/tsconfig.json tsconfig.json; do
    if [ -f "$f" ]; then UNTANGLE_TSCONFIG="$f"; break; fi
  done
fi
export UNTANGLE_TSCONFIG
if [ -z "${UNTANGLE_APP_PREFIX+set}" ]; then
  if [ -d app ]; then UNTANGLE_APP_PREFIX='app/'; else UNTANGLE_APP_PREFIX=''; fi
fi
export UNTANGLE_APP_PREFIX

[ -d .nuxt ] || echo "deps: no .nuxt/ found, run 'pnpm nuxt prepare' first for path aliases" >&2

set +e
run_dlx dependency-cruiser "${PATHS[@]}" \
  --config "$SCRIPTS_DIR/depcruise.cjs" --output-type err-long > "$OUT/depcruise.txt" 2>&1
status=$?
set -e

# dependency-cruiser exits non-zero when it finds violations; that is a result, not a failure.
echo "deps: exit $status, tsconfig ${UNTANGLE_TSCONFIG:-none} -> $OUT/depcruise.txt"
tail -n 3 "$OUT/depcruise.txt" || true
