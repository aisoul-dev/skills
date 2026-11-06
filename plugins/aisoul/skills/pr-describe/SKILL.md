---
name: pr-describe
description: Use when the user asks to write, refresh or shorten a pull request description or a PR comment. Produces a short, evidence-first description whose length follows the size of the diff.
argument-hint: "[branch | --squash <sha>]"
---

# Write a PR description

A PR description is **evidence a reviewer can check**, ordered so the reader can stop at any point and still know more than the title told them. The diff already says what changed. The description says what proves it works and what does not.

## 0. Load the project overlay

If the repository has `.claude/aisoul/pr-describe.md`, read it first. Its values replace the defaults below; anything it does not mention keeps the default. A template is at `${CLAUDE_PLUGIN_ROOT}/skills/pr-describe/overlay-template.md`.

| Key | Default |
|-----|---------|
| Location | `$(git rev-parse --git-dir)/pr-description/<branch>.md`, with `/` in the branch name replaced by `-`; inside `.git/`, so it is never committed. Create the directory if needed |
| Title | `# <title>`, or `# [<ticket>] <title>` when the branch name carries a ticket ID |
| Base branch | `origin/HEAD`, else `main` |
| Excluded paths | `docs/` and lockfiles (`pnpm-lock.yaml`, `package-lock.json`, `yarn.lock`, `bun.lock`, `bun.lockb`) |
| Checks tab | the jobs defined in the repository's CI config (`.github/workflows/` or equivalent). The PR may not be open yet, so read the config rather than guessing |
| Live environment | none named; apply the rule in "Live environment" generically |
| Screenshots | desktop width; add a narrow-width capture only when the change is about responsive layout |
| Disclosure | none |
| Example | the one at the end of this skill |

## Format and language

**Markdown, and always English**, whatever language the conversation is in: the description is a repository document read long after the chat is gone. Write the chat reply in the user's language; write the file in English.

Tables carry before/after numbers, fenced blocks carry literal output and request/response shapes, backticks mark every path, symbol and state value.

## 1. Size follows the diff

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/pr/size.sh" <branch>            # a branch, compared with the base
bash "${CLAUDE_PLUGIN_ROOT}/scripts/pr/size.sh" --squash <sha>      # a squash-merged commit
```

It counts changed lines without the excluded paths (`PR_EXCLUDE` and `PR_BASE` override them) and prints the shape. Tests count. The "~" below is for the writer; the scripts are exact: `size.sh` splits at 50 lines, `check.sh` enforces 150 and 400 words.

| Diff | Shape | Words outside `<details>` |
|------|-------|---------------------------|
| Up to ~50 changed lines | **small**: title, one paragraph (the reason included), the evidence, a line starting with **Not checked:**, a **Follow-ups:** line when there are any. No `##` headings | up to ~150 |
| Larger | **large**: the sections below | up to ~400 |

A table longer than ~8 rows, command output longer than ~10 lines, or a list of negative cases goes inside a `<details>` block: the opening `<details><summary>...</summary>` at the start of its own line, a blank line after it so the markdown inside renders, and `</details>` alone on the last line. The proof stays in the PR; the reader opens it on demand. Everything outside such blocks counts towards the budget, code blocks included.

## 2. The large document, in this order

1. **Title**, in the overlay's format. Write it fresh: what the PR does, in the imperative, under ~70 characters. The commit subject or the ticket title is a starting point, not the answer. The small shape uses the same rule.
2. **`## What`**: the problem, or for an addition the need (what a reader could not do before), in one paragraph in the reader's terms, with the headline number if there is one. Do not invent a motivation: if the conversation, the ticket and the commits give none, state what the change adds. Then what changed, grouped by area, in up to five bullets. Not a commit list. If the branch carries unrelated bodies of work, say so here and give each part its own `What` and `Evidence`.
3. **`## Why <the hard part>`**: only when a reviewer's first suggestion would be an approach that does not work, and you know that from the conversation, the ticket or the commit messages. Never infer a rejected approach. One section, named after the difficulty (`## Why the filter dialog needed a different fix`), one short paragraph.
4. **`## Evidence`**: chosen by change type (table below), holding only what the PR's Checks tab cannot show. End it with one line that starts with **Not checked:**: what was not run or not looked at, and why.
5. **`## Review notes`**: the single home for everything a reviewer might query: trade-offs, deviations from the ticket, limitations the merge ships with, work left for later. One or two sentences per bullet.
6. **`## Follow-ups`**: each with its ticket link or path, or "not filed yet". Omit if there are none.

The document ends with the last section. No trailer and no attribution line, unless the overlay sets a **Disclosure** line; then it is the first line under the title.

## 3. Evidence by change type

