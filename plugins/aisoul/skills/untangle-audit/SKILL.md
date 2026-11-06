---
name: untangle-audit
description: Read-only structural audit of a Nuxt/Vue/TS codebase or one area: finds change coupling, wrong dependency direction, shallow modules, dead weight and patches, writes a decision log of PR-sized fixes. Changes no code.
argument-hint: "[path or concern]"
disable-model-invocation: true
---

# Untangle audit

Goal: measure how expensive change is in the scope, find why, and write a decision log of fixes that each fit one reviewable PR. This skill NEVER edits source code. Fixes are applied later, one at a time, with `/aisoul:untangle-fix`.

Argument (optional): a path or a concern, e.g. `app/components/orgchart` or `realtime sync`.

## The lens: five kinds of findings

Every finding answers one question: what makes a change here cost more than it should?

| ID | Kind | Cost it causes | Grounded in |
|----|------|----------------|-------------|
| C | Change coupling | a change silently requires edits elsewhere | Tornhill (change coupling), Page-Jones (connascence) |
| D | Dependency direction | volatile code drags stable code along | Martin (Stable Dependencies), Parnas (information hiding) |
| M | Shallow modules | you read and pass through more than you gain | Ousterhout (deep vs shallow modules) |
| W | Dead weight | you maintain and read code nobody needs | Fowler (Speculative Generality), dead code |
| P | Patches | the design is wrong somewhere and this hides it | Ousterhout (define errors out of existence) |

The two headline metrics:
- **Change locality**: median and p90 files touched per commit in the scope. Lower is better.
- **Patch count**: number of P findings. The trend matters more than the absolute number.

## 0. Setup

- Scope: use the argument if given. Otherwise ask once: whole repo or which area.
- Log path: `docs/untangle/<scope>-<YYYY-MM-DD>.md`, unless the repo already has a place for specs/plans. If the repo requires a ticket before a branch, write the log without committing and say so.
- Nothing is installed into the project: scripts use `pnpm dlx` (or `npx`), outputs go to `/tmp/untangle/`. Do NOT add devDependencies or commit tool configs.
- Run `pnpm nuxt prepare` first so `.nuxt/` types and path aliases exist.

## 1. Measure (scripts first, judgement later)

