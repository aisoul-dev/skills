---
name: untangle-fix
description: Apply one fix from an untangle audit decision log (e.g. F3) as one small PR: re-verify, pin behavior, implement, remove the patches it makes unnecessary, review separately, update the log.
argument-hint: "<log path> <fix id>"
disable-model-invocation: true
---

# Untangle fix

One fix from the decision log = one branch = one PR. Behavior stays the same, except for bugs the fix removes on purpose, and those are named in the PR.

Arguments: log path and fix ID (e.g. `docs/untangle/orgchart-2026-11-06.md F3`). If the path is missing, look in `docs/untangle/` and ask if there is more than one log.

Finding kinds used in the log: C change coupling, D dependency direction, M shallow modules, W dead weight, P patches. See `/aisoul:untangle-audit` for definitions.

## 0. Branch

- If the repo requires a ticket before a branch, ask for the ticket ID. Follow the repo's branch naming.
- Never work on the default branch.

## 1. Re-verify the premise

The log may be stale. At HEAD, check that every finding the fix claims to resolve still exists (code may have moved or been fixed). If the premise is gone, mark the fix `obsolete` in the log with a one-line reason and stop.

## 2. Baseline

Run typecheck (`pnpm nuxt typecheck` or the repo's script), lint and unit tests. Count patches in the files the fix will touch:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/untangle/patches.sh" <file> <file> ...
```

If the baseline is red, stop and report: pre-existing failures must not blend into the fix.

## 3. Pin behavior first

If the behavior the fix touches has no test, write one and see it pass on the old code before changing anything. Test the way the code is used: component props, emits and rendered output; composable inputs and returned values; store actions and resulting state. Never assert on private functions or call counts of internals.

## 4. Implement only this fix

- Do what the log entry says. Delete the patches the new structure makes unnecessary; keep justified ones.
- Touch only files the fix needs. Anything else you notice goes into the log as a new finding, not into this diff.
- If the fix outgrows its planned files, needs another fix first, or turns out to be L: stop, record what you learned in the log entry, propose a split, ask.
- For M fixes in a repo with a spec/plan/TDD flow, treat the log entry as the spec and run that flow for this step.

Comments (touched files only):
- a comment earns its place by saying what the code cannot: an external constraint, a backend or library quirk, a product decision and its source
- delete comments that narrate what the next lines do
- when the fix removes a workaround, delete the comment that explained it

Tests (touched tests only, do this last):
- a good test breaks only when behavior a user or caller relies on breaks
- delete tests that cannot fail or only restate the implementation
- rewrite tests that break on harmless refactors so they check behavior instead
- a failing test gets fixed or deleted with a reason, never skipped

## 5. Verify

- Same checks as the baseline: all green.
- Patch count in touched files went down (rerun `patches.sh` on the same files), or the log says why not.
- If the audit used dependency rules, rerun `bash "${CLAUDE_PLUGIN_ROOT}/scripts/untangle/deps.sh"`: no new violations.
- Respect repo ratchets (e.g. net-negative explicit `any` per PR).
- `git diff --stat`: nothing outside the fix scope.

## 6. Separate review (no self-grading)

Give a fresh subagent, or the repo's review skill, only: the fix entry, the findings it claims to resolve, and the diff. It checks:
1. each claimed finding is actually resolved
2. behavior is unchanged, or the change is a named bug fix
3. no new coupling, wrong-direction import, shallow wrapper or patch was introduced

Resolve its findings, then rerun step 5.

## 7. Update the log

- Fix status `done`, PR link, patch delta.
- New findings from this work: added with evidence and IDs, not fixed now.
- If this fix changes the premise of later fixes, note it on those entries.

## 8. PR description

- Findings resolved (IDs and one-line titles), link to the log.
- What changed, in a few sentences.
- Behavior impact: none, or the named bug fixes.
- Manual check steps for anything tests do not cover.

## Stop and ask when

- the baseline is red
- the fix depends on an unfinished fix
- the diff grows past the planned scope
- removing a patch would change behavior users can see
