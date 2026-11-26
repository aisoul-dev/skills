#!/usr/bin/env bash
# Smoke test for the untangle git and grep scripts on throwaway repos:
# the Nuxt adapter, the stack-neutral core, and the shallow-clone guard.
# Network-dependent adapter steps (deps, deadweight) are not run here.
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
echo 'export default defineNuxtConfig({})' > nuxt.config.ts

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

grep -qE '^route-branch +0$' <<<"$counts" || fail "nuxt adapter adds route-branch"

m="$(UNTANGLE_SKIP_NET=1 bash "$SCRIPTS/measure.sh")" || fail "measure.sh failed"
grep -q '== adapter: nuxt' <<<"$m" || fail "nuxt adapter should be detected"
[ "$(cat "$OUT/adapter.txt")" = nuxt ] || fail "adapter.txt should say nuxt"

### stack-neutral core
none="$(UNTANGLE_ADAPTER=none bash "$SCRIPTS/patches.sh")"
if grep -q 'route-branch' <<<"$none"; then fail "core must not run nuxt patterns"; fi
UNTANGLE_ADAPTER=none bash "$SCRIPTS/deps.sh" >/dev/null || fail "deps without adapter must exit 0"
grep -q "^UNVERIFIED: adapter 'none' has no deps step" "$OUT/deps.txt" || fail "deps without adapter writes UNVERIFIED"
UNTANGLE_ADAPTER=none bash "$SCRIPTS/deadweight.sh" >/dev/null || fail "deadweight without adapter must exit 0"
grep -q '^UNVERIFIED' "$OUT/deadweight.txt" || fail "deadweight without adapter writes UNVERIFIED"
UNTANGLE_ADAPTER=none bash "$SCRIPTS/surface.sh" 2>/dev/null || fail "surface without adapter must exit 0"
if UNTANGLE_ADAPTER=nope bash "$SCRIPTS/patches.sh" 2>/dev/null; then fail "unknown adapter should exit 2"; fi

# Other languages, found by the core patterns without any adapter.
POLY="$(mktemp -d)"
(
  cd "$POLY"
  git init -q
  git config user.email smoke@example.com
  git config user.name smoke
  mkdir -p src tests
  printf '%s\n' 'try:' '    run()' 'except Exception: pass' 'x = load()  # type: ignore' 'time.sleep(1)' > src/svc.py
  # shellcheck disable=SC2016  # literal PHP source
  printf '%s\n' '<?php' 'try { run(); } catch (Exception $e) {}' '// phpcs:ignore' > src/Svc.php
  printf '%s\n' '@pytest.mark.skip' 'def test_later(): pass' > tests/test_svc.py
  git add -A
  git commit -qm poly
  poly="$(bash "$SCRIPTS/patches.sh")"
  echo "$poly"
  grep -qE '^swallowed-error +2$' <<<"$poly" || fail "python and php swallowed errors"
  grep -qE '^type-escape +1$' <<<"$poly"     || fail "python type: ignore"
  grep -qE '^lint-escape +1$' <<<"$poly"     || fail "phpcs:ignore"
  grep -qE '^timing +1$' <<<"$poly"          || fail "time.sleep"
  grep -qE '^skipped-test +1$' <<<"$poly"    || fail "pytest skip"
  grep -q '(adapter: none)' <<<"$poly"       || fail "no adapter for a python/php repo"
)
rm -rf "$POLY"

### shallow clone
SHALLOW="$(mktemp -d)"
git clone -q --depth 1 "file://$WORK" "$SHALLOW/repo"
(
  cd "$SHALLOW/repo"
  if bash "$SCRIPTS/locality.sh" 2>/dev/null; then fail "locality on a shallow clone should exit 3"; fi
  err="$(bash "$SCRIPTS/cochange.sh" 2>&1 || true)"
  grep -q 'fetch-depth: 0' <<<"$err" || fail "shallow error should say how to fix it"
  if UNTANGLE_SKIP_NET=1 bash "$SCRIPTS/measure.sh" >/dev/null 2>&1; then fail "measure on a shallow clone should fail"; fi
  UNTANGLE_ALLOW_SHALLOW=1 bash "$SCRIPTS/locality.sh" >/dev/null || fail "override should allow a shallow clone"
  bash "$SCRIPTS/patches.sh" >/dev/null || fail "patches needs no history"
)
rm -rf "$SHALLOW"

echo "smoke: OK"
