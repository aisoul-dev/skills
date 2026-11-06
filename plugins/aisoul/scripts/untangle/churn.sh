#!/usr/bin/env bash
# Churn: the most frequently changed files. Writes $OUT/churn.txt.
set -euo pipefail
# shellcheck source=SCRIPTDIR/lib.sh
source "$(dirname "$0")/lib.sh"

TOP="${UNTANGLE_TOP:-40}"

git log --since="$SINCE" --no-merges --name-only --pretty=tformat: -- "${PATHS[@]}" \
| awk 'NF' | sort | uniq -c | sort -rn | head -n "$TOP" > "$OUT/churn.txt"

echo "churn: $(wc -l < "$OUT/churn.txt") files -> $OUT/churn.txt"
