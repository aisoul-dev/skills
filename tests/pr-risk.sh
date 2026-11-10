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
has "$out" '**project-sensitive `app/components/flag`**: `app/components/flag.ts`'

out="$(bash "$FACTS" --squash "$(git rev-parse risky)")"
has "$out" 'against its first parent'
has "$out" '**Destructive data operations**'

out="$(bash "$FACTS" clean 2>&1 || true)"
has "$out" 'fell back to main'

# --- merged PRs: a merge commit, and an empty range with a hint ---------------
git checkout -q main
git merge -q --no-ff -m "merge risky" risky
out="$(bash "$FACTS" --squash "$(git rev-parse main)")"
has "$out" 'merge commit'
has "$out" '**Destructive data operations**'
out="$(PR_BASE=main bash "$FACTS" risky)" && fail "an empty range must exit non-zero"
has "$out" '- Diff: **empty**'
has "$out" 'PR_BASE=<base sha>'
out="$(PR_BASE="$(git rev-parse main^1)" bash "$FACTS" risky)"
has "$out" '**Destructive data operations**'

SIZE="$ROOT/plugins/aisoul/scripts/pr/size.sh"
out="$(bash "$SIZE" --squash "$(git rev-parse main)")"
grep -qE 'shape: (small|large)' <<<"$out" || fail "size.sh --squash on a merge commit: $out"
grep -q ' 0 files' <<<"$out" && fail "size.sh counted 0 files on a merge commit"
if out="$(PR_BASE=main bash "$SIZE" risky 2>&1)"; then fail "size.sh on an empty range must fail"; fi
has "$out" 'empty diff'

# --- precision: names, yaml, paths in front of the line, multi-line catches ---
git checkout -q -b edges main
mkdir -p app/composables app/services app/locales app/plugins
for f in app/composables/useAuth.ts app/services/AuthService.ts app/author.ts app/controller.ts; do
  printf 'export const x = 1\n' > "$f"
done
printf 'title: Hello\n' > app/locales/en.yaml
printf 'export const a = 1\n' > app/plugins/datadog.ts
cat > app/load.ts <<'EOF'
export async function load() {
  try {
    await fetchItems()
  } catch (e) {
    console.error(e)
  }
  try {
    await other()
  } catch {
    // ignore
  }
  try {
    await third()
  } catch (e) {
    Sentry.captureException(e)
  }
  promise.catch(noop)
}
EOF
printf "it.skipIf(ci)('slow', () => {})\n" > tests/edge.spec.ts
printf 'trackError(e)\nif (myFlag("x")) {}\n' > app/custom.ts
for i in $(seq 1 20); do echo "// @ts-ignore line $i"; done > app/escapes.ts
mkdir -p "app/my dir" && printf 'export const y = 2\n' > "app/my dir/file one.ts"
git add -A && git commit -qm edges

out="$(PR_BASE=main bash "$FACTS" edges)"
# Exactly these two: not app/author.ts, not app/controller.ts.
grep -qxF -- '- **auth and access**: `app/composables/useAuth.ts`, `app/services/AuthService.ts`' <<<"$out" \
  || fail "auth line should list exactly useAuth.ts and AuthService.ts: $(grep 'auth and access' <<<"$out")"
hasnt "$out" '**infra and CI**'
hasnt "$out" 'datadog.ts:+'
has "$out" 'app/load.ts:+  } catch (e) {'
has "$out" 'app/load.ts:+  } catch {'
has "$out" 'app/load.ts:+  promise.catch(noop)'
has "$out" "tests/edge.spec.ts:+it.skipIf(ci)('slow', () => {})"
has "$out" '... and 5 more'
has "$out" '`app/my dir/file one.ts`'
# The catch that reports to Sentry is not quiet.
[ "$(grep -c 'app/load.ts:+  } catch' <<<"$out")" = 2 ] || fail "the reporting catch must not be listed as quiet"

out="$(PR_BASE=main PR_RISK_REPORTING='trackError' PR_RISK_FLAGS='myFlag' bash "$FACTS" edges)"
has "$out" 'app/custom.ts:+trackError(e)'
has "$out" 'app/custom.ts:+if (myFlag("x")) {}'

out="$(PR_BASE=main PR_RISK_EXCLUDE=$'app/load\\.ts\napp/escapes' bash "$FACTS" edges)"
has "$out" '- Code signals exclude: app/load\.ts, app/escapes'
hasnt "$out" 'app/load.ts:+'
hasnt "$out" '@ts-ignore'
has "$out" "tests/edge.spec.ts:+it.skipIf"
out="$(PR_BASE=main PR_RISK_EXCLUDE='tests/' bash "$FACTS" edges)"
hasnt "$out" 'tests/edge.spec.ts:+'

