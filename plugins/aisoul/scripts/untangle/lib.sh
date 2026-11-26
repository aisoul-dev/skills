# Shared setup for untangle scripts. Source it, do not run it.
#
# Inputs:
#   positional args   paths to measure (default: the adapter's source folders
#                     that exist, else .)
#   UNTANGLE_SINCE    git history window (default: "6 months ago")
#   UNTANGLE_OUT      output directory (default: /tmp/untangle)
#   UNTANGLE_ADAPTER  stack adapter to use: a folder name under adapters/, or
#                     "none" (default: the first adapter whose detect.sh matches)
#
# Sets: SINCE, OUT, CORE_DIR, ADAPTER, ADAPTER_DIR, PATHS, EXTS, EXCLUDE_DIRS,
# EXTRA_PATTERNS. Adapters live in adapters/<name>/ (see adapters/README.md).

# shellcheck shell=bash
# shellcheck disable=SC2034  # variables are used by the scripts that source this file

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "untangle: run this from inside a git repository" >&2
  exit 1
}

SINCE="${UNTANGLE_SINCE:-6 months ago}"
OUT="${UNTANGLE_OUT:-/tmp/untangle}"
CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$OUT"

# Stack-neutral defaults; an adapter's adapter.env overrides them.
DEFAULT_PATHS="src lib app"
EXTS="ts tsx js jsx mjs cjs vue svelte py php rb go rs java kt cs swift"
EXCLUDE_DIRS="node_modules vendor dist build target .git .venv __pycache__ .next .nuxt .output coverage"
EXTRA_PATTERNS=()

ADAPTER="none"
ADAPTER_DIR=""
if [ -n "${UNTANGLE_ADAPTER:-}" ]; then
  if [ "$UNTANGLE_ADAPTER" != "none" ]; then
    if [ ! -f "$CORE_DIR/adapters/$UNTANGLE_ADAPTER/adapter.env" ]; then
      echo "untangle: no adapter '$UNTANGLE_ADAPTER' in $CORE_DIR/adapters" >&2
      exit 2
    fi
    ADAPTER="$UNTANGLE_ADAPTER"
  fi
else
  for d in "$CORE_DIR"/adapters/*/; do
    [ -f "$d/detect.sh" ] || continue
    if bash "$d/detect.sh" >/dev/null 2>&1; then
      ADAPTER="$(basename "$d")"
      break
    fi
  done
fi
if [ "$ADAPTER" != "none" ]; then
  ADAPTER_DIR="$CORE_DIR/adapters/$ADAPTER"
  # shellcheck source=/dev/null
  source "$ADAPTER_DIR/adapter.env"
fi

if [ "$#" -gt 0 ]; then
  PATHS=("$@")
else
  PATHS=()
  for d in $DEFAULT_PATHS; do
    [ -d "$d" ] && PATHS+=("$d/")
  done
  [ "${#PATHS[@]}" -eq 0 ] && PATHS=(.)
fi

# History-based measurements are meaningless on a shallow clone: they would
# report a quiet, well-factored codebase. Fail loudly instead.
require_history() {
  if [ "$(git rev-parse --is-shallow-repository 2>/dev/null)" = "true" ] && [ -z "${UNTANGLE_ALLOW_SHALLOW:-}" ]; then
    echo "untangle: shallow clone, git history is cut. Use 'fetch-depth: 0' in actions/checkout or 'git fetch --unshallow'. UNTANGLE_ALLOW_SHALLOW=1 overrides." >&2
    exit 3
  fi
}

# Prefer pnpm dlx, fall back to npx. Never installs into the project.
run_dlx() {
  if command -v pnpm >/dev/null 2>&1; then
    pnpm dlx "$@"
  else
    npx --yes "$@"
  fi
}
