#!/usr/bin/env bash
# Smoke test for the untangle git and grep scripts on a throwaway repo.
# Network-dependent scripts (deps, deadweight) are not run here.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$ROOT/plugins/aisoul/scripts/untangle"
WORK="$(mktemp -d)"
OUT="$(mktemp -d)"
trap 'rm -rf "$WORK" "$OUT"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

cd "$WORK"
git init -q
git config user.email smoke@example.com
git config user.name smoke
mkdir -p app/components app/composables server tests

commit() { for f in "$@"; do echo "// $RANDOM" >> "$f"; done; git add -A; git commit -qm change; }

commit app/composables/useA.ts app/components/B.vue
commit app/composables/useA.ts app/components/B.vue server/api.ts
commit app/composables/useA.ts app/components/B.vue
commit server/api.ts

cat >> app/composables/useA.ts <<'EOF'
export function useA() {
  setTimeout(() => {}, 0)
  const x = {} as any
  try { load() } catch {}
  return x
}
EOF
cat >> tests/a.test.ts <<'EOF'
it.skip('later', () => {})
EOF
git add -A && git commit -qm patches

export UNTANGLE_OUT="$OUT"

loc="$(bash "$SCRIPTS/locality.sh")"
echo "$loc"
grep -q 'commits: 5' <<<"$loc" || fail "locality should count 5 commits"
grep -q 'median files/commit: 2' <<<"$loc" || fail "locality median should be 2"

bash "$SCRIPTS/churn.sh" >/dev/null
head -n1 "$OUT/churn.txt" | grep -q 'app/composables/useA.ts' || fail "useA.ts should be the hottest file"

bash "$SCRIPTS/cochange.sh" >/dev/null
head -n1 "$OUT/cochange.txt" | grep -qE '3 app/components/B.vue  <->  app/composables/useA.ts' \
  || fail "B.vue <-> useA.ts should co-change 3 times: $(head -n1 "$OUT/cochange.txt")"

counts="$(bash "$SCRIPTS/patches.sh")"
echo "$counts"
grep -qE '^timing +1$' <<<"$counts"          || fail "timing should be 1"
grep -qE '^type-escape +1$' <<<"$counts"     || fail "type-escape should be 1"
grep -qE '^swallowed-error +1$' <<<"$counts" || fail "swallowed-error should be 1"
grep -qE '^skipped-test +1$' <<<"$counts"    || fail "skipped-test should be 1 (tests/ included by default)"

scoped="$(bash "$SCRIPTS/patches.sh" app/components/B.vue)"
grep -qE '^total +0$' <<<"$scoped" || fail "scoped census on B.vue should be 0"

UNTANGLE_SKIP_NET=1 bash "$SCRIPTS/measure.sh" >/dev/null || fail "measure.sh failed"

echo "smoke: OK"
