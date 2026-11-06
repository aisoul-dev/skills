# Shared setup for untangle scripts. Source it, do not run it.
#
# Inputs:
#   positional args   paths to measure (default: existing app/ server/ shared/ src/, else .)
#   UNTANGLE_SINCE    git history window (default: "6 months ago")
#   UNTANGLE_OUT      output directory (default: /tmp/untangle)

# shellcheck shell=bash
# shellcheck disable=SC2034  # variables are used by the scripts that source this file

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "untangle: run this from inside a git repository" >&2
  exit 1
}

SINCE="${UNTANGLE_SINCE:-6 months ago}"
OUT="${UNTANGLE_OUT:-/tmp/untangle}"
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$OUT"

if [ "$#" -gt 0 ]; then
  PATHS=("$@")
else
  PATHS=()
  for d in app server shared src; do
    [ -d "$d" ] && PATHS+=("$d/")
  done
  [ "${#PATHS[@]}" -eq 0 ] && PATHS=(.)
fi

# Prefer pnpm dlx, fall back to npx. Never installs into the project.
run_dlx() {
  if command -v pnpm >/dev/null 2>&1; then
    pnpm dlx "$@"
  else
    npx --yes "$@"
  fi
}
