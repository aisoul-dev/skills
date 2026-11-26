# untangle stack adapters

The untangle core (git history, the patch census, the lens and the workflow in the skills) knows no stack. A stack adapter adds what only the stack can measure: the dependency graph, dead code, and the public surface, plus a reference of what each kind of finding looks like there.

One folder per adapter: `adapters/<name>/`. `lib.sh` runs every `detect.sh` in alphabetical order and uses the first that matches; `UNTANGLE_ADAPTER=<name>` forces one, `UNTANGLE_ADAPTER=none` forces the core alone.

## Contract

| File | Required | What it does |
|------|----------|--------------|
| `detect.sh` | yes | exits 0 when the current directory is a project of this stack. Fast, no network, no side effects. |
| `adapter.env` | yes | sourced by `lib.sh`. Sets `DEFAULT_PATHS` (source folders measured when no path is given), `EXTS` (file extensions the patch census reads), `EXCLUDE_DIRS`, and optionally `EXTRA_PATTERNS` (an array of `label\|regex` lines added to the census). |
| `reference.md` | yes | for the skills: how to prepare the project, the typecheck, lint and test commands, caveats of the tools, and stack examples for each finding kind (C, D, M, W, P) and for pinning behavior with tests. |
| `deps.sh` | no | dependency direction: writes `$OUT/deps.txt`, one violation per line with the files involved. Violations are a result: exit 0. |
| `deadweight.sh` | no | dead code candidates: writes `$OUT/deadweight.txt`. |
| `surface.sh` | no | the public API only (declarations, signatures) into `$OUT/surface/`. |

Step scripts start with `source "$(dirname "$0")/../../lib.sh"`, so they get `OUT`, `PATHS`, `SINCE`, `run_dlx` and the adapter settings. They never install anything into the project: tools run through a one-off runner (`pnpm dlx`, `npx`, `uvx`, a container) or are already the project's own. A missing optional step is fine: the core writes an `UNVERIFIED` line for it, and the audit finds those findings by reading and says so in the log.

## Adding an adapter

1. Copy `nuxt/` as a starting point, delete what does not apply.
2. `detect.sh` on the stack's manifest (`composer.json` with `laravel/framework`, `pyproject.toml`, `go.mod`).
3. `adapter.env`: source folders, extensions, excluded folders.
4. `reference.md`: write it from a real project of that stack, not from memory. Every example should be something you have seen.
5. Steps for whatever the stack has tools for. Wire them only after running them on a real repository.
6. A case in `tests/smoke.sh`: detection on a minimal project of the stack, and the census picking up its extensions.
