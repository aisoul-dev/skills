#!/usr/bin/env bash
# Public surface (optional): runs the active adapter's surface.sh (see adapters/README.md).
# Without an adapter for this stack, or without this step in it, it writes
# an UNVERIFIED line to $OUT/surface/ and exits 0: the audit then finds these
# by reading and says so in the log.
set -euo pipefail
# shellcheck source=SCRIPTDIR/lib.sh
source "$(dirname "$0")/lib.sh"

if [ -n "$ADAPTER_DIR" ] && [ -f "$ADAPTER_DIR/surface.sh" ]; then
  exec bash "$ADAPTER_DIR/surface.sh" "$@"
fi

echo "surface: UNVERIFIED, adapter '$ADAPTER' has no surface step; use subagent summaries per area" >&2
