#!/usr/bin/env bash
# Mechanical facts for a merge-risk assessment. Prints markdown; judges nothing.
#
#   risk-facts.sh                 # current branch against the base
#   risk-facts.sh <branch>        # a branch against the base
#   risk-facts.sh --squash <sha>  # one commit against its parent
#
# Env:
#   PR_BASE             base ref (default: origin/HEAD, else main)
#   PR_RISK_SENSITIVE   extra path regexes (ERE, one per line) marked sensitive
#   PR_RISK_REPORTING   extra error-reporting call names, '|'-separated (ERE)
#   PR_RISK_FLAGS       extra feature-flag call names, '|'-separated (ERE)
set -euo pipefail

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "pr-risk-facts: run this from inside a git repository" >&2
  exit 1
}

if [ "${1:-}" = "--squash" ]; then
  sha="${2:?usage: risk-facts.sh --squash <sha>}"
  range=("$sha^" "$sha")
  label="commit $sha against its parent"
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
CATEGORIES=(
  'auth and access|(^|/)(auth|login|logout|session|sessions|token|tokens|oauth|sso|permission|permissions|roles?|acl|polic(y|ies)|guard|guards)([./_-]|$)|middleware/.*(auth|role|permission)'
  'money|(^|/)(billing|payment|payments|checkout|invoice|invoices|subscription|subscriptions|pricing|stripe|paddle|wallet)([./_-]|$)'
  'secrets and security config|(^|/)\.env|secret|credential|(^|/)(csp|security|cors)([./_-]|$)|nuxt\.config\.|vite\.config\.|next\.config\.'
  'data and schema|(^|/)(migrations?|schema|seeds?)([./_-]|$)|\.sql$|prisma/|drizzle/'
  'infra and CI|(^|/)\.github/workflows/|(^|/)(docker|dockerfile|compose|k8s|helm|terraform|infra|deploy|nginx|caddy)|Dockerfile|docker-compose|\.ya?ml$'
  'dependencies|(^|/)package\.json$|pnpm-lock\.yaml$|package-lock\.json$|yarn\.lock$|bun\.lockb?$|requirements\.txt$|go\.(mod|sum)$|Cargo\.(toml|lock)$'
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

# Added and removed lines, each prefixed with its file: "path:+text" / "path:-text".
lines="$(awk '
  /^--- (a\/|\/dev\/null)/ { if ($2 != "/dev/null") f = substr($0, 7); next }
  /^\+\+\+ (b\/|\/dev\/null)/ { if ($2 != "/dev/null") f = substr($0, 7); next }
  /^\+/ { print f ":" $0; next }
  /^-/ { print f ":" $0 }
' <<<"$diff0")"
added="$(grep -E '^[^:]+:\+' <<<"$lines" || true)"
removed="$(grep -E '^[^:]+:-' <<<"$lines" || true)"

hits() { grep -E "$1" <<<"$2" | head -n "${3:-15}" | sed 's/^/    /' || true; }

echo "# Merge-risk facts"
echo
echo "- Range: $label"
echo "- Diff: ${stat# }"
echo

echo "## Changed files"
echo
awk '{ printf "- %s `%s`\n", $1, $NF }' <<<"$files"
echo

echo "## Sensitive paths"
echo
any=0
for c in "${CATEGORIES[@]}"; do
  name="${c%%|*}"
  re="${c#*|}"
  matched="$(awk '{ print $NF }' <<<"$files" | grep -iE "$re" || true)"
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
section "Added swallowed errors" "$(hits ':\+.*(catch[[:space:]]*(\([^)]*\))?[[:space:]]*\{[[:space:]]*\}|\.catch\(\([^)]*\)[[:space:]]*=>[[:space:]]*(\{[[:space:]]*\}|null|undefined|void 0)\))' "$added")"
section "Added catch blocks that only log" "$(hits ':\+.*catch.*console\.(log|warn|error)' "$added")"
section "Removed error reporting" "$(hits "$REPORTING" "$removed")"
section "Added error reporting" "$(hits "$REPORTING" "$added")"
section "Added type or lint escapes" "$(hits ':\+.*(@ts-ignore|@ts-expect-error|as any\b|eslint-disable)' "$added")"
section "Skipped or removed tests" "$(hits ':\+.*\b(it|test|describe)\.(skip|todo|only)\(|\.(spec|test)\.[jt]sx?:-.*\b(it|test)\(' "$lines")"
section "Destructive data operations" "$(hits ':\+.*(DROP[[:space:]]+(TABLE|COLUMN|INDEX)|ALTER[[:space:]]+TABLE.*DROP|TRUNCATE|DELETE[[:space:]]+FROM|dropTable|dropColumn|removeColumn)' "$added")"
section "Feature flags" "$(hits ":[-+].*($FLAGS)" "$lines")"

deleted_tests="$(awk '$1 == "D" { print $NF }' <<<"$files" | grep -E '\.(spec|test)\.|(^|/)(tests?|__tests__|e2e)/' || true)"
section "Deleted test files" "$deleted_tests"
[ "$signals" = 1 ] || { echo "- none found"; echo; }

changed_tests="$(awk '{ print $NF }' <<<"$files" | grep -cE '\.(spec|test)\.|(^|/)(tests?|__tests__|e2e)/' || true)"
changed_total="$(awk 'NF' <<<"$files" | wc -l | tr -d ' ')"
echo "## Test files"
echo
echo "- $changed_tests of $changed_total changed files are tests"
