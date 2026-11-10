# pr-review overlay

<!--
Copy this file to `.claude/aisoul/pr-review.md` in a repository to adapt
/aisoul:pr-review to it. Every section is optional: delete what you do not
need and the default applies. Keep the headings as they are.
-->

## Base

`origin/main`

## Bug hunt

Claude Code's built-in `/code-review` with args `xhigh origin/main`, unless the user names another level. Not a plugin skill that shares the name.

## Standards review

<!-- Optional. A standards and spec review skill to run as a second source, e.g.:
`code-review` from `mattpocock/skills`, with `origin/main` as its fixed point.
Leave this comment alone or delete the section for none. -->

## Spec folders

Where specs live, one folder per line, passed as `PR_SPEC_DIRS`:

```text
docs/specs
```

## Ticket pattern

`[A-Z][A-Z0-9]*-[0-9]+`

## Gates

Run from the repository root; lint and format only the changed files:

```bash
pnpm tsc --noEmit
git diff --name-only --diff-filter=d origin/main...HEAD | grep -E '\.(ts|vue)$' | xargs -r pnpm exec eslint
git diff --name-only --diff-filter=d origin/main...HEAD | xargs -r pnpm exec prettier --check --ignore-unknown
pnpm test --run
```

## Ratchets

Explicit `any` must go down in every PR (net-negative); even is a Non-blocking row:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/pr/ratchet.sh" '(:|<|,|\bas)\s*any\b' -- '*.ts' '*.vue'
```

## Constraints

The "Critical constraints" section of `CLAUDE.md`. Violating one is an
architectural Blocker.

## Feature flags

- `NUXT_PUBLIC_NEW_CHECKOUT`: hides the Checkout link in the header only; `/checkout` stays reachable by URL for staff.

## Contract source

The backend repository, found in this order:

1. `$API_REPO`
2. `../api` next to the main checkout (resolve with `git rev-parse --git-common-dir` so it works in a worktree)
3. GitHub: `gh api -H "Accept: application/vnd.github.raw" "repos/acme/api/contents/<path>?ref=main"`
4. none: mark every contract claim _inferred_ and put "Contract" under _Not checked_

DTOs live in `app/Http/Requests/`, feature tests in `tests/Feature/`.

## Own-branch handoff

`/goal`: it writes the failing test before the fix.

## Comment language

English.

## Disclosure

<!-- Optional. A line for the end of the review summary, e.g.:
Reviewed with an AI agent; findings triaged by @handle.
Delete this section for none. -->
