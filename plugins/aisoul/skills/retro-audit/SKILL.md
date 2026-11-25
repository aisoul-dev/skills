---
name: retro-audit
description: Read-only retrospective on one or more coding-agent sessions: finds the friction in the transcript (corrections, failed attempts, long searches, costly calls) and writes a decision log of PR-sized fixes to the agent's environment (checks, review standards, skills, pointers). Changes nothing.
argument-hint: "[session id or transcript | --queue | --last <n>]"
disable-model-invocation: true
---

# Retro audit

Goal: turn friction from past sessions into changes to what the next session starts with, so the same friction cannot happen again, and write them as a decision log of fixes that each fit one reviewable PR. This skill NEVER edits the project, a skill or a steering file. Fixes are applied later, one at a time, with `/aisoul:retro-fix`.

It is not a memory system. It does not record what happened; it changes the environment so that it does not happen again.

Argument (optional): a session id or transcript path, `--queue` for the sessions the collector queued for this project, `--last <n>` for the newest n sessions here. Without one: the current session (the newest from `sessions.mjs --limit 1`) if it did real work, otherwise ask once.

## The lens: seven kinds of findings

Every finding answers one question: what made this session cost more than it should, and what would have stopped it?

| ID | Kind | Signal in the session | Default fix |
|----|------|-----------------------|-------------|
| G | Guardrail gap | a mistake a check could have caught; a check that exists but is not wired or is broken; no hook or CI running lint, types or tests at all | lint rule, type, test, hook, CI job |
| S | Standard missed | a judgement-call mistake that review did not catch | a rule where the reviewer reads it |
| P | Procedure | a working sequence found only after failed attempts; a skill that misled, did not load, or did not exist | a skill patch |
| N | Navigation | a long search for a file or a fact | a pointer in a file the agent already reads |
| A | Access | information the agent needed and could not reach | make it reachable: a log written to a file, a script, read-only access |
| T | Tool economy | expensive calls that returned little | a narrower call, a filter, a cheaper tool |
| X | Steering debt | steering lines that change nothing, or that belong in a check or a standard | delete or move them |

## The fix ladder

Route every finding to the first rung that would have prevented it.

