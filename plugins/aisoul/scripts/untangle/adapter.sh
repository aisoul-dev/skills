#!/usr/bin/env bash
# Print the stack adapter untangle will use here, and its reference file.
#   adapter.sh            ->  nuxt  /path/to/adapters/nuxt/reference.md
#   (no adapter)          ->  none
set -euo pipefail
# shellcheck source=SCRIPTDIR/lib.sh
source "$(dirname "$0")/lib.sh"

if [ "$ADAPTER" = none ]; then
  echo "none"
else
  echo "$ADAPTER  $ADAPTER_DIR/reference.md"
fi
