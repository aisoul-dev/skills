---
name: untangle-audit
description: Read-only structural audit of a codebase or one area, any stack (a stack adapter adds the dependency graph and dead code; Nuxt/Vue/TS is built in): finds change coupling, wrong dependency direction, shallow modules, dead weight and patches, writes a decision log of PR-sized fixes. Changes no code.
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
- Nothing is installed into the project: tools run through one-off runners (`pnpm dlx`, `npx`), outputs go to `/tmp/untangle/`. Do NOT add dependencies or commit tool configs.
- **Stack adapter.** Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/untangle/adapter.sh"`. It prints the adapter for this repo and its reference file, or `none`. Read the reference now: its prepare step (run it before measuring), the typecheck, lint and test commands, tool caveats, and what each finding kind looks like in this stack. With `none`, the git and patch measurements still work; dependency direction and dead weight are found by reading, and the log says so.

## 1. Measure (scripts first, judgement later)

Run from the repo root. Every script accepts optional paths (default: the adapter's source folders that exist, `src/ lib/ app/` without an adapter, else the whole repo). Env: `UNTANGLE_SINCE` (default `6 months ago`), `UNTANGLE_OUT` (default `/tmp/untangle`), `UNTANGLE_ADAPTER` (force an adapter, or `none`).

The history measurements refuse a shallow clone (exit 3): in CI, check out with `fetch-depth: 0`.

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
| `deps.sh` | `deps.txt` | adapter step. D findings: dependency rule violations and cycles |
| `deadweight.sh` | `deadweight.txt` | adapter step. W candidates |
| `surface.sh` (optional, not in `measure.sh`) | `surface/` | adapter step. The whole public API in context, for the big picture |

Caveats:
- An adapter step the stack has no adapter for writes a line starting with `UNVERIFIED`. Then find those kinds by reading and grep in step 2, and write `UNVERIFIED (no adapter)` in the log header instead of a count.
- Every dead weight hit is a candidate: verify it with grep before it becomes a finding. The adapter's reference lists the tool's known false positives.
- `patches.sh` only finds candidates. Multi-line swallowed errors, guard flags and one-caller parameters are found by reading, in step 2.
- `surface.sh`: if nothing is emitted, skip it and use subagent summaries per area.

## 2. Find (no fixes yet)

Split the scope into areas (by feature or top-level folder). Give each subagent its area, the files in `/tmp/untangle/`, the guide below and the adapter's reference (its "What the kinds look like here" section). Each returns findings with `file:line` evidence.

**C. Change coupling**: knowledge that lives in more than one place, so changing it means finding all copies.
- the same mapping, validation or option-building logic written twice
- one concept with two shapes: one feature sends a business ID, another sends a UUID for the same field
- implicit execution order: one module must initialise before another reads its state
- shared mutable state with no owner: module-level variables, global events, string-keyed registries
- a caller reaching into another module's internals instead of using its interface
- pairs from `cochange.txt` that live apart and have no explicit link

**D. Dependency direction**: a module knows something it should not need to know.
- presentation code that reaches into state or the network directly
- low-level helpers that read configuration or application state
- business rules inside an entry point (a page, a controller, a handler), needed by another one
- a stable module importing a feature module
- anything in `deps.txt`

**M. Shallow modules**: the interface costs about as much as the implementation saves.
- a wrapper that only forwards to another module
- a function or class that wraps one call and adds nothing
- data passed through 3+ layers that nothing in between uses
- a function with so many options that callers effectively re-implement it through config

**W. Dead weight**: exists without a current reason.
- verified `deadweight.txt` hits: unused files, exports, dependencies
- parameters and options nobody passes, abstraction layers with a single implementation "for later"
- state nobody reads, feature flags that are always on
- hand-written types or schemas that duplicate generated ones

**P. Patches**: code that exists because the design does not handle a case on its own.
- branches on one specific id, name or route
- a parameter added for exactly one caller
- swallowed errors: an empty catch, a catch that only logs and continues
- timing fixes: sleeps, timeouts and retries used to win a race
- type and lint escapes: ignore comments, casts to an any-type
- skipped or disabled tests
- guard flags that stop loops or double execution

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

Adapter: nuxt
Locality: median <N> files/commit, p90 <N> (<N> commits, 6 months)
Patches: <N> (timing 7, type-escape 23, swallowed-error 4, ...)
Dependency rule violations: <N>, or UNVERIFIED (no adapter). Dead weight (verified): <N>, or UNVERIFIED (no adapter).
Regenerate: bash "${CLAUDE_PLUGIN_ROOT}/scripts/untangle/measure.sh" <scope>

## Fixes (by payback)

### F1. <title>  [S | todo]
Resolves: C1, D3, P2, P4
Change: ...
Rejected: <alternative>, because ...
Files: ~4 (src/orders/pricing.ts, ...)
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
- Locality and patch baselines recorded, and the adapter (or `none`) named.
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
