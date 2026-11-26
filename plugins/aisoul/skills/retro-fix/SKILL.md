---
name: retro-fix
description: Apply one fix from a retro-audit or retro-curate decision log (e.g. F2) as one small PR: re-verify the gap, prove the fix would have caught the session's case, implement only that change, review separately, update the log.
argument-hint: "<log path> <fix id>"
disable-model-invocation: true
---

# Retro fix

One fix from the decision log = one target = one branch = one PR. The fix must be shown to stop the friction it was written for, not only to exist.

Arguments: log path and fix ID (e.g. `docs/retro/2026-11-26-export-flow.md F2`). If the path is missing, look in the Log folder (`docs/retro` unless `.claude/aisoul/retro-audit.md` says otherwise) and ask if there is more than one log.

Finding kinds used in the log: G guardrail gap, S standard missed, P procedure, N navigation, A access, T tool economy, X steering debt; curate logs add U unused, O overlap, B bloat, Z noise. See `/aisoul:retro-audit` and `/aisoul:retro-curate` for definitions and the fix ladder.

## 0. Where the change goes

- **Target in this project**: a branch in this repo. If the repo requires a ticket before a branch, ask for the ticket ID. Follow the repo's branch naming. Never work on the default branch.
- **Target outside** (marked `outside` in the log: a skills repo, a user's global steering file):
  - a git repo (a skills repo, a dotfiles repo): a branch and a PR there, under that repo's own rules (version bumps, changelog, tests);
  - not a git repo (`~/.claude/CLAUDE.md`, a user skill folder): show the exact diff and ask before writing. No PR, the log records the change.
  - a plugin skill without a known source repo: write the proposed change into the log as a note for its author and stop.
- Nothing from this project goes into an outside target: no paths, names, tickets, customer or colleague details. The general rule goes out; the specific part stays in this project's overlay.

## 1. Re-verify the gap

The log may be stale. At HEAD, check that the gap still exists: the check was not added since, the skill was not already patched, the steering line is still there. If the premise is gone, mark the fix `obsolete` in the log with a one-line reason and stop.

## 2. Prove it first

Show that the fix would have caught the session's case before calling it done.

| Kind | Proof |
|------|-------|
| G | Write the check, then run it on the case from the session (the old code, or a minimal fixture with the same mistake): it must fail. Then run it on the whole repo and count existing violations. A few: fix them in this PR. Many: land it as a warning or a ratchet (no new violations), or split. Never land a blocking check that is red on the default branch. |
| S | Add the rule. When the session's mistake is in a diff, give the repo's review skill that diff (or a minimal one) and confirm it now flags it. |
| P | Patch the skill, then replay: a fresh headless session on a scratch worktree with the task from the session moment, run with `AISOUL_RETRO_SKIP=1` so the collector does not queue it. It must follow the patched step. Required when the patch reorders or removes steps; for a one-line pitfall, reading the patched skill against the session moment is enough, and the PR says so. |
| N, A | Confirm the pointer sits in a file the agent opened at that moment in the session, or that the information is now reachable by the command the agent ran. |
| T | Run the old and the new call on the same input and record the size or time. |
| X, U, O, B | Confirm nothing references what is removed or moved: grep skills, steering files, overlays and scripts. For a removed steering line, the check or standard that replaces it already exists. |
| Z | Show the rule's suppressions or misfires before, and that the changed rule still catches the case it was added for. |

If the proof does not show the change, stop: record what happened in the log entry and ask.

## 3. Implement only this fix

- Do what the log entry says, at the rung it names. If on the way a cheaper rung turns out to work, take it and note it in the log.
- Touch only the files the fix needs. Anything else you notice goes into the log as a new finding, not into this diff.
- **Skills and standards text.** Match the target's existing style. Replace or tighten a line rather than append one; a skill that grows past its job moves the detail into a support file next to it. Write instructions, not stories: no session narrative, no dates, no "we once". If the user has a writing style skill for agent text, follow it.
- **Checks.** The cheapest mechanism the repo already uses: a lint rule before a custom script, a custom script before a new tool. The error message says what to do instead, so the agent that hits it can fix the code without reading the rule.
- **Steering.** A line moved out of `CLAUDE.md` or `AGENTS.md` is deleted there in the same PR.

## 4. Verify

- The target repo's own checks: lint, typecheck, tests, or a skills repo's validation and script tests. All green.
- The proof from step 2 still holds after the final edit.
- `git diff --stat`: nothing outside the fix.

## 5. Separate review (no self-grading)

Give a fresh subagent, or the repo's review skill, only: the fix entry, the findings it resolves with their evidence lines (the excerpts, not the whole transcript), and the diff. It checks:
1. the change would have prevented the friction at each evidence point
2. no cheaper rung would have done it
3. nothing project-specific or private went to an outside target
4. nothing else changed

Resolve its findings, then rerun step 4.

## 6. Update the log

- Fix status `done`, PR link (or "applied locally" for a non-repo target), and what was added: the file plus the rule name, skill section or check command. `/aisoul:retro-curate` reads this to find what retro added.
- New findings from this work: added with evidence and IDs, not fixed now.
- If this fix changes the premise of later fixes, note it on those entries.

## 7. PR description

- Findings resolved, with IDs and session references (`3f2a91c0:L214`), never transcript excerpts that hold private content.
- What changed, in a few sentences.
- The proof: the case that fails without the fix and passes with it, or the replay result, or why reading was enough.
- For a new blocking check: how many existing violations it found and what happened to them.

## Stop and ask when

- the gap is gone or the proof does not show the change
- a new check is red on many existing files
- the target is outside the project and not a git repo
- the fix would add a line to always-loaded steering
- the diff grows past the planned scope
