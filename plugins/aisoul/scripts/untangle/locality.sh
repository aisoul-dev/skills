#!/usr/bin/env bash
# Change locality: how many files a typical commit touches in the given paths.
# Lower is better. Writes $OUT/locality.txt and prints it.
set -euo pipefail
# shellcheck source=SCRIPTDIR/lib.sh
source "$(dirname "$0")/lib.sh"

git log --since="$SINCE" --no-merges --name-only --pretty=tformat:@@ -- "${PATHS[@]}" \
| awk '/^@@$/ { if (n) print n; n = 0; next } NF { n++ } END { if (n) print n }' \
| sort -n \
| awk -v since="$SINCE" '
    { a[NR] = $1 }
    END {
      if (!NR) { print "commits: 0 (no history in window: " since ")"; exit }
      p = int(NR * 0.9); if (p < 1) p = 1
      print "commits:", NR, " median files/commit:", a[int((NR + 1) / 2)], " p90:", a[p], " window:", since
    }' \
| tee "$OUT/locality.txt"
