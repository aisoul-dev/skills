---
name: retro-curate
description: Read-only periodic pruning of what retro and you added to an agent's environment: unused or overlapping skills, bloated skills, noisy checks, steering lines that a check or standard now covers. Writes a decision log for retro-fix. Changes nothing.
argument-hint: "[--days <n>]"
disable-model-invocation: true
---

# Retro curate

`/aisoul:retro-audit` only adds: checks, standards, skill lines, pointers. Each one alone is cheap; together they bloat skills, slow the build and fill steering with rules nobody needs. This skill looks at the whole environment over time and proposes what to retire, merge, shrink or loosen. It NEVER deletes or edits anything. Its log is applied with `/aisoul:retro-fix`, one entry at a time.

Run it on a schedule (monthly is enough for most setups) and in each config directory you use: skill usage is read from that directory's sessions only.

Argument (optional): `--days <n>`, the usage window, default 60.

## The lens

| ID | Kind | Question | Default fix |
|----|------|----------|-------------|
| U | Unused | was the skill used in the window, and should it have been? | retire it, merge it into an umbrella skill, or fix its description if it should have loaded |
| O | Overlap | do two skills cover the same procedure, or contradict each other? | merge into one, the other becomes a pointer or goes |
| B | Bloat | did the skill grow past its job? | condense it, move detail into support files |
| Z | Noise | does a check fire on correct code, get suppressed, or never fire at all? | loosen it, scope it, or remove it |
| X | Steering debt | is a steering line now covered by a check or a standard, or does it change nothing? | delete it |

## 0. Setup

Read `.claude/aisoul/retro-audit.md` if present: Log folder, Skill sources and Steering files come from there, with the same defaults as `/aisoul:retro-audit`. Log path: `<Log folder>/<YYYY-MM-DD>-curate.md`. Write it, do not commit it. Record `git rev-parse --short HEAD` of each repo it looks at.

## 1. Measure

```bash
mkdir -p /tmp/retro
# installed skill names, from every skill source (adjust to the overlay)
ls .claude/skills "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills" 2>/dev/null | grep -v ':$' | sort -u > /tmp/retro/skills.txt
node "${CLAUDE_PLUGIN_ROOT}/scripts/retro/usage.mjs" --days 60 $(cat /tmp/retro/skills.txt) > /tmp/retro/usage.txt
```

`usage.mjs` prints uses, sessions, last use and name, including installed skills with no use as 0. Plugin skills show up as `plugin:skill`.

Then, by reading:
- **What retro added**: every `done` fix in the logs in the Log folder, with the file and rule, section or check it added. These are the first candidates for Z and B: they were added for one session's friction and have not been judged since.
- **Skill size and growth**: `wc -l` of every `SKILL.md`, and `git log --oneline -- <skill folder>` where skills are in a repo.
- **Suppressions** of each retro-added lint rule: `rg -c "<disable comment>.*<rule name>"` across the repo; a `--no-verify` or a skipped hook in recent sessions (`signals.mjs` on the newest ones) is a Z signal for hooks.
- **Steering**: word count of each steering file, and for each line, whether a check or a standard now enforces the same thing.

## 2. Find

- **U**: 0 uses in the window. Before proposing removal, check whether it is a manual-only skill (`disable-model-invocation: true`) used rarely on purpose, such as a release or a yearly task: those stay, and the log says so. For a skill that should load by itself and never did, the finding is its description, not its existence.
- **O**: read the descriptions of all skills side by side; then the bodies of any pair that could answer the same request. Contradicting instructions are always a finding.
- **B**: a skill whose body explains more than it instructs, repeats itself, or grew mostly through appended pitfalls. Line count is a signal, not the rule.
- **Z**: a rule suppressed more than a few times, or one that has never fired since it was added (it may guard something that no longer happens).
- **X**: steering lines duplicated by a check, a standard or a skill; lines that no session would behave differently without.

Rule: no evidence, no entry. Each finding cites the usage line, the file and line, the suppression count or the log entry it comes from.

## 3. Route

For each finding, the fix with the least loss: loosen before remove, merge before delete, move before drop. Write fixes in the `retro-audit` log format (ID, title, Resolves, Target, Change, Not cheaper, Prove, size), ordered by what they save: tokens loaded per session first (steering, skill descriptions), then build and review time, then maintenance.

Retiring a skill the user wrote by hand is always a proposal they confirm in `/aisoul:retro-fix`, never a default.

## Done criteria

- Every finding has evidence and a fix or a reason to keep things as they are.
- Every fix fits one PR.
- Nothing was edited or deleted.

Final reply: log path, findings by kind, the three fixes that save the most, and the usage window used.
