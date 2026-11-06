#!/usr/bin/env bash
# Co-change: file pairs committed together, most frequent first.
# Commits touching more than UNTANGLE_MAX_FILES files (default 25) are skipped:
# mass renames and formatting runs say nothing about design.
# Writes $OUT/cochange.txt.
set -euo pipefail
# shellcheck source=SCRIPTDIR/lib.sh
source "$(dirname "$0")/lib.sh"

TOP="${UNTANGLE_TOP:-60}"
MAX="${UNTANGLE_MAX_FILES:-25}"

git log --since="$SINCE" --no-merges --name-only --pretty=tformat:@@ -- "${PATHS[@]}" \
| awk -v max="$MAX" '
    function flush() {
      if (n > 1 && n <= max)
        for (i = 1; i <= n; i++)
          for (j = i + 1; j <= n; j++)
            print f[i] "  <->  " f[j]
      n = 0
    }
    /^@@$/ { flush(); next }
    NF     { f[++n] = $0 }
    END    { flush() }' \
| sort | uniq -c | sort -rn | head -n "$TOP" > "$OUT/cochange.txt"

echo "cochange: $(wc -l < "$OUT/cochange.txt") pairs -> $OUT/cochange.txt"
