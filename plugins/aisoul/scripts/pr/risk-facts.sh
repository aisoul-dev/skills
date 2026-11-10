#!/usr/bin/env bash
# Mechanical facts for a merge-risk assessment. Prints markdown; judges nothing.
#
#   risk-facts.sh                 # current branch against the base
#   risk-facts.sh <branch|sha>    # a branch or head commit against the base
#   risk-facts.sh --squash <sha>  # a squash or merge commit against its first parent
#
# For a merged PR, either pass the PR's base: PR_BASE=<base sha> risk-facts.sh <head sha>,
# or the merge commit: risk-facts.sh --squash <merge sha>.
#
# Env:
#   PR_BASE             base ref (default: origin/HEAD, else origin/main, else main)
#   PR_RISK_SENSITIVE   extra path regexes (ERE, one per line, matched anywhere
#                       in the path) marked sensitive
#   PR_RISK_EXCLUDE     path regexes (ERE, one per line, anchored at the repo
#                       root) left out of every signal, e.g. test fixtures. Markdown and plain-text
#                       files are always left out of the signals: they are prose.
#   PR_RISK_REPORTING   extra error-reporting call names, '|'-separated (ERE)
#   PR_RISK_FLAGS       extra feature-flag call names, '|'-separated (ERE)
#   PR_RISK_MAX         lines shown per signal before "and N more" (default 15)
#
# Exit: 0 with facts, 2 when the range is empty (the message says what to pass).
set -euo pipefail

# shellcheck source=SCRIPTDIR/lib.sh
source "$(dirname "$0")/lib.sh"
require_repo pr-risk-facts
T=$'\t'

MAX="${PR_RISK_MAX:-15}"

if [ "${1:-}" = "--squash" ]; then
  sha="${2:?usage: risk-facts.sh --squash <sha>}"
  range=("$sha^1" "$sha")
  parents="$(git rev-list --parents -n 1 "$sha" | wc -w)"
  kind="commit"; [ "$parents" -gt 2 ] && kind="merge commit"
  label="$kind $(git rev-parse --short "$sha") against its first parent"
else
  resolve_base
  branch="${1:-HEAD}"
  mb="$(git merge-base "$BASE" "$branch")"
  range=("$mb" "$branch")
  label="$branch against $BASE at $(git rev-parse --short "$mb")$BASE_NOTE"
fi

# --- sensitive path categories (case-insensitive ERE on the path) -------------
# A name counts at a path-segment start, after a separator or after "use"
# (useAuth, use-permissions), and must end at a separator or a capital
# (AuthService), so "controller" does not match "role" and "author" not "auth".
# These two categories are matched case-sensitively for that reason.
B='(^|/|[._-]|[Uu]se)'
E='([./_A-Z-]|$)'
CATEGORIES=(
  "auth and access${T}${B}([aA]uth|[lL]ogin|[lL]ogout|[sS]essions?|[tT]okens?|[oO]auth|[sS]so|[pP]ermissions?|[rR]oles?|[aA]cl|[pP]olic(y|ies)|[gG]uards?)${E}"
  "money${T}${B}([bB]illing|[pP]ayments?|[cC]heckout|[iI]nvoices?|[sS]ubscriptions?|[pP]ricing|[sS]tripe|[pP]addle|[wW]allet)${E}"
  "secrets and security config${T}(^|/)\.env|secret|credential|${B}(csp|security|cors)([./_-]|\$)|(^|/)(nuxt|vite|next|webpack)\.config\."
  "data and schema${T}(^|/)(migrations?|schema|seeds?)([./_-]|\$)|\.sql\$|(^|/)prisma/|(^|/)drizzle/"
  "infra and CI${T}(^|/)\.github/workflows/|\.gitlab-ci\.ya?ml\$|(^|/)(k8s|helm|terraform|infra|deploy|nginx|caddy)(/|\$)|Dockerfile|docker-compose|(^|/)compose\.ya?ml\$"
  "dependencies${T}(^|/)(package\.json|pyproject\.toml|Pipfile|go\.mod|Cargo\.toml|Gemfile|composer\.json|[^/]*requirements[^/]*\.txt)\$|$(lockfiles_re)"
)
# Framework config files beyond the few above belong in the overlay's
# Sensitive paths (PR_RISK_SENSITIVE), not in this list.
if [ -n "${PR_RISK_SENSITIVE:-}" ]; then
  while IFS= read -r re; do
    [ -n "$re" ] && CATEGORIES+=("project-sensitive \`$re\`${T}$re")
  done <<<"$PR_RISK_SENSITIVE"
