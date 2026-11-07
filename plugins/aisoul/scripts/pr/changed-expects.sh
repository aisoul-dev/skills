#!/usr/bin/env bash
# Test expectations a branch changed or removed, not just added: an existing
# assertion bent to fit the code hides the bug it was written to catch.
#
#   changed-expects.sh [<branch>]
#
# Lists, per test file, assertion lines the branch removed, with the lines it
# added in the same hunk for comparison. Assertion lines: expect(...), assert...,
# toBe/toEqual/toMatch..., should..., snapshot updates.
# Env: PR_BASE (default: origin/HEAD, else origin/main).
set -euo pipefail

branch="${1:-HEAD}"
base="${PR_BASE:-}"
if [ -z "$base" ]; then
  base="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  [ -n "$base" ] || base=origin/main
fi

TESTS='*.test.* *.spec.* *_test.* *_spec.* **/__snapshots__/* **/tests/** **/test/** **/e2e/**'
# shellcheck disable=SC2086  # word splitting of the pathspec list is intended
diff="$(git -c core.quotePath=false diff -U0 "$base...$branch" -- $TESTS)"

out="$(awk '
  /^diff --git / { file = ""; next }
  /^\+\+\+ b\// { file = substr($0, 7); next }
  /^@@/ { if (hunk != "" && removed) print hunk; hunk = "  " file " " $0 "\n"; removed = 0; next }
  /^-[^-]/ && /expect\(|assert|\.to(Be|Equal|StrictEqual|Match|Have|Contain|Throw)|\.should|toMatchSnapshot|toMatchInlineSnapshot|^-exports\[/ {
    hunk = hunk "    " $0 "\n"; removed = 1; next
  }
  /^\+[^+]/ && /expect\(|assert|\.to(Be|Equal|StrictEqual|Match|Have|Contain|Throw)|\.should|toMatchSnapshot|^\+exports\[/ {
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
