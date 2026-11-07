#!/usr/bin/env bash
# shellcheck disable=SC2016  # backticks in expected output are literal
# Tests for scripts/pr/risk-facts.sh: each signal is reported on a fixture
# branch, and a clean branch reports none.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FACTS="$ROOT/plugins/aisoul/scripts/pr/risk-facts.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
has() { grep -qF -- "$2" <<<"$1" || fail "expected: $2"; }
hasnt() { grep -qF -- "$2" <<<"$1" && fail "unexpected: $2"; true; }

cd "$WORK"
git init -q -b main
git config user.email risk@example.com
git config user.name risk
mkdir -p app/components app/auth tests db/migrations .github/workflows
cat > app/components/List.vue <<'EOF'
<script setup lang="ts">
async function load() {
  try { await fetchItems() } catch (e) { Sentry.captureException(e) }
}
</script>
EOF
printf "it('loads', () => {})\n" > tests/old.spec.ts
printf '{ "dependencies": { "vue": "3.4.0" } }\n' > package.json
git add -A && git commit -qm base

# --- a clean branch ------------------------------------------------------------
git checkout -q -b clean
printf '<p>hello</p>\n' > app/components/Hello.vue
git add -A && git commit -qm clean
out="$(PR_BASE=main bash "$FACTS" clean)"
has "$out" '- none matched'
has "$out" '- none found'
has "$out" '- 0 of 1 changed files are tests'

# --- a risky branch ------------------------------------------------------------
git checkout -q -b risky main
cat > app/components/List.vue <<'EOF'
<script setup lang="ts">
async function load() {
  try { await fetchItems() } catch {}
  const x = data as any
}
</script>
EOF
printf 'export const canEdit = () => true\n' > app/auth/permissions.ts
printf 'ALTER TABLE users DROP COLUMN legacy;\n' > db/migrations/002_drop.sql
printf 'on: push\n' > .github/workflows/ci.yml
printf '{ "dependencies": { "vue": "4.0.0" } }\n' > package.json
printf "it.skip('flaky', () => {})\n" > tests/new.spec.ts
git rm -q tests/old.spec.ts
printf 'if (useFeature("new-list")) {}\n' > app/components/flag.ts
git add -A && git commit -qm risky

out="$(PR_BASE=main bash "$FACTS" risky)"
echo "$out"
has "$out" '**auth and access**: `app/auth/permissions.ts`'
has "$out" '**data and schema**: `db/migrations/002_drop.sql`'
has "$out" '**infra and CI**: `.github/workflows/ci.yml`'
has "$out" '**dependencies**: `package.json`'
has "$out" '**Added swallowed errors**'
has "$out" '**Removed error reporting**'
has "$out" 'Sentry.captureException'
has "$out" '**Added type or lint escapes**'
has "$out" '**Skipped or removed tests**'
has "$out" '**Destructive data operations**'
has "$out" 'DROP COLUMN legacy'
has "$out" '**Feature flags**'
has "$out" '**Deleted test files**'
has "$out" 'tests/old.spec.ts'
hasnt "$out" 'ev/null'

# --- overlay extras and squash mode -------------------------------------------
out="$(PR_BASE=main PR_RISK_SENSITIVE='app/components/flag' bash "$FACTS" risky)"
has "$out" '**project-sensitive**: `app/components/flag.ts`'

out="$(bash "$FACTS" --squash "$(git rev-parse risky)")"
has "$out" 'against its parent'
has "$out" '**Destructive data operations**'

out="$(bash "$FACTS" clean 2>&1 || true)"
has "$out" 'origin/HEAD not set, fell back to main'

echo "pr-risk: OK"
