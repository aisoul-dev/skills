---
name: pr-risk
description: Use when asked how risky a PR or branch is to merge, or to assess merge risk for a reviewer. Review is read-only and posts nothing unless asked. Self-check, which may edit the branch, runs only when explicitly asked for.
argument-hint: "[PR number or URL | branch | --squash <sha>] [--self-check]"
---

# Assess merge risk

The question a reviewer actually has is not "is this code good" but "what happens if I merge it and I am wrong". This skill answers that in five dimensions, each with the evidence behind it and the cheapest action that would lower it.

Two modes:
- **Review** (default): someone else's PR, or yours before merging. Read-only: it changes nothing, and posts a PR comment only when the user asks. This is the only mode used when the skill is triggered by a plain question such as "how risky is this PR?".
- **Self-check**: only when the user or the calling workflow asks for it (`--self-check`, "self-check my branch"). An agent's own branch before it asks a human for review: apply the cheap risk-lowering actions, reassess, report the risk before and after.

## 0. Load the project overlay

If the repository has `.claude/aisoul/pr-risk.md`, read it first. Path and API lists it gives are added to the built-in ones; other values replace the default; anything it does not mention keeps the default. A template is at `${CLAUDE_PLUGIN_ROOT}/skills/pr-risk/overlay-template.md`.

| Key | Default |
|-----|---------|
| Base branch | `origin/HEAD`, else `origin/main`, else `main` |
| Sensitive paths | the built-in categories in `risk-facts.sh`: auth and access, money, secrets and security config, data and schema, infra and CI, dependencies |
| Excluded from code signals | nothing beyond prose: Markdown and plain-text files never produce signals |
| Error reporting | common APIs (`Sentry.*`, `captureException`, `reportError`, `logger.error`, ...) |
| Feature flags | common APIs (`isFeatureEnabled`, `useFeature`, `useFlag`, ...) |
| Rollback | revert the merge commit and release as usual; nothing else assumed |
| Runtime | a deployed service whose errors can be reported |
| Verification evidence | CI check runs for the head, the PR description's Evidence section, output attached to the PR |

## 1. Gather

Facts first, judgement after.

1. **The change and its range.**
   - Open PR: `gh pr view <n> --json title,body,baseRefName,headRefName,headRefOid,files,url` and `gh pr diff <n>`. If `gh pr` fails (GraphQL unavailable), use REST: `gh api repos/<owner>/<repo>/pulls/<n>` and `.../pulls/<n>/files`.
   - Merged PR: the base branch has moved past it, so the default range is empty. Use the PR's own base and head, `PR_BASE=<base.sha>` with `<head.sha>` from the pulls API, or its merge commit with `--squash <merge sha>` (compared with the first parent, so it covers the whole PR).
   - Local branch: the branch against the base.
2. **Mechanical facts**, with the overlay's values loaded into the environment first:

   ```bash
   eval "$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/pr/overlay-env.sh" .claude/aisoul/pr-risk.md)"
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/pr/size.sh" <head>
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/pr/risk-facts.sh" <head>
   ```

   `risk-facts.sh` lists changed files, sensitive-path hits by category, and signals in the changed lines: swallowed errors, catch blocks that only log, error reporting added or removed, type and lint escapes, destructive data operations, feature flags, skipped, removed or deleted tests. It is grep, not judgement: every hit is a lead to read, not a finding. Both scripts exit 2 with a hint when the range is empty; never assess an empty range.
3. **Intent.** The PR description, the linked issue or ticket, the commit messages, and the spec when one exists: inside `pr-review`, the one its Spec source chose; on its own, the candidates from `bash "${CLAUDE_PLUGIN_ROOT}/scripts/pr/spec-find.sh" <head>`, after also loading `.claude/aisoul/pr-review.md` for its spec folders and ticket pattern. Scope fit is judged against the spec first. If nothing states intent, Scope fit is judged on what is there and says so.
4. **Proof.** CI results for the head commit (`gh api repos/<owner>/<repo>/commits/<sha>/check-runs`; a 422 or an empty list means the head is not pushed or CI has not run, which goes under **Not assessed**), the description's Evidence section and **Not checked:** line if it was written with `/aisoul:pr-describe`, and any output attached to the PR. A result the description reports counts when CI or attached output shows it, or when you reproduce it cheaply; otherwise it is "reported, not reproduced" and cannot carry a ✅ alone.
5. **Read the code** behind every lead and every sensitive path. A finding cites `file:line`.

## 2. Judge five dimensions

Each gets one verdict: ✅ low risk, 👀 some risk, ⚠️ high risk, or ❓ cannot tell from what is available. ❓ is not a pass: it counts as 👀 in the rules and its bullet says what is missing.

