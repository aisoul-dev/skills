#!/usr/bin/env bash
# Test expectations a branch changed or removed, not just added: an existing
# assertion bent to fit the code hides the bug it was written to catch.
#
#   changed-expects.sh [<branch>]
#
# Lists, per test file, assertion lines the branch removed, with the lines it
# added in the same hunk for comparison. Assertion lines: expect(...), assert...,
# toBe/toEqual/toMatch..., should..., snapshot updates, shell checks ending in
# "|| fail" and lines calling has/hasnt/assert_*, plus PR_ASSERT (an ERE).
# Env: PR_BASE (default: origin/HEAD, else origin/main, else main), PR_ASSERT.
set -euo pipefail
# shellcheck source=SCRIPTDIR/lib.sh
source "$(dirname "$0")/lib.sh"
require_repo pr-changed-expects

branch="${1:-HEAD}"
resolve_base
base="$BASE"

TESTS='*.test.* *.spec.* *_test.* *_spec.* **/__snapshots__/* tests/** test/** e2e/** **/tests/** **/test/** **/e2e/**'
# shellcheck disable=SC2086  # word splitting of the pathspec list is intended
diff="$(git -c core.quotePath=false diff -U0 "$base...$branch" -- $TESTS)"

ASSERT='expect\(|assert|\.to(Be|Equal|StrictEqual|Match|Have|Contain|Throw)|\.should|toMatchSnapshot|toMatchInlineSnapshot|exports\[|\|\|[[:space:]]*fail([^[:alnum:]_]|$)|(^|[[:space:]])(has|hasnt|assert_[a-z_]+)[[:space:]]'
[ -n "${PR_ASSERT:-}" ] && ASSERT="$ASSERT|$PR_ASSERT"

# The pattern goes through ENVIRON, not -v, which would eat its backslashes.
out="$(ASSERT_RE="$ASSERT" awk '
  BEGIN { re = ENVIRON["ASSERT_RE"] }
  /^diff --git / { file = ""; next }
  /^\+\+\+ b\// { file = substr($0, 7); next }
  /^@@/ { if (hunk != "" && removed) print hunk; hunk = "  " file " " $0 "\n"; removed = 0; next }
  /^-[^-]/ && substr($0, 2) ~ re {
    hunk = hunk "    " $0 "\n"; removed = 1; next
  }
  /^\+[^+]/ && substr($0, 2) ~ re {
    hunk = hunk "    " $0 "\n"; next
  }
  END { if (hunk != "" && removed) print hunk }
' <<<"$diff")"

echo "# Changed or removed test expectations: $branch against $base"
echo
if [ -z "$out" ]; then
  echo "- none: every assertion change is an addition"
else
  echo '```diff'
  printf '%s\n' "$out" | sed '/^$/d'
  echo '```'
fi
