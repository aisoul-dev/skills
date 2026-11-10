# Shared helpers for scripts/pr. Source it, do not run it.
# shellcheck shell=bash
# shellcheck disable=SC2034  # BASE, BASE_NOTE and LOCKFILES are read by the scripts that source this

# The base every script compares against, the same way everywhere:
# PR_BASE if set, else origin/HEAD, else origin/main, else main.
# Sets BASE and BASE_NOTE (a short note when a fallback was used).
resolve_base() {
  BASE_NOTE=""
  if [ -n "${PR_BASE:-}" ]; then BASE="$PR_BASE"; return 0; fi
  BASE="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  [ -n "$BASE" ] && return 0
  if git rev-parse --verify --quiet origin/main >/dev/null; then
    BASE=origin/main; BASE_NOTE=" (origin/HEAD not set, fell back to origin/main)"
  else
    BASE=main; BASE_NOTE=" (origin/HEAD and origin/main not found, fell back to main)"
  fi
}

# The hint every script gives for an empty range.
empty_range_hint() {
  echo "Empty range: if the PR is already merged, the base has moved past it. Pass its base, PR_BASE=<base sha> with the head sha, or its merge commit, --squash <merge sha>."
}

require_repo() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "$1: run this from inside a git repository" >&2
    exit 1
  }
}

# Lockfiles of every package manager the scripts know, by file name. size.sh
# and pr-describe leave them out of the diff size; risk-facts.sh lists them as
# dependencies. One list, so the scripts never disagree.
LOCKFILES="pnpm-lock.yaml package-lock.json npm-shrinkwrap.json yarn.lock bun.lock bun.lockb poetry.lock uv.lock Pipfile.lock Gemfile.lock composer.lock Cargo.lock go.sum"

# LOCKFILES as an ERE matching a path in any directory.
lockfiles_re() {
  local names
  names="$(tr ' ' '\n' <<<"$LOCKFILES" | sed 's/[.]/\\./g' | paste -sd'|' -)"
  printf '(^|/)(%s)$' "$names"
}