| Change | Evidence |
|--------|----------|
| UI | Before/after captures of the same element, same viewport and crop, at the overlay's screenshot widths. "Before" is the base branch or a deployed environment, never a stash or a revert of the branch. Look at every capture before using it. Seed or demo data only. Images are pasted into the PR on GitHub, not committed: in the file, leave `<!-- screenshot: <what it shows> -->` where each one goes |
| Bug fix | The same input before and after, and the test that failed against the old code: seen failing first, or proven by reverting the fix or by mutation, not assumed |
| Performance | A before/after table: what was measured, on what dataset size, how many runs |
| Tooling, lint, types, build, CI | The real command output before and after, exit code included, or a table of the numbers it printed. Not retyped |
| API contract handling | The literal request/response shape the code now handles |
| Refactor with no behaviour change | One line on what proves equivalence: identical build output, the same tests passing before and after |
| New capability (feature, command, script, endpoint) | One real invocation and what it returned, plus the test that pins it. A capture if it has UI |
| Documentation only | What a reader can now find or do, and that links and examples were followed and work |

A PR that matches several rows takes the evidence of each, briefly.

Name the two sides of a comparison by commit: the merge base (`git merge-base <base> <branch>`) against the branch head. For a squash-merged change, the sides are `<sha>^` and `<sha>`. When the branch fixes something it added itself, so the merge base has nothing to compare, the sides are the commit before the fix and the head.

**Live environment.** When the automated tests mock an external dependency (an API, a database, a payment provider), the defects that matter surface only when the branch runs against the real thing. When it was run that way, name the scenarios and the defects that run caught; a fix for something that would have shipped broken is labelled as such. When it was not run, the **Not checked** line says so: silence reads as "verified". The overlay names the environment. If the tests mock nothing, the rule does not apply and nothing is said.

**Checks tab.** Everything the overlay lists under Checks tab shows its own result on the PR. One of them appears in the description only when it is what the change is about (a lint-count PR, a CI change: then its before/after output is the evidence) or its result will differ from what Checks shows, such as a pre-existing failure, with the reason inline.

## Evidence beats adjectives

| Instead of | Write |
|------------|-------|
| "fixes the bug" | the input that failed, and the test that now fails without the fix |
| "cleans up the code" | what was removed, as a count, and what proves nothing else moved |
| "improves performance" | a before/after table with the dataset size that produced it |
| "handles the error" | the literal response shape it handles |

A measured claim gives the number. A claim reasoned from the code says "reasoned, not measured": reviewers weigh the two differently. A number someone else measured and you did not reproduce is attributed to them ("reported by the first review run"), not stated as yours.

## Refreshing an existing description

Update the file in place. Re-check every count, fold new work into the existing sections, add new follow-up tickets, and rerun `size.sh`: more commits can move the description into the large shape or past its word budget. A stale count tells a reviewer the document was not re-read.

## Before handing over

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/pr/check.sh" <file> <small|large>
```

It fails on any of these, and each is fixed before the description is shown to the user:

- **Word budget**: words outside `<details>` blocks (code blocks included; the title, table pipes and separator rows not), over the shape's budget, or a `<details>` block that is never closed.
- **No line starting with Not checked**, or, in a large description, one outside `## Evidence`; a large description without `## What` or `## Evidence`.
- **`##` headings in a small description.**
- **A bare `#<number>` outside code**, `<details>` included. In a PR body or comment, GitHub links it to that issue or PR in the same repository, so test-data names (`Test #13`), finding numbers and another repository's PR all point at unrelated PRs. Put data names in backticks, number findings `D1`, `D2`, and write "api-service PR 671" or a full URL. Markdown viewed as a file in the repository is not autolinked, which is why these slip through.
- **An em dash in your own prose.** Use a hyphen or an en dash. Pasted output in a code block stays verbatim, em dash or not.

What the script cannot check, check by reading: **every claim** has a number, a real output, or "reasoned, not measured", and nothing is invented: no number, result or run you did not see.

## Example (small diff)

```markdown
# [SHOP-412] Debounce the product search input

Typing in the product search fired one `GET /products?q=` per keystroke, so a
nine-letter query sent nine requests and the results list flickered as stale
responses arrived out of order. The input now waits 250 ms after the last
keystroke and aborts the previous request, in `useProductSearch.ts`.

|                          | `main` `3f9c2a1` | this branch `8d04e7b` |
| ------------------------ | ---------------- | --------------------- |
| Requests for "furniture" | 9                | 1                     |
| Out-of-order renders     | 3 of 5 runs      | 0 of 5 runs           |

`useProductSearch.spec.ts` asserts one request per pause; it failed on `main`
with 9 calls.

**Not checked:** slow-network throttling and the mobile layout. The change does
not touch rendering, so layout should not move (reasoned, not measured).
```
