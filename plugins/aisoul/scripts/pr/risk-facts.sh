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
#   PR_BASE             base ref (default: origin/HEAD, else main)
#   PR_RISK_SENSITIVE   extra path regexes (ERE, one per line) marked sensitive
#   PR_RISK_EXCLUDE     path regexes (ERE, one per line) left out of the code
#                       signals, e.g. test fixtures; test sections still see them
#   PR_RISK_REPORTING   extra error-reporting call names, '|'-separated (ERE)
#   PR_RISK_FLAGS       extra feature-flag call names, '|'-separated (ERE)
#   PR_RISK_MAX         lines shown per signal before "and N more" (default 15)
set -euo pipefail

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "pr-risk-facts: run this from inside a git repository" >&2
  exit 1
}

MAX="${PR_RISK_MAX:-15}"

if [ "${1:-}" = "--squash" ]; then
  sha="${2:?usage: risk-facts.sh --squash <sha>}"
  range=("$sha^1" "$sha")
  parents="$(git rev-list --parents -n 1 "$sha" | wc -w)"
  kind="commit"; [ "$parents" -gt 2 ] && kind="merge commit"
  label="$kind $(git rev-parse --short "$sha") against its first parent"
else
  base="${PR_BASE:-}"
  note=""
  if [ -z "$base" ]; then
    base="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
    [ -n "$base" ] || { base=main; note=" (origin/HEAD not set, fell back to main)"; }
  fi
  branch="${1:-HEAD}"
  mb="$(git merge-base "$base" "$branch")"
  range=("$mb" "$branch")
  label="$branch against $base at $(git rev-parse --short "$mb")$note"
fi

# --- sensitive path categories (case-insensitive ERE on the path) -------------
# A name counts at a path-segment start, after a separator or after "use"
# (useAuth, use-permissions), and must end at a separator or a capital
# (AuthService), so "controller" does not match "role" and "author" not "auth".
# These two categories are matched case-sensitively for that reason.
B='(^|/|[._-]|[Uu]se)'
E='([./_A-Z-]|$)'
CATEGORIES=(
  "auth and access|${B}([aA]uth|[lL]ogin|[lL]ogout|[sS]essions?|[tT]okens?|[oO]auth|[sS]so|[pP]ermissions?|[rR]oles?|[aA]cl|[pP]olic(y|ies)|[gG]uards?)${E}"
  "money|${B}([bB]illing|[pP]ayments?|[cC]heckout|[iI]nvoices?|[sS]ubscriptions?|[pP]ricing|[sS]tripe|[pP]addle|[wW]allet)${E}"
  "secrets and security config|(^|/)\.env|secret|credential|${B}(csp|security|cors)([./_-]|\$)|(^|/)(nuxt|vite|next|webpack)\.config\."
  "data and schema|(^|/)(migrations?|schema|seeds?)([./_-]|\$)|\.sql\$|(^|/)prisma/|(^|/)drizzle/"
  "infra and CI|(^|/)\.github/workflows/|\.gitlab-ci\.ya?ml\$|(^|/)(k8s|helm|terraform|infra|deploy|nginx|caddy)(/|\$)|Dockerfile|docker-compose|(^|/)compose\.ya?ml\$"
  "dependencies|(^|/)package\.json\$|pnpm-lock\.yaml\$|package-lock\.json\$|yarn\.lock\$|bun\.lockb?\$|requirements\.txt\$|go\.(mod|sum)\$|Cargo\.(toml|lock)\$"
)
if [ -n "${PR_RISK_SENSITIVE:-}" ]; then
  while IFS= read -r re; do
    [ -n "$re" ] && CATEGORIES+=("project-sensitive|$re")
  done <<<"$PR_RISK_SENSITIVE"
fi

REPORTING='Sentry\.|captureException|captureMessage|reportError|logger\.(error|fatal)|posthog\.capture|datadog|bugsnag|rollbar'
[ -n "${PR_RISK_REPORTING:-}" ] && REPORTING="$REPORTING|$PR_RISK_REPORTING"
FLAGS='feature[_-]?flag|featureFlag|isFeatureEnabled|isEnabled\(|useFeature|useFlag|getFlag|unleash|launchdarkly|growthbook'
[ -n "${PR_RISK_FLAGS:-}" ] && FLAGS="$FLAGS|$PR_RISK_FLAGS"

files="$(git diff --name-status "${range[@]}")"
diff0="$(git diff -U0 "${range[@]}")"
stat="$(git diff --shortstat "${range[@]}")"

echo "# Merge-risk facts"
echo
echo "- Range: $label"
if [ -z "$stat" ]; then
  echo "- Diff: **empty**. If this PR is already merged, the base has moved past it: pass its base, \`PR_BASE=<base sha> risk-facts.sh <head sha>\`, or its merge commit, \`risk-facts.sh --squash <merge sha>\`."
  exit 0
fi
echo "- Diff: ${stat# }"
[ -n "${PR_RISK_EXCLUDE:-}" ] && echo "- Code signals exclude: $(grep -v '^$' <<<"$PR_RISK_EXCLUDE" | paste -sd, - | sed 's/,/, /g')"
echo