# Prose is never a signal; non-ASCII paths keep their own lines.
git checkout -q -b prose main
printf 'Call Sentry.captureException and useFeature in docs.\n' > notes.md
printf 'export const b = 2\n' > app/b.ts
printf 'try { a() } catch (e) {}\n' > "app/Ünï.ts"
git add -A && git commit -qm prose
out="$(PR_BASE=main bash "$FACTS" prose)"
hasnt "$out" 'notes.md:+'
has "$out" 'app/Ünï.ts:+try { a() } catch (e) {}'
hasnt "$out" 'app/b.ts:+try'

# --- review findings on PR 2: labels with |, "-- a/" lines, paths with ":" ----
git checkout -q -b parsing main
mkdir -p .claude-plugin db app/fixtures
printf '{}\n' > .claude-plugin/plugin.json
printf -- '-- a/notes: legacy\nSELECT 1;\n' > db/q.sql
git add -A && git commit -qm parsing-base
git checkout -q -b parsing-change
printf 'DELETE FROM users;\nSELECT 1;\n' > db/q.sql
printf 'try { a() } catch (e) {}\n' > "app/a:b.ts"
printf 'try { a() } catch (e) {}\n' > app/fixtures/f.ts
printf '{ "v": 2 }\n' > .claude-plugin/plugin.json
git add -A && git commit -qm parsing-change
out="$(PR_BASE=parsing PR_RISK_SENSITIVE='(^|/)\.claude-plugin/' bash "$FACTS" parsing-change)"
grep -qxF -- '- **project-sensitive `(^|/)\.claude-plugin/`**: `.claude-plugin/plugin.json`' <<<"$out" \
  || fail "a pattern with | must keep its whole label: $(grep project-sensitive <<<"$out")"
has "$out" 'db/q.sql:+DELETE FROM users;'
has "$out" 'app/a:b.ts:+try { a() } catch (e) {}'
out="$(PR_BASE=parsing PR_RISK_EXCLUDE='app/fixtures/' bash "$FACTS" parsing-change)"
hasnt "$out" 'app/fixtures/f.ts:+'
out="$(PR_BASE=parsing PR_RISK_EXCLUDE='fixtures/' bash "$FACTS" parsing-change)"
has "$out" 'app/fixtures/f.ts:+'   # anchored at the repo root, as documented

# --- other stacks: each pattern catches one line and leaves its near miss ------
git checkout -q -b stacks-base main
mkdir -p svc/pkg py app spec scripts rs
printf 'package pkg\nfunc TestOld(t *testing.T) {}\n' > svc/pkg/old_test.go
printf 'def test_old():\n    assert True\n' > app/test_old.py
git add -A && git commit -qm stacks-base
git checkout -q -b stacks
git rm -q svc/pkg/old_test.go app/test_old.py
mkdir -p svc/pkg
cat > py/a.py <<'EOF'
x = f()  # type: ignore
# the type is ignored here
import os  # noqa
noqa_count = 1
# pylint: disable=invalid-name
# pylint is disabled in CI
try:
    a()
except ValueError: pass
try:
    b()
except ValueError: return None
try:
    c()
except KeyError:
    pass
try:
    d()
except IndexError:
    log.warning(e)
@pytest.mark.skip(reason="slow")
@pytest.mark.skipif(sys.platform == "win32", reason="posix")
@pytest.mark.parametrize("a", [1])
EOF
cat > svc/pkg/b.go <<'EOF'
x := f() //nolint
// nolinter is a name
if err != nil {}
if err != nil { return err }
if err2 := g(); err2 != nil {
	return err2
}
if err != nil {
}
if err != nil {
	return err
}
func TestB(t *testing.T) { t.Skip("flaky") }
func TestC(t *testing.T) { if t.Skipped() { return } }
EOF
cat > rs/lib.rs <<'EOF'
#[allow(dead_code)]
#[derive(Debug)]
EOF
cat > app/A.java <<'EOF'
@SuppressWarnings("unchecked")
@Override
EOF
cat > scripts/run.sh <<'EOF'
# shellcheck disable=SC2086
# shellcheck source=lib.sh
EOF
cat > app/b.rb <<'EOF'
foo # rubocop:disable Style/X
# rubocop config lives in .rubocop.yml
skip_validation = true
EOF
cat > spec/c_spec.rb <<'EOF'
xit "does a thing" do
  skip "pending upstream"
  skip_count = 1
