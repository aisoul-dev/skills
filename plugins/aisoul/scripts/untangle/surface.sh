#!/usr/bin/env bash
# Public surface: emit .d.ts declarations only, so the whole API of the
# codebase fits in context. Optional. Needs vue-tsc in the project.
# Type errors are fine as long as files are emitted. Writes $OUT/surface/.
set -euo pipefail
# shellcheck source=SCRIPTDIR/lib.sh
source "$(dirname "$0")/lib.sh"

TSCONFIG="${UNTANGLE_TSCONFIG:-}"
if [ -z "$TSCONFIG" ]; then
  for f in .nuxt/tsconfig.app.json .nuxt/tsconfig.json tsconfig.json; do
    if [ -f "$f" ]; then TSCONFIG="$f"; break; fi
  done
fi

rm -rf "$OUT/surface"
set +e
if command -v pnpm >/dev/null 2>&1; then
  pnpm exec vue-tsc --declaration --emitDeclarationOnly --noEmit false \
    --outDir "$OUT/surface" -p "$TSCONFIG" > "$OUT/surface.log" 2>&1
else
  npx --no-install vue-tsc --declaration --emitDeclarationOnly --noEmit false \
    --outDir "$OUT/surface" -p "$TSCONFIG" > "$OUT/surface.log" 2>&1
fi
set -e

n="$(find "$OUT/surface" -name '*.d.ts' 2>/dev/null | wc -l | tr -d ' ')"
if [ "$n" -gt 0 ]; then
  echo "surface: $n declaration files -> $OUT/surface/"
else
  echo "surface: nothing emitted (see $OUT/surface.log); fall back to subagent summaries" >&2
fi
