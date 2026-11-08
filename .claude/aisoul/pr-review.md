# pr-review overlay for this repository

## Base

`origin/main`

## Bug hunt

Claude Code's built-in `/code-review` with args `xhigh origin/main` when available; otherwise the skill's own hunt.

## Spec folders

```text
docs/specs
```

## Gates

The same as CI (`.github/workflows/validate.yml`):

```bash
claude plugin validate .
for p in plugins/*/; do claude plugin validate "$p"; done
shellcheck -x plugins/*/scripts/*/*.sh tests/*.sh
for t in tests/*.sh; do bash "$t"; done
em="$(printf '\xe2\x80\x94')"; ! grep -rn "$em" --include='*.md' --include='*.json' --include='*.sh' --include='*.cjs' .
```

A plugin change without a version bump in `plugin.json` is a red gate (CI checks it on pull requests).

## Constraints

- General only: no employer code, internal paths, colleague names or team rules.
- Scripts never install into the project they inspect and never print a plausible but wrong result; they fail loudly instead.
- No em dashes in skill text.
- The marketplace and plugin names `aisoul` never change.

## Own-branch handoff

A task list for the next implementation run, each Blocker with the failing test to write first.

## Comment language

English.