EOF
cat > app/d.ts <<'EOF'
// @ts-nocheck
// ts-nocheck is not used
xit('a', () => {})
xdescribe('b', () => {})
process.exit(1)
EOF
mkdir -p tools
printf '[project]\nname = "x"\n' > pyproject.toml
printf 'h1\n' > svc/go.sum
printf 'GEM\n' > tools/Gemfile.lock
printf 'notes\n' > py/requirements-notes.md
git add -A && git commit -qm stacks
out="$(PR_BASE=stacks-base bash "$FACTS" stacks)"
for line in 'py/a.py:+x = f()  # type: ignore' 'py/a.py:+import os  # noqa' 'py/a.py:+# pylint: disable=invalid-name' \
  'svc/pkg/b.go:+x := f() //nolint' 'rs/lib.rs:+#[allow(dead_code)]' 'app/A.java:+@SuppressWarnings("unchecked")' \
  'scripts/run.sh:+# shellcheck disable=SC2086' 'app/b.rb:+foo # rubocop:disable Style/X' 'app/d.ts:+// @ts-nocheck' \
  'py/a.py:+except ValueError: pass' 'py/a.py:+except KeyError:' 'svc/pkg/b.go:+if err != nil {}' \
  '@pytest.mark.skip(reason="slow")' '@pytest.mark.skipif(sys.platform' 't.Skip("flaky")' \
  "app/d.ts:+xit('a', () => {})" "app/d.ts:+xdescribe('b'" 'spec/c_spec.rb:+xit "does a thing" do' \
  'spec/c_spec.rb:+  skip "pending upstream"' 'svc/pkg/old_test.go:-func TestOld' 'app/test_old.py:-def test_old' \
  '`svc/pkg/old_test.go`' '`app/test_old.py`'; do
  has "$out" "$line"
done
for line in 'the type is ignored' 'noqa_count' 'pylint is disabled' 'nolinter' 'return None' 'except IndexError' \
  'if err != nil { return err }' 'err2 := g()' '#[derive' '@Override' 'shellcheck source' 'rubocop config' \
  'skip_validation' 'skip_count' 'ts-nocheck is not used' 'process.exit' 'parametrize' 't.Skipped'; do
  hasnt "$out" "$line"
done
# Only the handler whose body is just "}" is quiet, not the one that returns.
[ "$(grep -c 'svc/pkg/b.go:+if err != nil {$' <<<"$out")" = 1 ] || fail "only the empty Go handler is swallowed"
grep -qxF -- '- **dependencies**: `pyproject.toml`, `svc/go.sum`, `tools/Gemfile.lock`' <<<"$out" \
  || fail "dependencies: $(grep dependencies <<<"$out")"
has "$out" '- 3 of 14 changed files are tests'

# --- overlay-env.sh: the repo's overlay and the template load as documented ---
ENV="$ROOT/plugins/aisoul/scripts/pr/overlay-env.sh"
out="$(bash "$ENV" "$ROOT/.claude/aisoul/pr-risk.md")"
has "$out" "export PR_BASE='origin/main'"
has "$out" "export PR_RISK_EXCLUDE='plugins/aisoul/scripts/"
out="$(bash "$ENV" "$ROOT/plugins/aisoul/skills/pr-risk/overlay-template.md")"
has "$out" "export PR_RISK_REPORTING='useErrorReporter|trackError'"
( eval "$out"; [ "$(printf '%s\n' "$PR_RISK_SENSITIVE" | wc -l)" = 3 ] ) || fail "sensitive paths must stay one per line"
[ -z "$(bash "$ENV" /nonexistent.md)" ] || fail "a missing overlay must print nothing"

# --- risk-check.sh: the skill's own example passes, broken ones fail ----------
CHECK="$ROOT/plugins/aisoul/scripts/pr/risk-check.sh"
awk '/^```markdown$/ { i = 1; next } i && /^```$/ { exit } i' "$ROOT/plugins/aisoul/skills/pr-risk/SKILL.md" > risk-example.md
[ -s risk-example.md ] || fail "could not extract the example from pr-risk SKILL.md"
bash "$CHECK" risk-example.md >/dev/null || fail "the skill's own example fails risk-check.sh"

{
  echo '**Merge risk: medium**: no rule given'
  echo
  echo '**Blast radius** 👀'
  echo '- touches #12'
  echo '**Scope fit** ✅'
  echo '**Verification**'
  echo '**Reversibility** ✅'
} > risk-bad.md
if out="$(bash "$CHECK" risk-bad.md)"; then fail "risk-bad.md should fail"; fi
has "$out" "FAIL  first line must be"
has "$out" "FAIL  dimension out of order: Blast radius"
has "$out" "FAIL  no '- Lower it:' bullet under: Blast radius"
has "$out" "FAIL  no verdict on: Verification"
has "$out" "FAIL  expected 5 dimensions, found 4"
has "$out" "FAIL  no **Not assessed:** line"
has "$out" "FAIL  bare #<number>"

sed '1s/(rule 5)$/as rule 5 says/' risk-example.md > risk-noparen.md
if bash "$CHECK" risk-noparen.md >/dev/null; then fail "a headline without (rule N) must fail"; fi

echo "pr-risk: OK"
