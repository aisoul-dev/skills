#!/usr/bin/env bash
# Dependency direction: runs the active adapter's deps.sh (see adapters/README.md).
# Without an adapter for this stack, or without this step in it, it writes
# an UNVERIFIED line to $OUT/deps.txt and exits 0: the audit then finds these
# by reading and says so in the log.
set -euo pipefail
# shellcheck source=SCRIPTDIR/lib.sh
source "$(dirname "$0")/lib.sh"

if [ -n "$ADAPTER_DIR" ] && [ -f "$ADAPTER_DIR/deps.sh" ]; then
  exec bash "$ADAPTER_DIR/deps.sh" "$@"
fi

echo "UNVERIFIED: adapter '$ADAPTER' has no deps step for this stack; find these by reading" | tee "$OUT/deps.txt"
