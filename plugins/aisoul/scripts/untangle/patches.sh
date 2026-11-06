#!/usr/bin/env bash
# Patch census: grep candidates for code that hides a design gap.
# Candidates only: multi-line swallowed errors, guard flags and one-caller
# parameters are found by reading, not by grep.
#
# Accepts directories or individual files (untangle-fix passes touched files).
# Writes $OUT/patches.txt (label:file:line:text) and prints counts per label.
set -euo pipefail
# shellcheck source=SCRIPTDIR/lib.sh
source "$(dirname "$0")/lib.sh"

# With no explicit paths, include test directories as well.
if [ "$#" -eq 0 ]; then
  for d in tests test; do
    [ -d "$d" ] && PATHS+=("$d/")
  done
fi

PATTERNS=(
  'timing|setTimeout\(|nextTick\(|sleep\(|[Rr]etry'
  'swallowed-error|catch\s*(\(\w*\))?\s*\{\s*\}|\.catch\(\(\)\s*=>\s*\{?\s*\}?\)'
  'type-escape|@ts-(ignore|expect-error)|\bas any\b|:\s*any\b'
  'lint-escape|eslint-disable'
  'skipped-test|\b(it|test|describe)\.(skip|todo)\('
  'marker|\b(TODO|FIXME|HACK|XXX)\b'
  'route-branch|route\.(name|path)\s*==='
)

search() {
  if command -v rg >/dev/null 2>&1; then
    rg -n --no-heading -g '*.{ts,tsx,js,mjs,vue}' -e "$1" "${PATHS[@]}" || true
  else
    grep -rnE --include='*.ts' --include='*.tsx' --include='*.js' --include='*.mjs' --include='*.vue' \
      --exclude-dir=node_modules --exclude-dir=.nuxt --exclude-dir=.output --exclude-dir=dist \
      -e "$1" "${PATHS[@]}" || true
  fi
}

: > "$OUT/patches.txt"
total=0
for p in "${PATTERNS[@]}"; do
  label="${p%%|*}"
  re="${p#*|}"
  hits="$(search "$re")"
  count=0
  if [ -n "$hits" ]; then
    count="$(printf '%s\n' "$hits" | wc -l | tr -d ' ')"
    printf '%s\n' "$hits" | sed "s/^/$label:/" >> "$OUT/patches.txt"
  fi
  total=$((total + count))
  printf '%-16s %s\n' "$label" "$count"
done
printf '%-16s %s\n' "total" "$total"
echo "patches -> $OUT/patches.txt"
