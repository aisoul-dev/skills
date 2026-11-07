---
name: pr-risk
description: Use when asked how risky a PR or branch is to merge, to assess merge risk for a reviewer, or to self-check a branch before asking for review. Read-only; posts nothing unless asked.
argument-hint: "[PR number or URL | branch | --squash <sha>]"
---

# Assess merge risk

The question a reviewer actually has is not "is this code good" but "what happens if I merge it and I am wrong". This skill answers that in five dimensions, each with the evidence behind it and the cheapest action that would lower it. It reads; it changes nothing and posts nothing unless the user asks.

Two uses:
- **Review**: someone else's PR, or yours before merging. Output goes to the chat, or to a PR comment when asked.
- **Self-check**: an agent's own branch before it asks a human for review. Do the cheap risk-lowering actions, reassess, then hand over with the final assessment.

## 0. Load the project overlay

If the repository has `.claude/aisoul/pr-risk.md`, read it first; it replaces the defaults below. A template is at `${CLAUDE_PLUGIN_ROOT}/skills/pr-risk/overlay-template.md`.

| Key | Default |
|-----|---------|
| Base branch | `origin/HEAD`, else `main` |
| Sensitive paths | the built-in categories in `risk-facts.sh` (auth and access, money, secrets and security config, data and schema, infra and CI, dependencies) |
| Error reporting | common APIs (`Sentry.*`, `captureException`, `reportError`, `logger.error`, ...) |
| Feature flags | common APIs (`isFeatureEnabled`, `useFeature`, `useFlag`, ...) |
| Rollback | revert the merge commit and redeploy; nothing else assumed |
| Verification evidence | the PR description's Evidence section and its **Not checked:** line, if present |

## 1. Gather

Facts first, judgement after.

1. **The change.** For a PR: `gh pr view <n> --json title,body,baseRefName,headRefName,files,url` and `gh pr diff <n>`; check out or fetch the head if you need to run anything. For a branch: the diff against the base.
2. **Mechanical facts**, with the overlay's values passed through the environment (`PR_BASE`, `PR_RISK_SENSITIVE`, `PR_RISK_REPORTING`, `PR_RISK_FLAGS`):

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/pr/size.sh" <branch>
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/pr/risk-facts.sh" <branch>
   ```

   `risk-facts.sh` lists changed files, sensitive-path hits by category, and signals in the changed lines: swallowed errors, catch blocks that only log, error reporting added or removed, type and lint escapes, skipped or removed tests, destructive data operations, feature flags, deleted test files. It is grep, not judgement: every hit is a lead to read, not a finding.
3. **Intent.** The PR description, the linked issue or ticket, and the commit messages. If none states intent, Scope fit is judged on what is there and says so.
4. **Read the code** behind every lead and every sensitive path. A finding cites `file:line`.

## 2. Judge five dimensions

Each gets one verdict: ✅ low risk, 👀 some risk, ⚠️ high risk, or ❓ cannot tell from what is available. ❓ is not a pass: it scores as 👀 and the gap says what is missing.

**Scope fit**: does the change do what it says and only that?
- ✅ every change traces to the stated intent; any extra is named in the description.
- 👀 unannounced drive-by changes, or behaviour assumptions the description does not mention.
- ⚠️ the change contradicts its intent, or a large part of the diff has no stated reason.

**Blast radius**: if it is wrong, how much breaks, for whom?
- ✅ one feature, one screen or one internal path; no sensitive category touched.
- 👀 shared code (composables, stores, utils, layouts, API clients) used by several features, a public interface or contract, or a sensitive category touched in a way that does not widen access or weaken checks.
- ⚠️ access widened or a check weakened, money or personal data paths changed, a schema or contract change consumers depend on, global config (CSP, CORS, build, auth middleware), or a dependency major bump.

**Verification**: is it proven to work, at the level the change needs?
- ✅ the behaviour that changed has proof matching its kind: before/after captures for UI, a test that failed before the fix for a bug, numbers for performance, the literal shape for a contract. Edge cases are tested or named as untested.
- 👀 tests exist but do not reach the changed behaviour, or the proof covers the happy path only.
- ⚠️ user-visible or sensitive behaviour changed with no proof, tests were skipped or deleted to pass, or the description claims checks nobody could see run.

**Reversibility**: if it goes wrong after merge, how expensive is undoing it?
- ✅ a revert restores the previous state completely (two-way door), or the change sits behind a flag that can be turned off.
- 👀 a revert works but leaves residue: data written in a new shape, caches, sent emails, a deploy coordinated with another service.
- ⚠️ one-way door: destructive migration, data deleted or rewritten, an external contract published, a secret rotated, anything a revert does not bring back.

**Observability**: if it breaks in production, does someone find out before a user reports it?
- ✅ failures in the changed flow reach the error reporting the project uses, or the change cannot fail at runtime (docs, types, tests only).
- 👀 failures are logged but nothing alerts on them, or a fallback hides them from the user without recording them.
- ⚠️ errors are swallowed, reporting was removed, or a critical flow fails silently.

## 3. Overall risk

Rules, applied in order; the first that fires decides, and the output says which.

1. **High** if Reversibility is ⚠️ and Blast radius is not ✅.
2. **High** if Blast radius is ⚠️ and Verification is not ✅.
3. **High** if two or more dimensions are ⚠️.
4. **Low** if no dimension is ⚠️, at most one is 👀 or ❓, and that one is neither Verification nor Reversibility.
5. **Medium** otherwise.

Rules, not an average: a one-way door on shared code is high risk however good the tests are, and an average would hide it.

## 4. Output

```markdown
**Merge risk: medium**: <one sentence: the rule that fired, in plain words>

**Scope fit** ✅
**Blast radius** 👀
- <gap, with `file:line` or a link>
- Lower it: <the cheapest action>
**Verification** ⚠️
- ...
**Reversibility** ✅
**Observability** 👀
- ...

**Not assessed:** <what could not be read or run, and why>
```

- Dimensions at ✅ get no bullets unless something is worth knowing.
- One **Lower it:** per dimension that is not ✅: one concrete action (add a test for X, put Y behind a flag, report errors from Z), not advice.
- Up to ~250 words. Cite code as `path:line`; in a PR comment, as links to the head commit.
- No bare `#<number>` outside code (GitHub autolinks it), no em dashes.

## 5. Deliver

- **Review**: print the assessment in the chat. Post it as a PR comment (`gh pr comment <n> --body-file <file>`) only when the user asks; posting is visible to others.
- **Self-check**: do the **Lower it** actions that are cheap and inside the branch's scope, rerun steps 1 to 3, and report both the starting and the final risk. Actions outside the scope go in the PR description's Review notes, not into the diff.

## What this is not

Not a code review: style, naming and structure are out of scope unless they change one of the five dimensions. Not a gate: the verdict informs the person merging; it does not decide for them.