# Path of each changed file: the last tab-separated field (new path for renames).
paths="$(awk -F'\t' 'NF { print $NF }' <<<"$files")"

# Added and removed lines, each prefixed with its file: "path:+text" / "path:-text".
lines="$(awk '
  /^--- (a\/|\/dev\/null)/ { if ($2 != "/dev/null") { f = substr($0, 7); sub(/\t$/, "", f) }; next }
  /^\+\+\+ (b\/|\/dev\/null)/ { if ($2 != "/dev/null") { f = substr($0, 7); sub(/\t$/, "", f) }; next }
  /^\+/ { print f ":" $0; next }
  /^-/ { print f ":" $0 }
' <<<"$diff0")"

# Lines whose path matches PR_RISK_EXCLUDE are left out of the code signals.
code_lines="$lines"
if [ -n "${PR_RISK_EXCLUDE:-}" ]; then
  excl="$(grep -v '^$' <<<"$PR_RISK_EXCLUDE" | paste -sd'|' -)"
  code_lines="$(awk -v re="^($excl)" '{ p = $0; sub(/:[-+].*/, "", p); if (p !~ re) print }' <<<"$lines")"
fi
added="$(grep -E '^[^:]+:\+' <<<"$code_lines" || true)"
removed="$(grep -E '^[^:]+:-' <<<"$code_lines" || true)"

# Matching lines, capped at MAX with a count of the rest. The pattern applies to
# the line text only, never to the path in front of it.
hits() {
  local re="$1" input="$2" found n
  found="$(grep -E "^[^:]+:[-+].*($re)" <<<"$input" || true)"
  [ -n "$found" ] || return 0
  n="$(wc -l <<<"$found" | tr -d ' ')"
  head -n "$MAX" <<<"$found"
  if [ "$n" -gt "$MAX" ]; then echo "... and $((n - MAX)) more"; fi
  return 0
}

# catch blocks whose body, within the next 4 added lines of the same file,
# only logs or is empty or a comment, with no rethrow and no reporting.
quiet_catches() {
  awk -v rep="$REPORTING" '
    function flush() {
      if (open && !loud && (logs || empty)) print first
      open = 0
    }
    {
      p = $0; sub(/:[-+].*/, "", p); t = $0; sub(/^[^:]+:\+/, "", t)
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

echo "## Changed files"
echo
awk -F'\t' 'NF { printf "- %s `%s`\n", substr($1, 1, 1), $NF }' <<<"$files"
echo

echo "## Sensitive paths"
echo
any=0
for c in "${CATEGORIES[@]}"; do
  name="${c%%|*}"
  re="${c#*|}"
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
    echo "$body"
    echo '```'
    echo
  fi
}
section "Added swallowed errors" "$(hits 'catch[[:space:]]*(\([^)]*\))?[[:space:]]*\{[[:space:]]*\}|\.catch\((\([^)]*\)[[:space:]]*=>[[:space:]]*(\{[[:space:]]*\}|null|undefined|void 0)|noop|_\.noop)\)' "$added")"
section "Added catch blocks that only log, or are empty or a comment" "$(quiet_catches "$added" | head -n "$MAX")"
section "Removed error reporting" "$(hits "$REPORTING" "$removed")"
section "Added error reporting" "$(hits "$REPORTING" "$added")"
section "Added type or lint escapes" "$(hits '@ts-ignore|@ts-expect-error|as any\b|eslint-disable' "$added")"
section "Destructive data operations" "$(hits 'DROP[[:space:]]+(TABLE|COLUMN|INDEX)|ALTER[[:space:]]+TABLE.*DROP|TRUNCATE|DELETE[[:space:]]+FROM|dropTable|dropColumn|removeColumn' "$added")"
section "Feature flags" "$(hits "$FLAGS" "$code_lines")"
# Test sections see every changed line, excluded paths included.
section "Skipped or removed tests" "$( { grep -E '^[^:]+:\+.*\b(it|test|describe)\.(skip|skipIf|todo|only|fails)\b' <<<"$lines" || true; grep -E '^[^:]*(\.(spec|test)\.[cm]?[jt]sx?|_test\.go|_spec\.rb):-.*\b(it|test)\(' <<<"$lines" || true; } | head -n "$MAX")"

deleted_tests="$(awk -F'\t' '$1 == "D" { print $NF }' <<<"$files" | grep -E '\.(spec|test)\.|(^|/)(tests?|__tests__|e2e)/' || true)"
section "Deleted test files" "$deleted_tests"
[ "$signals" = 1 ] || { echo "- none found"; echo; }

changed_tests="$(grep -cE '\.(spec|test)\.|(^|/)(tests?|__tests__|e2e)/' <<<"$paths" || true)"
changed_total="$(wc -l <<<"$paths" | tr -d ' ')"
echo "## Test files"
echo
echo "- $changed_tests of $changed_total changed files are tests"
