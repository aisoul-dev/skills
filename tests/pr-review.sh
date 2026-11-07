#!/usr/bin/env bash
# shellcheck disable=SC2016  # backticks in expected output are literal
# Tests for the pr-review scripts: scope.sh, stacked.sh, ratchet.sh,
# changed-expects.sh, comment-link.sh, on a repo with a bare "origin".
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$ROOT/plugins/aisoul/scripts/pr"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
has() { grep -qF -- "$2" <<<"$1" || fail "expected: $2"$'\n'"in: $1"; }
hasnt() { grep -qF -- "$2" <<<"$1" && fail "unexpected: $2"; true; }

git init -q --bare -b main "$WORK/origin.git"
git clone -q "$WORK/origin.git" "$WORK/repo" 2>/dev/null
cd "$WORK/repo"
git config user.email review@example.com
git config user.name review
git remote set-url origin git@github-alias:acme/shop.git      # an SSH alias, as in real setups
git config "url.$WORK/origin.git.insteadOf" git@github-alias:acme/shop.git

mkdir -p app tests docs
seq 1 12 | sed 's/^/export const v/; s/$/ = 0/' > app/a.ts
printf "it('adds', () => { expect(add(1, 1)).toBe(2) })\n" > tests/add.spec.ts
printf '# Notes\n\nline 3\n' > docs/notes.md
printf 'export const untouched = 1\n' > app/untouched.ts
git add -A && git commit -qm base && git push -q origin main
git remote set-head origin main >/dev/null

# --- feature branch: changes a line, adds any, bends a test --------------------
git checkout -q -b feat
seq 1 12 | sed 's/^/export const v/; s/$/ = 0/; 2s/= 0/: any = 2/' > app/a.ts && echo 'export const v13 = 0' >> app/a.ts
printf "it('adds', () => { expect(add(1, 1)).toBe(3) })\n" > tests/add.spec.ts
printf '# Notes\n\nline 3 changed\n' > docs/notes.md
git add -A && git commit -qm feat && git push -q origin feat

# scope: up to date
out="$(PR_NO_FETCH=1 bash "$S/scope.sh" feat)"
has "$out" '- Ahead: 1 commits; behind: 0 commits'
has "$out" 'Merge with origin/main: clean'

# ratchet: one any added, none removed
out="$(bash "$S/ratchet.sh" '(:|<|,|\bas)\s*any\b' feat -- '*.ts' && echo exit0 || echo "exit$?")"
has "$out" 'added 1, removed 0, net 1'
has "$out" 'exit2'

# changed expectations
out="$(bash "$S/changed-expects.sh" feat)"
has "$out" "-it('adds', () => { expect(add(1, 1)).toBe(2) })"
has "$out" "+it('adds', () => { expect(add(1, 1)).toBe(3) })"

# changed-expects: shell checks in a root tests/ folder
git checkout -q -b shell-tests main
printf 'out="$(run)"\nhas "$out" "ok"\n[ -s f ] || fail "empty"\n' > tests/run.sh
git add -A && git commit -qm shell-base
git checkout -q -b shell-change
printf 'out="$(run)"\n' > tests/run.sh
git add -A && git commit -qm shell-change
out="$(PR_BASE=shell-tests bash "$S/changed-expects.sh" shell-change)"
has "$out" '-has "$out" "ok"'
has "$out" '-[ -s f ] || fail "empty"'
git checkout -q feat

# comment-link: SSH alias resolved, line in diff, outside diff, not in diff, Markdown
sha="$(git rev-parse origin/feat)"
out="$(bash "$S/comment-link.sh" app/a.ts 2 feat)"
has "$out" "https://github.com/acme/shop/blob/$sha/app/a.ts#L2"
has "$out" '**File:** `app/a.ts` · **Line:** 2'
out="$(bash "$S/comment-link.sh" app/a.ts 2 4 feat)"
has "$out" '#L2-L4'
has "$out" '**Lines:** 2–4'
out="$(bash "$S/comment-link.sh" app/a.ts 7 feat)"
has "$out" 'file-level comment (L7 is outside the diff)'
git checkout -q main && printf 'export const z = 0\n' > app/z.ts && git add -A && git commit -qm z && git push -q origin main
git checkout -q feat
out="$(bash "$S/comment-link.sh" app/untouched.ts 1 feat)"
has "$out" '**Where:** general PR comment (about `app/untouched.ts:1`)'
if bash "$S/comment-link.sh" app/a.ts 99 feat 2>/dev/null; then fail "a line past the end must fail"; fi
git checkout -q --detach feat
if bash "$S/comment-link.sh" app/a.ts 2 2>/dev/null; then fail "a detached HEAD without a branch must fail"; fi
git checkout -q feat
echo '// local edit' >> app/a.ts
out="$(bash "$S/comment-link.sh" app/a.ts 2 feat 2>&1 >/dev/null)"
has "$out" 'differs from the pushed version'
git checkout -q -- app/a.ts
out="$(bash "$S/comment-link.sh" docs/notes.md 3 feat)"
has "$out" "docs/notes.md?plain=1#L3"
git checkout -q -b local-only
if bash "$S/comment-link.sh" app/a.ts 2 local-only 2>/dev/null; then fail "an unpushed branch must fail"; fi

# scope: behind, clean merge
git checkout -q feat
out="$(PR_NO_FETCH=1 bash "$S/scope.sh" feat)"
has "$out" 'behind: 1 commits'
has "$out" 'Condition: update from origin/main before merging'

# scope: behind with conflicts exits 3 and names the file
git checkout -q main && sed -i '2s/.*/export const v2 = 100/' app/a.ts && git add -A && git commit -qm conflict && git push -q origin main
git checkout -q feat
set +e; out="$(PR_NO_FETCH=1 bash "$S/scope.sh" feat)"; code=$?; set -e
[ "$code" = 3 ] || fail "conflicts must exit 3, got $code"
has "$out" '**CONFLICTS**'
has "$out" '- `app/a.ts`'

# --- stacked: a branch built on feat ------------------------------------------
git checkout -q -b follow feat
printf 'export const fixed = true\n' > app/fix.ts
git add -A && git commit -qm follow && git push -q origin follow
git checkout -q feat
out="$(bash "$S/stacked.sh" feat -- app/a.ts)"
has "$out" '- No changes to: app/a.ts'
out="$(bash "$S/stacked.sh" feat -- app/fix.ts)"
has "$out" '## `origin/follow`'
has "$out" '1 file changed, 1 insertion(+)'
has "$out" 'Merge with feat: clean'
has "$out" '+export const fixed = true'
hasnt "$out" '## `origin/feat`'

git checkout -q main
out="$(PR_BASE=origin/main bash "$S/stacked.sh" origin/follow)"
has "$out" '- none'

echo "pr-review: OK"