fi

REPORTING='Sentry\.|captureException|captureMessage|reportError|logger\.(error|fatal)|posthog\.capture|datadog|bugsnag|rollbar'
[ -n "${PR_RISK_REPORTING:-}" ] && REPORTING="$REPORTING|$PR_RISK_REPORTING"
FLAGS='feature[_-]?flag|featureFlag|isFeatureEnabled|isEnabled\(|useFeature|useFlag|getFlag|unleash|launchdarkly|growthbook'
[ -n "${PR_RISK_FLAGS:-}" ] && FLAGS="$FLAGS|$PR_RISK_FLAGS"

# Test files in the languages the signals know: JS/TS, Go, Python, Ruby.
TEST_PATHS='\.(spec|test)\.|(^|/)(tests?|__tests__|e2e|spec)/|_test\.(go|py)$|_spec\.rb$|(^|/)test_[^/]*\.py$'

# core.quotePath=false keeps non-ASCII paths readable instead of quoted and escaped.
gd() { git -c core.quotePath=false diff "$@"; }
files="$(gd --name-status "${range[@]}")"
diff0="$(gd -U0 "${range[@]}")"
stat="$(gd --shortstat "${range[@]}")"

echo "# Merge-risk facts"
echo
echo "- Range: $label"
if [ -z "$stat" ]; then
  echo "- Diff: **empty**. $(empty_range_hint)"
  exit 2
fi
echo "- Diff: ${stat# }"
[ -n "${PR_RISK_EXCLUDE:-}" ] && echo "- Code signals exclude: $(grep -v '^$' <<<"$PR_RISK_EXCLUDE" | paste -sd, - | sed 's/,/, /g')"
echo

# Path of each changed file: the last tab-separated field (new path for renames).
paths="$(awk -F'\t' 'NF { print $NF }' <<<"$files")"

# Added and removed lines, each prefixed with its file and a tab, which a path
# from git cannot contain: "path<TAB>+text" / "path<TAB>-text". File headers are
# read only between "diff --git" and the first "@@", so a changed line whose text
# starts with "-- a/" or "++ b/" is never taken for one.
lines="$(awk '
  /^diff --git / { hdr = 1; next }
  hdr && /^--- (a\/|\/dev\/null)/ { if ($2 != "/dev/null") { f = substr($0, 7); sub(/\t$/, "", f) }; next }
  hdr && /^\+\+\+ (b\/|\/dev\/null)/ { if ($2 != "/dev/null") { f = substr($0, 7); sub(/\t$/, "", f) }; next }
  /^@@/ { hdr = 0; next }
  hdr { next }
  /^\+/ { print f "\t" $0; next }
  /^-/ { print f "\t" $0 }
' <<<"$diff0")"

# Signals read code only: prose files and paths matching PR_RISK_EXCLUDE are left out.
excl="$(grep -v '^$' <<<"${PR_RISK_EXCLUDE:-}" | paste -sd'|' - || true)"
# Patterns go through ENVIRON, not -v, which would eat their backslashes.
code_lines="$(EXCL_RE="$excl" awk 'BEGIN { ex = ENVIRON["EXCL_RE"] } {
  p = $0; sub(/\t.*/, "", p)
  if (p ~ /\.(md|mdx|markdown|txt|rst)$/ || (ex != "" && p ~ ("^(" ex ")"))) next
  print
}' <<<"$lines")"
added="$(grep -E "^[^$T]+$T\\+" <<<"$code_lines" || true)"
removed="$(grep -E "^[^$T]+$T-" <<<"$code_lines" || true)"