1. **Deterministic check (G).** For mechanical violations: fixed syntax patterns, banned APIs, import shapes, file locations, config values. A check can fail; a prose line cannot. Building the check is the default over writing a rule. Before proposing a new one, read the repo's own check commands (`package.json` scripts, `Makefile`, pre-commit config, CI workflows): an existing check that is not wired, skipped or silently broken is the finding, not a new check.
2. **Reviewer standard (S).** Only for judgement calls: consistency across files, matching surrounding style, naming that needs context. It goes where the review reads it (the Standards file), because the reviewer sees only a diff. Not into always-loaded steering.
3. **Skill patch (P).** For multi-step procedures. Patch in this order: the skill that was used or should have been; an umbrella skill for the area; a support file next to it (a reference, a script); a new skill only as the last resort. A skill that should have loaded and did not is fixed in its `description`.
4. **Pointer or access (N, A).** One line in a file the agent already opens at that moment (the folder's README, the skill, an index), or a change that makes the information reachable.
5. **Steering line.** Last resort, with the reason none of the rungs above works: `CLAUDE.md` and `AGENTS.md` load into every session, relevant or not.
6. **Nothing.** A one-off, or a fix that costs more than the friction. It goes under "Not fixed" with the reason.

Never keep: failures caused by the environment (a network blip, an expired token, a full disk), one-off details of this task, anything that is true only for this ticket.

## 0. Setup

If the repository has `.claude/aisoul/retro-audit.md`, read it first. Its values replace the defaults below; anything it does not mention keeps the default. A template is at `${CLAUDE_PLUGIN_ROOT}/skills/retro-audit/overlay-template.md`.

| Key | Default |
|-----|---------|
| Log folder | `docs/retro` |
| Standards file | the first that exists: `CODING_STANDARDS.md`, `docs/CODING_STANDARDS.md`, the Constraints section of `.claude/aisoul/pr-review.md`; otherwise ask when the first S finding appears |
| Skill sources | project skills in `.claude/skills/`, user skills in `${CLAUDE_CONFIG_DIR:-~/.claude}/skills/`. Plugin skills are read-only copies: a fix to one needs its source repo, named in the overlay, or it becomes a note for the plugin's author |
| Steering files | `CLAUDE.md`, `AGENTS.md`, `.claude/CLAUDE.md`, and the user's `${CLAUDE_CONFIG_DIR:-~/.claude}/CLAUDE.md` |

- Log path: `<Log folder>/<YYYY-MM-DD>-<topic>.md`. Write it, do not commit it.
- Record the project commit: `git rev-parse --short HEAD`.
- **Privacy.** Transcripts hold private code, secrets, and other people's names and messages. The log quotes at most one short line per evidence point and never a key, token, password or personal detail. A fix whose target lives outside this project (a shared or public skills repo, a global steering file) carries no project specifics: generalize it, or put the specific part in this project's overlay.

## 1. Measure (scripts first, judgement later)

Transcripts are read from `${CLAUDE_CONFIG_DIR:-~/.claude}/projects`, so a session is visible only from the config directory it ran under.

```bash
mkdir -p /tmp/retro
node "${CLAUDE_PLUGIN_ROOT}/scripts/retro/sessions.mjs" --queue      # queued sessions for this project
node "${CLAUDE_PLUGIN_ROOT}/scripts/retro/sessions.mjs" --limit 5    # or the newest ones here
node "${CLAUDE_PLUGIN_ROOT}/scripts/retro/signals.mjs" <transcript> [...] > /tmp/retro/signals.txt
```

`sessions.mjs` prints last activity, tool calls, tool errors, human messages and the path. `signals.mjs` prints, per session, every human message, interruption, tool error, repeated command, read and search count before the first edit, re-read file, edit churn, large tool result, compaction and skill use, each with its line number. Thresholds: `RETRO_LARGE`, `RETRO_REPEAT`, `RETRO_REREAD`, `RETRO_CHURN`.

Signals are candidates, not findings. Reading them:
- a human message right after a tool call or an edit that corrects it: G, S or P, depending on whether a check, a reviewer or a procedure would have prevented it
- an interruption: read the events before it, the agent was going somewhere the user did not want
- a repeated command with failures: P (the sequence that finally worked), G (a check would have failed earlier and cheaper) or T
- many reads and searches before the first edit, files read again and again: N
- large tool results: T
- edit churn on one file: P or G
- a compaction mid-task: T, or the task was too big for one session
- a skill used, then a correction: that skill is the P target

Also read the guardrails once: check scripts, CI workflows, pre-commit config, lint config. They decide every G finding and the "no guardrail" finding.

## 2. Find (no fixes yet)

Read the transcript around each signal: the Read tool with an offset a few lines before it, about 30 lines. Transcript lines are long JSON; read what the user said, what the agent did and what came back. Also look for what the signals cannot see: the agent stating something false and nobody catching it, an assumption that cost time later, a question to the user that a file could have answered.

For long transcripts or several sessions, split by session or by time and give each part to a subagent with the signals and this step. Each returns findings with evidence. Subagents must not invoke review or retro skills.

Rule: no evidence, no entry. Every finding cites `<session>:L<n>` (the first 8 characters of the session id) and, when it concerns the repo, `file:line`. A candidate that cannot be traced to a specific moment is dropped, however reasonable it sounds: generic advice that fills a category is how a retro goes wrong.

## 3. Route (main agent, not subagents)

For each finding: classify it as mechanical, judgement or procedure, walk the ladder, and stop at the first rung that would have prevented it. Findings from different sessions with one cause get one fix.

For each fix write: ID, title, findings it resolves, Target (the file or skill it changes, marked `outside` when it lives outside this project), the change in 2-5 sentences (for G the rule and the command that runs it; for P the lines to add or replace and the rung), why no cheaper rung works (one line), how to prove it (for G the case from the session that must fail; for P, S, N the session moment it addresses and a one-line replay task), size S or M. Split every L.

Order by payback: friction prevented (minutes, failed runs, corrections, tokens) per change. At equal payback, deterministic checks first.

## 4. Independent pass

Spawn a fresh subagent that has NOT seen the log. Give it the signals file, the transcript paths and the step 2 guide. Two jobs: find what the log missed, and, for each fix, open only its evidence lines and confirm the moment shows what the fix claims. Drop or correct what it cannot confirm, add what is real and new, rerun step 3 for those. At most two rounds.

## 5. Close the queue

For queued sessions that are now in the log: `node "${CLAUDE_PLUGIN_ROOT}/scripts/retro/sessions.mjs" --drop <transcript> [...]`.

## Log format

```markdown
# Retro: <topic> (<YYYY-MM-DD>, <sha>)

Sessions: 3f2a91c0 (52 min, 84 tool calls, 3 corrections), 9be1d204 (...)
Guardrails: lint in CI yes, typecheck in CI no, pre-commit none, tests in CI yes
Findings: G 2, S 1, P 2, N 1, A 0, T 1, X 0

## Fixes (by payback)

### F1. <title>  [S | todo]
Resolves: G1, P2
Target: eslint.config.mjs
Change: ...
Not cheaper: ...
Prove: ...
After: none

## Findings

### G1. <title>
Evidence: 3f2a91c0:L214 (user correction), 3f2a91c0:L230; app/api/client.ts:40
Cost: ~6 min, 2 failed test runs

## Not fixed
- 3f2a91c0:L400 pnpm install timed out: environment, not a gap.
```

## Done criteria

- Every finding has evidence the independent pass confirmed, and either a fix or a "Not fixed" reason.
- Every fix names one target and fits one PR (S or M).
- No fix adds a steering line without saying why the cheaper rungs fail.
- The log quotes no secret, and no fix sends project specifics to an outside target.
- `git status` shows only the log (or nothing). Nothing else changed.

Final reply: log path, finding counts by kind, number of fixes, top 3 by payback, and which sessions left the queue.

## Credits

- Matt Pocock's `retro` ([mattpocock/skills](https://github.com/mattpocock/skills), MIT): environment over memory, the categories behind G, S, N, A, T and X, mechanical versus judgement, an unwired check as the finding.
- Nous Research's Hermes Agent learning loop ([NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent), MIT): the skill patch order, never keeping environment failures or one-off details, periodic curation.