**Scope fit**: does the change do what it says and only that?
- ✅ every change traces to the stated intent, or is named in the description. Formatting-only or wording-only extras of a few lines do not count against it.
- 👀 unannounced drive-by changes with behaviour, or behaviour assumptions the description does not mention.
- ⚠️ the change contradicts its intent, or a large part of the diff has no stated reason.

**Blast radius**: if it is wrong, how much breaks, for whom?
- ✅ one feature, one screen or one internal path; or a sensitive path touched only to add a check, a test or a CI step.
- 👀 shared code used by several features (composables, stores, utils, layouts, API clients, a CLI or script many users run), a public interface or contract, or a sensitive path changed without widening access or weakening checks.
- ⚠️ access widened or a check weakened, money or personal data paths changed, a schema or contract change consumers depend on, global config (CSP, CORS, build, auth middleware), or a dependency major bump.

**Verification**: is it proven to work, at the level the change needs?
- ✅ the behaviour that changed has proof matching its kind: before/after captures for UI, a test that failed before the fix for a bug, numbers for performance, the literal shape for a contract, real output for a script. Edge cases are tested or named as untested.
- 👀 tests exist but do not reach the changed behaviour, the proof covers the happy path only, or key results are reported but not reproduced.
- ⚠️ user-visible or sensitive behaviour changed with no proof, tests were skipped or deleted to pass, or the description claims checks nobody could see run.

**Reversibility**: if it goes wrong after merge, how expensive is undoing it?
- ✅ a revert, released the project's usual way (the overlay's Rollback), restores the previous behaviour for everyone (two-way door), or the change sits behind a flag that can be turned off.
- 👀 a revert works but leaves residue beyond the usual release path: data written in a new shape, caches, sent emails, a deploy coordinated with another service.
- ⚠️ one-way door: destructive migration, data deleted or rewritten, an external contract published, a secret rotated, anything a revert does not bring back.

**Observability**: if it breaks where it runs, does someone find out before a user has to report it?
- ✅ failures in the changed flow reach the project's error reporting; or, for code that runs on users' machines (CLIs, scripts, plugins, skills), failures are loud: non-zero exit, a clear message; or the change cannot fail at runtime (docs, types, tests only).
- 👀 failures are logged but nothing alerts on them, a fallback hides them without recording them, or a script can print a plausible but wrong result without warning.
- ⚠️ errors are swallowed, reporting was removed, or a critical flow fails silently.

## 3. Overall risk

Rules, applied in order; the first that fires decides, and the headline names it.

1. **High** if Reversibility is ⚠️ and Blast radius is not ✅.
2. **High** if Blast radius is ⚠️ and Verification is not ✅.
3. **High** if two or more dimensions are ⚠️.
4. **Low** if no dimension is ⚠️, at most one is 👀 or ❓, and that one is neither Verification nor Reversibility.
5. **Medium** otherwise.

Rules, not an average: a one-way door on shared code is high risk however good the tests are, and an average would hide it.

## 4. Output

```markdown
**Merge risk: medium**: <one sentence on why, in plain words> (rule 5)

**Scope fit** ✅
**Blast radius** 👀
- <gap, with `path:line` or a link>
- Lower it: <the cheapest action>
**Verification** ⚠️
- <gap>
- Lower it: <action>
**Reversibility** ✅
**Observability** 👀
- <gap>
- Lower it: <action>

**Not assessed:** <what could not be read or run, and why>
```

- The five dimensions, in this order. ✅ gets no bullets unless something is worth knowing.
- Every dimension that is not ✅ gets exactly one **Lower it:**: a concrete action (add a test for X, put Y behind a flag, report errors from Z), not advice. When the risk is inherent and nothing cheap lowers it, write `Lower it: none, <why>` rather than invent an action.
- Up to 250 words in total. Cite code as `path:line`; in a PR comment, as links to the head commit.
- No bare `#<number>` outside code (GitHub autolinks it), no em dashes.

Check it before handing over:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/pr/risk-check.sh" <file>
```

## 5. Deliver

**Review**: print the assessment in the chat. Post it as a PR comment (`gh pr comment <n> --body-file <file>`, or `gh api repos/<owner>/<repo>/issues/<n>/comments -F body=@<file>`) only when the user asks; posting is visible to others.

**Self-check**:
1. Assess as above. Keep this as the starting risk.
2. Apply the **Lower it** actions that are both cheap (about a quarter of an hour, no new dependency, no design decision) and in scope (they touch only files the branch already changes, or tests for them). Commit them separately.
3. Gather and judge again. The headline becomes `**Merge risk: low (was medium)**: ... (rule 4)`, and a line `**Done:** <actions applied>` goes right under it.
4. Actions not applied go to the PR description's Review notes. When the description is written with `/aisoul:pr-describe`, run that after the self-check, so its Evidence includes what the self-check added.

## What this is not

Not a code review: style, naming and structure are out of scope unless they change one of the five dimensions. Not a gate: the verdict informs the person merging; it does not decide for them.