# Matching lines, capped at MAX with a count of the rest. The pattern applies to
# the line text only, never to the path in front of it.
hits() {
  local re="$1" input="$2" found n
  found="$(grep -E "^[^$T]+${T}[-+].*($re)" <<<"$input" || true)"
  [ -n "$found" ] || return 0
  n="$(wc -l <<<"$found" | tr -d ' ')"
  head -n "$MAX" <<<"$found"
  if [ "$n" -gt "$MAX" ]; then echo "... and $((n - MAX)) more"; fi
  return 0
}

# catch blocks whose body, within the next 4 added lines of the same file,
# only logs or is empty or a comment, with no rethrow and no reporting.
quiet_catches() {
  REP_RE="$REPORTING" awk '
    BEGIN { rep = ENVIRON["REP_RE"] }
    function flush() {
      if (open && !loud && (logs || empty)) print first
      open = 0
    }
    {
      p = $0; sub(/\t.*/, "", p); t = $0; sub(/^[^\t]+\t\+/, "", t)
      if (open) {
        if (p != file || ++n > 4) flush()
        else {
          if (t ~ /throw|reject\(/ || t ~ rep) loud = 1
          if (t ~ /console\.(log|warn|error|info)/) logs = 1
          if (t ~ /^[[:space:]]*\}/) { if (n == 1 || commented) empty = 1; flush(); next }
          if (t ~ /^[[:space:]]*(\/\/|\/\*|\*)/) commented = 1
          next
        }
      }
      if (t ~ /catch[[:space:]]*(\([^)]*\))?[[:space:]]*\{[[:space:]]*$/) {
        open = 1; first = $0; file = p; n = 0; loud = 0; logs = 0; empty = 0; commented = 0
      }
    }
    END { flush() }
  ' <<<"$1"
}

