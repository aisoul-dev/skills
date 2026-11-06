# aisoul

Grygorii Liashenko's skill set for Claude Code, tuned for Nuxt / Vue / TypeScript work. Every skill is invoked as `/aisoul:<skill>`.

## Skills

| Skill | Group | What it does |
|-------|-------|--------------|
| `/aisoul:untangle-audit [path or concern]` | untangle | Read-only. Measures change locality and patches, finds causes, writes a decision log of PR-sized fixes to `docs/untangle/`. Changes no code. |
| `/aisoul:untangle-fix <log path> <fix id>` | untangle | Applies one fix from the log as one branch and one PR: re-verify, pin behavior with tests, implement, separate review, update the log. |

Skills are named `<group>-<action>` so related ones sort together in `/` completion. Heavy workflows run only when you call them (`disable-model-invocation: true`).

## untangle

Measure how expensive change is in a codebase, log the causes, and fix them one small PR at a time.

### Finding kinds

| ID | Kind | Question |
|----|------|----------|
| C | Change coupling | does one change silently require edits elsewhere? |
| D | Dependency direction | does stable code depend on more volatile code? |
| M | Shallow modules | does the interface cost as much as it saves? |
| W | Dead weight | does it exist without a current reason? |
| P | Patches | is this code hiding a gap in the design? |

Headline metrics: **change locality** (median and p90 files per commit) and **patch count**.

### Scripts

`scripts/untangle/` holds the measurements the audit runs. They also work standalone from any repo root:

```bash
bash plugins/aisoul/scripts/untangle/measure.sh                  # all measurements
bash plugins/aisoul/scripts/untangle/measure.sh app/features/x   # scoped
UNTANGLE_SKIP_NET=1 bash plugins/aisoul/scripts/untangle/measure.sh   # git and grep only
```

| Script | Needs | Output in `$UNTANGLE_OUT` (default `/tmp/untangle`) |
|--------|-------|------|
| `locality.sh` | git | `locality.txt` |
| `churn.sh` | git | `churn.txt` |
| `cochange.sh` | git | `cochange.txt` |
| `patches.sh` | ripgrep or grep | `patches.txt` + counts |
| `deps.sh` | pnpm or npx (downloads dependency-cruiser) | `depcruise.txt` |
| `deadweight.sh` | pnpm or npx (downloads knip) | `knip.txt` |
| `surface.sh` | `vue-tsc` in the project | `surface/*.d.ts` |

Env: `UNTANGLE_SINCE` (default `6 months ago`), `UNTANGLE_OUT`, `UNTANGLE_TOP`, `UNTANGLE_MAX_FILES` (co-change skips bigger commits, default 25), `UNTANGLE_APP_PREFIX` (`app/` for Nuxt 4, empty for Nuxt 3), `UNTANGLE_TSCONFIG`.

Nothing is installed into the audited project and no config is written there.

### Credits

Inspired by [caldoai/skills `untangle-codebase`](https://github.com/caldoai/skills) (MIT). The taxonomy, metrics, scripts and workflow here are independent. Background reading is listed at the end of the audit skill.
