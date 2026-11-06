#!/usr/bin/env bash
# Tests for scripts/pr: size.sh shapes and check.sh rules, plus the skill's own
# example, which must pass the checks it tells others to run.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$ROOT/plugins/aisoul/scripts/pr"
SKILL="$ROOT/plugins/aisoul/skills/pr-describe/SKILL.md"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# --- size.sh -----------------------------------------------------------------
cd "$WORK"
git init -q -b main
git config user.email pr@example.com
git config user.name pr
mkdir -p src docs
printf 'a\n' > src/a.ts && git add -A && git commit -qm base

git checkout -q -b small
printf 'b\nc\n' >> src/a.ts
seq 1 500 > docs/notes.md            # excluded: must not push it into large
seq 1 300 > pnpm-lock.yaml           # excluded lockfile
git add -A && git commit -qm small

out="$(PR_BASE=main bash "$SCRIPTS/size.sh" small)"
echo "$out"
grep -q '2 changed lines' <<<"$out" || fail "small branch should count 2 lines"
grep -q 'shape: small' <<<"$out"    || fail "small branch should be small"

git checkout -q -b large main
seq 1 80 > src/big.ts && git add -A && git commit -qm large
out="$(PR_BASE=main bash "$SCRIPTS/size.sh" large)"
grep -q 'shape: large' <<<"$out" || fail "80 lines should be large"

out="$(PR_BASE=main PR_EXCLUDE="src/big.ts" bash "$SCRIPTS/size.sh" large)"
grep -q 'shape: small' <<<"$out" || fail "PR_EXCLUDE should remove src/big.ts"

out="$(bash "$SCRIPTS/size.sh" --squash "$(git rev-parse large)")"
grep -q '80 changed lines' <<<"$out" || fail "squash mode should count 80 lines: $out"

# --- check.sh: the skill's example passes ------------------------------------
awk '/^```markdown$/ { inside = 1; next } inside && /^```$/ { exit } inside' "$SKILL" > example.md
[ -s example.md ] || fail "could not extract the example from SKILL.md"
bash "$SCRIPTS/check.sh" example.md small || fail "the skill's own example fails check.sh"

# --- check.sh: each rule fires -----------------------------------------------
cat > bad.md <<'EOF'
# [X-1] Bad

## What

Fixed the crash from #13 and mentioned `Test #14` in code, which is fine.
EOF
printf 'A dash \xe2\x80\x94 here.\n' >> bad.md

if out="$(bash "$SCRIPTS/check.sh" bad.md small)"; then fail "bad.md should fail"; fi
echo "$out"
grep -q 'FAIL  no \*\*Not checked:\*\* line' <<<"$out" || fail "missing Not checked not reported"
grep -q 'FAIL  small description has ## headings' <<<"$out" || fail "headings not reported"
grep -q 'FAIL  bare #<number>' <<<"$out" || fail "bare #13 not reported"
grep -q 'Test #14' <<<"$out" && fail "#14 inside backticks must not be reported"
grep -q 'FAIL  em dash' <<<"$out" || fail "em dash not reported"

{ echo '# T'; for _ in $(seq 1 40); do echo 'one two three four five'; done; echo '**Not checked:** x'; } > long.md
if bash "$SCRIPTS/check.sh" long.md small >/dev/null; then fail "200 words should exceed the small budget"; fi
bash "$SCRIPTS/check.sh" long.md large >/dev/null || fail "200 words should fit the large budget"

{ echo '# T'; echo '<details><summary>Proof</summary>'; echo;
  for _ in $(seq 1 100); do echo 'one two three four five'; done
  echo '</details>'; echo '**Not checked:** x'; } > details.md
bash "$SCRIPTS/check.sh" details.md small >/dev/null || fail "words inside <details> must not count"

echo "pr: OK"