# Handlers whose whole body is the next added line of the same file:
# Python "except ...:" followed by "pass", Go "if err != nil {" followed by "}".
# The one-line forms are matched by the swallowed-errors pattern itself.
empty_handlers() {
  awk '
    {
      p = $0; sub(/\t.*/, "", p); t = $0; sub(/^[^\t]+\t\+/, "", t)
      if (want != "" && p == file && t ~ want) print first
      want = ""
      if (p ~ /\.py$/ && t ~ /^[[:space:]]*except([[:space:]][^:]*)?:[[:space:]]*(#.*)?$/) { want = "^[[:space:]]*pass[[:space:]]*(#.*)?$"; first = $0; file = p }
      else if (p ~ /\.go$/ && t ~ /if[[:space:]]+err[[:space:]]*!=[[:space:]]*nil[[:space:]]*\{[[:space:]]*$/) { want = "^[[:space:]]*\\}"; first = $0; file = p }
    }
  ' <<<"$1"
}

echo "## Changed files"
echo
awk -F'\t' 'NF { printf "- %s `%s`\n", substr($1, 1, 1), $NF }' <<<"$files"
echo

echo "## Sensitive paths"
echo
any=0
for c in "${CATEGORIES[@]}"; do
  name="${c%%"$T"*}"
  re="${c#*"$T"}"
  case "$name" in
    "auth and access"|money) matched="$(grep -E "$re" <<<"$paths" || true)" ;;
    *) matched="$(grep -iE "$re" <<<"$paths" || true)" ;;
  esac
  if [ -n "$matched" ]; then
    any=1
    echo "- **$name**: $(awk -v q='`' '{ printf "%s%s%s%s", (NR > 1 ? ", " : ""), q, $0, q }' <<<"$matched")"
  fi
done
[ "$any" = 1 ] || echo "- none matched"
echo

echo "## Signals in changed lines"
echo
signals=0
section() {
  local title="$1" body="$2"
  if [ -n "$body" ]; then
    signals=1
    echo "**$title**"
    echo
    echo '```text'
    tr '\t' ':' <<<"$body"
    echo '```'
    echo
  fi
}
section "Added swallowed errors" "$( { hits 'catch[[:space:]]*(\([^)]*\))?[[:space:]]*\{[[:space:]]*\}|\.catch\((\([^)]*\)[[:space:]]*=>[[:space:]]*(\{[[:space:]]*\}|null|undefined|void 0)|noop|_\.noop)\)|\bexcept([[:space:]][^:]*)?:[[:space:]]*pass[[:space:]]*(#.*)?$|if[[:space:]]+err[[:space:]]*!=[[:space:]]*nil[[:space:]]*\{[[:space:]]*\}' "$added"; empty_handlers "$added"; } | head -n "$MAX")"
section "Added catch blocks that only log, or are empty or a comment" "$(quiet_catches "$added" | head -n "$MAX")"
section "Removed error reporting" "$(hits "$REPORTING" "$removed")"
section "Added error reporting" "$(hits "$REPORTING" "$added")"
ESCAPES='@ts-ignore|@ts-expect-error|@ts-nocheck|as any\b|eslint-disable|#[[:space:]]*type:[[:space:]]*ignore|#[[:space:]]*noqa\b|#[[:space:]]*pylint:[[:space:]]*disable|//[[:space:]]*nolint\b|#!?\[allow\(|@SuppressWarnings|#[[:space:]]*shellcheck[[:space:]]+disable|rubocop:disable'
section "Added type or lint escapes" "$(hits "$ESCAPES" "$added")"
section "Destructive data operations" "$(hits 'DROP[[:space:]]+(TABLE|COLUMN|INDEX)|ALTER[[:space:]]+TABLE.*DROP|TRUNCATE|DELETE[[:space:]]+FROM|dropTable|dropColumn|removeColumn' "$added")"
section "Feature flags" "$(hits "$FLAGS" "$code_lines")"
# Skipped: Jest/Vitest/Mocha (it.skip, xit), pytest (mark.skip, skipif, pytest.skip),
# Go (t.Skip), RSpec (xit, xdescribe, a bare skip in a _spec.rb file).
SKIPPED='\b(it|test|describe)\.(skip|skipIf|todo|only|fails)\b|\b(xit|xtest|xdescribe|xcontext|xspecify)\b[[:space:]]*[('"'"'"]|@pytest\.mark\.(skip|skipif|xfail)\b|\bpytest\.skip\(|\bt\.Skip(f|Now)?\('
section "Skipped or removed tests" "$( { grep -E "^[^$T]+$T\\+.*($SKIPPED)" <<<"$code_lines" || true; grep -E "^[^$T]*_spec\\.rb$T\\+[[:space:]]*skip\\b" <<<"$code_lines" || true; grep -E "^[^$T]*(\\.(spec|test)\\.[cm]?[jt]sx?|_test\\.go|_spec\\.rb|_test\\.py|/test_[^/]*\\.py|^test_[^/]*\\.py)$T-.*(\\b(it|test)\\(|func Test|def test_)" <<<"$code_lines" || true; } | head -n "$MAX")"

deleted_tests="$(awk -F'\t' '$1 == "D" { print $NF }' <<<"$files" | grep -E "$TEST_PATHS" || true)"
section "Deleted test files" "$deleted_tests"
[ "$signals" = 1 ] || { echo "- none found"; echo; }

changed_tests="$(grep -cE "$TEST_PATHS" <<<"$paths" || true)"
changed_total="$(wc -l <<<"$paths" | tr -d ' ')"
echo "## Test files"
echo
echo "- $changed_tests of $changed_total changed files are tests"
