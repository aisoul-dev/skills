#!/usr/bin/env bash
# Nuxt adapter, dependency direction: dependency-cruiser with the rules in
# depcruise.cjs. Uses pnpm dlx / npx, adds nothing to the project.
# Writes $OUT/deps.txt. Env: UNTANGLE_TS_VERSION (default ^6).
#
# Auto-imported components and composables have no import statement, so this
# graph does not see them. Cover those with grep.
set -euo pipefail
# shellcheck source=SCRIPTDIR/../../lib.sh
source "$(dirname "$0")/../../lib.sh"

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

# dependency-cruiser needs a TypeScript it supports next to it; a one-off run
# otherwise pulls the newest one, and an unsupported version makes it parse
# no .ts files at all while reporting "no violations".
TS="typescript@${UNTANGLE_TS_VERSION:-^6}"
CONFIG="$(cd "$(dirname "$0")" && pwd)/depcruise.cjs"

set +e
if command -v pnpm >/dev/null 2>&1; then
  pnpm dlx --package=dependency-cruiser --package="$TS" depcruise "${PATHS[@]}" \
    --config "$CONFIG" --output-type err-long > "$OUT/deps.txt" 2>&1
else
  npx --yes -p dependency-cruiser -p "$TS" depcruise "${PATHS[@]}" \
    --config "$CONFIG" --output-type err-long > "$OUT/deps.txt" 2>&1
fi
status=$?
set -e

# A run that cruised nothing is not a clean result.
if grep -qE '\(0 modules' "$OUT/deps.txt"; then
  { echo "UNVERIFIED: dependency-cruiser parsed 0 modules (TypeScript or path setup); find dependency direction by reading"; cat "$OUT/deps.txt"; } > "$OUT/deps.tmp"
  mv "$OUT/deps.tmp" "$OUT/deps.txt"
  echo "deps: UNVERIFIED, 0 modules parsed" >&2
fi

# dependency-cruiser exits non-zero when it finds violations; that is a result, not a failure.
echo "deps: exit $status, tsconfig ${UNTANGLE_TSCONFIG:-none} -> $OUT/deps.txt"
tail -n 3 "$OUT/deps.txt" || true