Run from the repo root. Every script accepts optional paths (default: existing `app/ server/ shared/ src/`). Env: `UNTANGLE_SINCE` (default `6 months ago`), `UNTANGLE_OUT` (default `/tmp/untangle`).

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/untangle/measure.sh"                          # whole repo
bash "${CLAUDE_PLUGIN_ROOT}/scripts/untangle/measure.sh" app/components/orgchart  # scoped
```

`measure.sh` runs all of the following; each one also runs alone.

| Script | Output | How to read it |
|--------|--------|----------------|
| `locality.sh` | `locality.txt` | baseline for the headline metric |
| `churn.sh` | `churn.txt` | hot files: where a fix pays back fastest |
| `cochange.sh` | `cochange.txt` | pair that co-changes but lives apart: C candidate. Hot file co-changing with many unrelated files: does too much (D or M) |
| `patches.sh` | `patches.txt` + counts | P candidates by label; counts are the patch baseline |
| `deps.sh` | `depcruise.txt` | D findings: cycles, utils importing UI, logic importing components, shared importing app |
| `deadweight.sh` | `knip.txt` | W candidates |
| `surface.sh` (optional, not in `measure.sh`) | `surface/*.d.ts` | the whole public API in context, for the big picture |

Caveats:
- `knip`: verify every hit with grep before it becomes a finding. `resolveComponent`, `<component :is>`, string lookups, server routes and test-only usage give false positives.
- `deps.sh`: auto-imported components and composables have no import statement, so the graph misses them. For each composable and store in scope, list consumers with grep (`grep -rn "useXxx(" app/`). If `.vue` files show zero dependencies, the SFC parser was not resolved: do not fix it, rely on grep for `.vue` and note it in the log.
- `patches.sh` only finds candidates. Multi-line swallowed errors, guard flags and one-caller parameters are found by reading, in step 2.
- `surface.sh`: if nothing is emitted, skip it and use subagent summaries per area.

## 2. Find (no fixes yet)

Split the scope into areas (by feature or top-level folder). Give each subagent its area, the files in `/tmp/untangle/` and the guide below. Each returns findings with `file:line` evidence.

**C. Change coupling**: knowledge that lives in more than one place, so changing it means finding all copies.
- the same mapping, validation or option-building logic written twice (two components each build the same select options)
- one concept with two shapes: one feature sends a business ID, another sends a UUID for the same field
- implicit execution order: a plugin must init before a middleware reads its state; a watcher relies on another watcher having run
- shared mutable state with no owner: module-level `let` in a composable, `provide`/`inject` with string keys, `window` events, ad-hoc event buses
- parents driving children through template refs and `defineExpose` instead of props and emits
- pairs from `cochange.txt` that live apart and have no explicit link

**D. Dependency direction**: a module knows something it should not need to know.
- leaf UI components that import stores or call the API directly
- utils that read stores or runtime config
- business rules inside pages, needed by another page
- a stable module importing a feature module
- anything in `depcruise.txt`

**M. Shallow modules**: the interface costs about as much as the implementation saves.
- a component that only forwards props to a UI library component
- a composable that wraps one call and adds nothing
- props drilled through 3+ levels that nothing in between uses
- a function with so many options that callers effectively re-implement it through config

**W. Dead weight**: exists without a current reason.
- verified `knip.txt` hits: unused files, exports, dependencies
- props and options nobody passes, abstraction layers with a single implementation "for later"
- store state nobody reads, feature flags that are always on
- hand-written types that duplicate generated API types

**P. Patches**: code that exists because the design does not handle a case on its own.
- branches on one specific id, name or route
- a parameter added for exactly one caller
- swallowed errors: empty catch, `.catch(() => {})`, catch that only logs and continues
- timing fixes: `setTimeout`, `nextTick`, retries used to win a race
- type escapes: `@ts-ignore`, `as any`, `eslint-disable`
- skipped or disabled tests
- guard flags that stop watcher loops or double fetches

Rule: no evidence, no entry. Every finding cites `file:line` or a measurement line. A finding can belong to two kinds; pick the one whose fix is cheaper to explain.

## 3. Design it twice (main agent, not subagents)

Group related findings into clusters. For each cluster, sketch at least two alternative structures, then pick the one that removes the most findings with the fewest touched files. Prefer one structural change that makes several patches unnecessary over one patch per patch.

For each chosen fix write: ID, title, findings it resolves, the change in 2-5 sentences, the rejected alternative in one line and why, estimated files, behavior risk (none / low / needs manual check, and what to check), dependencies on other fixes, size S/M/L. Split every L before it goes in the log.

Patches the design cannot remove go to "Justified patches" with the external reason (backend contract, third-party library behavior, browser bug). No external reason means it is still a finding.

Order fixes by payback: findings resolved per touched file, hot files first.

## 4. Independent pass

Spawn a fresh subagent that has NOT seen the log. Give it only the scope and the step 2 guide. Compare its findings with the log: add what is real and new, rerun step 3 for those. At most two rounds. The audit is done when an independent pass adds nothing material.

## Log format

```markdown
# Untangle audit: <scope> (<YYYY-MM-DD>, <sha>)

Locality: median <N> files/commit, p90 <N> (<N> commits, 6 months)
Patches: <N> (timing 7, type-escape 23, swallowed-error 4, ...)
Dependency rule violations: <N>. Dead weight (verified): <N>.
Regenerate: bash "${CLAUDE_PLUGIN_ROOT}/scripts/untangle/measure.sh" <scope>

## Fixes (by payback)

### F1. <title>  [S | todo]
Resolves: C1, D3, P2, P4
Change: ...
Rejected: <alternative>, because ...
Files: ~4 (app/composables/useX.ts, ...)
Behavior risk: low. Manual check: ...
After: none

## Findings

### C1. <title>
Evidence: app/a.ts:12, app/b.ts:40; co-changed in 9 commits
Cost: ...

## Justified patches
- P9 app/x.ts:88 setTimeout before chart init: third-party library needs a frame after mount.
```

## Done criteria

- Every finding has evidence and either a fix or a justification.
- Every fix fits one PR (S or M).
- Locality and patch baselines recorded.
- The independent pass added nothing material.
- `git status` shows only the log (or nothing). No source file changed.

Final reply: log path, finding counts by kind, number of fixes, baselines, top 3 fixes by payback.

## Further reading

- John Ousterhout, *A Philosophy of Software Design*: deep vs shallow modules, design it twice, defining errors out of existence, comments
- Adam Tornhill, *Your Code as a Crime Scene* / *Software Design X-Rays*: churn, change coupling, hotspots
- Meilir Page-Jones, *What Every Programmer Should Know About Object-Oriented Design*: connascence
- Robert C. Martin, *Clean Architecture*: Stable Dependencies Principle
- David Parnas, "On the Criteria To Be Used in Decomposing Systems into Modules" (1972)
- Martin Fowler, *Refactoring*: Speculative Generality and other smells
