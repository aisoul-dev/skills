#!/usr/bin/env bash
# Patch census: grep candidates for code that hides a design gap.
# Candidates only: multi-line swallowed errors, guard flags and one-caller
# parameters are found by reading, not by grep.
#
# The core patterns cover common languages; the active adapter sets which file
# extensions and folders count and may add stack-specific patterns.
# Accepts directories or individual files (untangle-fix passes touched files).
# Writes $OUT/patches.txt (label:file:line:text) and prints counts per label.
set -euo pipefail
# shellcheck source=SCRIPTDIR/lib.sh
source "$(dirname "$0")/lib.sh"

# With no explicit paths, include test directories as well.
if [ "$#" -eq 0 ]; then
  for d in tests test spec __tests__; do
    [ -d "$d" ] && PATHS+=("$d/")
  done
fi

PATTERNS=(
  'timing|setTimeout\(|nextTick\(|sleep\(|usleep\(|time\.sleep|[Rr]etry'
  'swallowed-error|catch\s*(\([^)]*\))?\s*\{\s*\}|\.catch\(\(\)\s*=>\s*\{?\s*\}?\)|except[^:]*:\s*pass\b'
  'type-escape|@ts-(ignore|expect-error)|\bas any\b|:\s*any\b|#\s*type:\s*ignore|@phpstan-ignore|@psalm-suppress'
  'lint-escape|eslint-disable|#\s*noqa|phpcs:ignore|rubocop:disable|//\s*nolint|@SuppressWarnings'
  'skipped-test|\b(it|test|describe)\.(skip|todo)\(|@pytest\.mark\.skip|markTestSkipped|@Disabled\b|t\.Skip\('
  'marker|\b(TODO|FIXME|HACK|XXX)\b'
  ${EXTRA_PATTERNS[@]+"${EXTRA_PATTERNS[@]}"}
)

RG_ARGS=()
GREP_ARGS=()
for e in $EXTS; do
  RG_ARGS+=(-g "*.$e")
  GREP_ARGS+=("--include=*.$e")
done
for d in $EXCLUDE_DIRS; do
  RG_ARGS+=(-g "!$d/")
  GREP_ARGS+=("--exclude-dir=$d")
done

search() {
  if command -v rg >/dev/null 2>&1; then
    rg -n --no-heading "${RG_ARGS[@]}" -e "$1" "${PATHS[@]}" || true
  else
    grep -rnE "${GREP_ARGS[@]}" -e "$1" "${PATHS[@]}" || true
  fi
}

: > "$OUT/patches.txt"
total=0
for p in "${PATTERNS[@]}"; do
  [ -n "$p" ] || continue
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
echo "patches -> $OUT/patches.txt (adapter: $ADAPTER)"
