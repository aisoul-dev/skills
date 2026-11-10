---
name: pr-review
description: Use when the user asks to review a branch or PR against the base, or asks whether it can be approved or merged ("review this branch", "can I approve this?", "can this be merged?"), including a re-review after new commits. Also for a self-review of the user's own branch before opening a PR ("check my branch before the PR", "what should I fix first?").
argument-hint: "[PR number | branch] [--own]"
---

# Review a branch for approval

The reply is a **decision a reviewer can act on**: a verdict, every finding with the reason it got its status, the merge risk, and comments ready to paste into the PR. A bug hunt alone does not give that. This skill adds what it lacks:

- whether the change is the one that was asked for, against its spec
- context checks that change severity
- mechanical gates
- the merge risk, from `/aisoul:pr-risk`
- a verdict

A finding judged in isolation gets over-rated. Each context check in Step 3 exists because it once turned a "blocker" into a non-issue. Run all of them before assigning any status.

## 0. Load the project overlay

If the repository has `.claude/aisoul/pr-review.md`, read it first. Its values replace the defaults below; anything it does not mention keeps the default. A template is at `${CLAUDE_PLUGIN_ROOT}/skills/pr-review/overlay-template.md`.

| Key | Default |
|-----|---------|
| Base | `origin/HEAD`, else `origin/main`, else `main` |
| Bug hunt | Claude Code's built-in `/code-review` at `xhigh` against the base; otherwise Step 2's own hunt |
| Standards review | a standards and spec review skill, if one is installed (for example `code-review` from `mattpocock/skills`); none otherwise |
| Spec folders | `docs/specs`, `specs`, `docs/superpowers/specs`, `.scratch`, `docs` |
| Ticket pattern | `[A-Z][A-Z0-9]*-[0-9]+` |
| Gates | the first of: CI config run locally, the tests section of `CLAUDE.md`, `AGENTS.md` or `CONTRIBUTING.md`, the build files (Step 4) |
| Ratchets | none. A ratchet is a pattern a PR must not add more of than it removes, e.g. explicit `any` |
| Constraints | the "must" and "never" rules in the repo's `CLAUDE.md` or `AGENTS.md`, and the Constraints or Runtime sections of any overlay in `.claude/aisoul/` |
| Feature flags | none known |
| Contract source | none: API claims are marked _inferred_ |
| Own-branch handoff | a task list for the next implementation run |
| Comment language | English |
| Disclosure | none; when set, the review summary ends with it |

Scripts are in `${CLAUDE_PLUGIN_ROOT}/scripts/pr/`. All take `PR_BASE` and read the overlay's values from the environment. Each shell call starts fresh, so load the overlay at the start of every call that runs a script, and pass the same `PR_BASE` to `pr-risk`, so every script compares the same range:

```bash
eval "$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/pr/overlay-env.sh" .claude/aisoul/pr-review.md)"
```

## Step 1: Scope

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/pr/scope.sh" [<branch>]
```

It fetches (set `PR_NO_FETCH=1` when the repository must not be touched), then prints commits ahead and behind, whether merging the base is clean, the commit list and the diffstat. Compare against the remote base, not a local branch, which may be stale. If the user named a branch or PR, review that one, checked out or by ref.

Act on it before the bug hunt:

- **Up to date**: continue.
- **Behind, clean merge**: continue, and add the merge condition "update from the base" to the verdict. The gates run on the branch without the base's latest commits, so they do not prove the merged result.
- **Behind with conflicts** (exit 3): stop before Step 2. Say the branch must be updated from the base first, with the count and the conflicting files. Resolving the conflicts changes the code under review, so a review now is spent on a diff that will not be merged.

In own-branch mode, tell the user to update from the base. Do not merge it yourself.

## Step 2: Find

Findings come from up to three sources, each with its own source name in the ledger. Every subagent brief, here and in later steps, includes the line "Do not invoke any review skill (code-review, pr-review, pr-risk) unless this brief is to run that one skill": a subagent that starts its own review spawns more agents and duplicates the work.

**Bug hunt** (source _bug hunt_, whoever ran it). By default, Claude Code's built-in `/code-review` with args `xhigh <base>`, unless the user named another level. Its output varies a lot from run to run: the same branch can return 15 findings once and 1 the next time.

**Make sure it is the bug hunt.** Plugins can ship a skill with the same name. `code-review` from `mattpocock/skills`, for one, reviews standards and spec and does not hunt bugs, and it does not take a level. If several bug hunts answer to `code-review`, ask which to run, or use the overlay's choice. If the only one is not a bug hunt, run the own hunt below, and run that skill as the standards review if it is one. Never guess. Say under _Not checked_ which hunt ran when it was not the built-in one.

**Standards review** (source _standards_), when the overlay names one or one is installed: run it with the base as its fixed point. Keep its Standards findings; its Spec findings, if any, feed the Spec source below instead of being added twice. If the overlay names one that is not installed, or none runs, say so under _Not checked_. A breach of a documented standard can become an architectural Blocker in Step 5; a code smell is always Non-blocking.

Without a `code-review` skill, hunt yourself: read the full diff, then for each changed function the callers and the tests that reach it, and look for broken flows, unhandled states and errors, and wrong assumptions about inputs. Use subagents per area for a large diff.

**Spec** (source _spec_): is it the change that was asked for?

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/pr/spec-find.sh" [<branch>]
```

It lists ticket and issue references in the branch name and commits, and candidate spec files: ones the branch changes, ones naming a ticket, ones sharing words with the branch name (exit 1: no candidates; exit 2: empty range). Then use the first source that exists: a path the user passed, a spec file the branch changes, a ticket or issue the references point to (read it if you can reach it), another candidate that really is this branch's spec, or ask the user. With none, write "no spec available" under _Not checked_ and invent no requirements.

Compare the spec with the diff, in a subagent for a large change. Number its requirements if they are not (R1, R2, ...) and judge each: met, partial, missing or wrong. Each gap becomes a finding that quotes the spec line:

- **missing or partial**: a requirement the diff does not implement, or only part of it
- **wrong**: implemented, but not as the spec says
- **not asked for**: behaviour no requirement covers. Non-blocking; a large unasked part is also a `pr-risk` Scope fit gap

Spec findings go through Step 3 and Step 5 like the others: the proof for a Blocker is the quoted spec line plus the input that shows the gap.

**Anything you notice yourself in Steps 3 and 4 also goes into the ledger**: a label mismatch, a missing test, a lint warning on a line the branch added. Its source is _own_, even if the bug hunt did not report it. An observation mentioned only in passing slips through.

## Step 3: Context checks (for each finding, before assigning a status)

**Verify first.** Open each finding's `path:line` and confirm the code does what the finding claims. A finding you cannot confirm in the code cannot be a Blocker: give it _Non-blocking (unconfirmed)_ and say what you could not confirm.

**Stacked follow-up: run this before the others below.**

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/pr/stacked.sh" [<branch>] -- <file> ...
```

It lists remote branches built on this branch's commits, each with its own changes counted from the merge base (not `HEAD..B`: if this branch merged the base after B forked, that range is mostly the merge in reverse), its merge state with this branch and with the base, how far it is behind the base, and its diff for the files you name. If a stacked branch B fixes the finding, the status is _Handled in B_, and the verdict gets the merge condition "merge together with B, or right before it", with B's merge states and how far behind it is.

| Check | How | If it holds |
|-------|-----|-------------|
| **Pre-existing** | `git show <base>:<file>` already has the defect | _Non-blocking (pre-existing)_: suggest a ticket. If this branch newly exposes the path, it counts as introduced only if the valid-input main flow breaks (Step 5) |
| **Reachable on the base?** | For a removed or changed page, route or component: `git grep -n '<route or name>' <base> -- <app dir>` | If nothing on the base links to it, removing it is not a user-facing regression |
| **Feature flag** | Is the surface behind one of the overlay's flags? Check what the flag actually hides: an entry point, or the whole surface | A flag that only hides an entry point lowers discoverability, not reachability. Never use a flag to downgrade a correctness finding |
| **Contract** | If the finding depends on API behaviour: read the contract source from the overlay (a backend checkout, an OpenAPI file, a schema) at its main branch, the DTO and the test that covers the input | Cite the file. Mark each claim _tested_ (a test covers exactly this input) or _inferred_ (read from code or constraints). Never infer the contract from the calling side's own types |
| **Test expectation changed** | `bash "${CLAUDE_PLUGIN_ROOT}/scripts/pr/changed-expects.sh"` lists assertions the branch changed or removed, not just added | Own row. Does the new expectation match the spec or acceptance criteria? A legitimate behaviour change is fine; one that only makes the branch pass is a Blocker |
| **Duplication** | For each function, module, helper or component the branch adds, `git grep` the base for the same logic: similar names, the same API call, the same transform. Also compare the branch's new code against itself | Own row, Non-blocking. Name every copy with `path:line` and where the shared version should live. A Blocker only under a constraint in Step 5, e.g. an API call outside the layer the project allows |

**If the checks give different answers for different parts of one finding, split it into rows `1a`, `1b`, ...** with one status each. For example: the error case is handled in B, the "only way in" claim is disproved, and the silent failure is pre-existing. Each row gets its own status and, if needed, its own comment.

## Step 4: Mechanical gates and merge risk

Take the gates from the first source that has them, and name the source in the Gates part of the reply:

1. **The overlay's gates.**
2. **CI config** (`.github/workflows/`, `.gitlab-ci.yml`, ...): run the same commands locally, as far as they run without CI's secrets or services.
3. **The project's own instructions**: a tests or checks section in `CLAUDE.md`, `AGENTS.md` or `CONTRIBUTING.md`. When it says to run what a change touches and lists commands per area, run the ones this diff touches, not every suite.
4. **The build files**, from this table. A repo with several build files (a Go service next to a JS UI) takes the rows of the areas the diff touches.

| Build file | Gates |
|------------|-------|
| `package.json` with a lockfile | The package manager from the lockfile. The `typecheck`, `lint` and `test` scripts in `package.json`, or `tsc --noEmit` when there is a `tsconfig.json` and no `typecheck` script. eslint on changed `.ts/.tsx/.js/.vue` files only with an eslint config present; prettier only with a prettier config present |
| `Makefile` or `justfile` | targets named `test`, `check`, `lint` |
| `pyproject.toml`, `tox.ini` or `noxfile.py` | `pytest`; `ruff`, `flake8` or `mypy` only when configured |
| `go.mod` | `go vet ./...`, `go test ./...` |
| `Cargo.toml` | `cargo clippy`, `cargo test` |
| `Gemfile` | `rake` or `rspec`; `rubocop` only with `.rubocop.yml` |
| `composer.json` | its `test` script, else `phpunit` |

Rules for every source:

- Run a linter or formatter only when the project has its config. No config, no gate, and nothing about it under _Not checked_.
- Lint and format only the changed files, and never pass an empty list, which lints the whole repo:

```bash
git diff --name-only --diff-filter=d <base>...HEAD | grep -E '\.(ts|tsx|js|vue)$' | xargs -r <pm> exec eslint
git diff --name-only --diff-filter=d <base>...HEAD | xargs -r <pm> exec prettier --check --ignore-unknown
```

Use `xargs`, not a shell variable: zsh does not word-split variables.

- When the full suite is long (a root script that chains many suites), run the part the diff touches and say which part. A gate not run goes under _Not checked_.

For each ratchet in the overlay:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/pr/ratchet.sh" '<pattern>' -- <pathspec>...
```

It prints added, removed and net, and exits 0 (net down), 1 (even) or 2 (net up).

Report each gate's own counts (files, tests, errors); when a runner prints only a pass line, quote that line. A gate is red only on errors, test failures, conflicts, or a ratchet the branch moves the wrong way. A warning about the whole repository (a validator, an audit) counts only if the base does not show it too; otherwise it is _Non-blocking (pre-existing)_. A ratchet that stays even is one Non-blocking row with source _own_, when the overlay says every PR should move it. Each line the branch added that gets lint warnings becomes one Non-blocking row, source _own_, listing every rule that fires on it.

**Merge risk.** Run `/aisoul:pr-risk` in review mode on the same range (the same `PR_BASE`) and with the spec chosen in Step 2, reusing the gates' results as proof. Its headline goes into the verdict, its whole assessment into the reply (Step 6, part 3). Each ⚠️ dimension also becomes a ledger row with source _pr-risk_, Non-blocking unless it meets Step 5. The verdict is about defects and the risk about consequences: a high risk with no Blocker still gives **✅ Approve with comments**, and the summary's first bullet names the risk.

End-to-end runs, browser checks and CI are not run by default; read CI's state for the pushed head if `gh` is available. Anything not run goes under _Not checked_.

## Step 5: Triage

A finding is a **Blocker** only if all four hold:

1. This branch introduced it, or made it newly reachable.
2. No stacked branch that merges with it handles it.
3. It is one of:
   - a broken flow: the main flow **fails with valid input** for users who can reach it. A silent failure on invalid input is Non-blocking and needs a ticket
   - data loss
   - a security issue
   - a red gate
   - **architectural**: a violated overlay constraint or documented standard, or logic placed at a layer the next ticket must undo
   - **spec**: a requirement missing, partial or implemented wrongly, when the spec makes it part of this change. Condition 1 then holds: this branch is the change that owed it
4. You can show it fails: a failing-test sketch or an exact repro (input, expected, actual). For an architectural finding, the proof is the violated constraint or the ticket that has to undo it. A red gate is its own proof. Without proof, the finding is Non-blocking, whatever its category.

Everything else is **Non-blocking**. A finding the checks proved wrong is **Dismissed**, with its reason. If the bug hunt reported findings through `ReportFindings`, report them again with `outcome: no_change_needed` on the Dismissed and Handled ones.

Verdict:

- any Blocker: **❌ Request changes**
- only Non-blocking findings or merge conditions: **✅ Approve with comments**
- nothing: **✅ Approve**

## Step 6: The reply, in this order

Prose and the ledger in the user's language; comment blocks in the overlay's comment language, because they go to the PR.

1. **Verdict**: one line with the verdict and one sentence why, then the merge risk headline from `pr-risk`. Directly under it, the merge conditions, or `Merge conditions: none`. A condition is something that must happen with or before this merge: an update from the base, merging together with a stacked branch that handles a finding. A stacked branch that handles nothing sets no condition.
2. **Gates**: one line per gate with its result and counts, then a _Not checked:_ line.
3. **Merge risk**: the `pr-risk` assessment as it came out, in its own format.
4. **Ledger, every finding**: first one line for the spec, `Spec: <path or ticket>: R1 met, R2 partial, ...` or `Spec: none available`; then a table `#` | source (bug hunt / _standards_ / _spec_ / _own_ / _pr-risk_) | finding | `path:line` | status (Blocker / Non-blocking / Non-blocking (pre-existing) / Non-blocking (unconfirmed) / Handled in X / Dismissed) | why.
   - Every bug-hunt, standards and spec finding appears in at least one row, whole or split.
   - Every _own_ observation from Steps 3 and 4 has its own row.
   - The table is required even if the bug hunt says not to repeat its findings: the reviewer re-checks the triage from it.
5. **Paste-ready comments**: Blockers first, then Non-blocking. Dismissed, Handled and pre-existing findings get none: pre-existing ones go to the summary as tickets to file. Each comment has:
   - a heading `### [n](<link>)`, linked to where the fix goes, which can be a different file from the finding's `path:line`; when the fix belongs in a file that does not exist yet, link the code it would replace;
   - directly under it, the placement line, so the reviewer does not have to open the link to know where the comment goes;
   - both from `bash "${CLAUDE_PLUGIN_ROOT}/scripts/pr/comment-link.sh" <path> <line> [<end line>] [<branch>]`, which links to the pushed commit (a local-only sha gives a 404), adds `?plain=1` for Markdown, and picks the placement form from GitHub's diff view: a line or lines in the diff, a file-level comment, or a general PR comment;
   - a fenced `markdown` block with the comment, starting `**Blocking:**` or `**Non-blocking:**`: the defect, a concrete scenario and the suggested fix. A Blocking comment also gives the proof from Step 5. A duplication comment lists every copy and where the shared version should live. Fence code inside it with `~~~`. Refer to other findings by their content, never as `#n`: GitHub turns `#12` into a link to issue or PR 12. This applies to the summary too.
6. **Review summary**: one fenced `markdown` block for the review body, 2 to 5 bullets on blockers, conditions, the merge risk and tickets to file for pre-existing findings. The overlay's disclosure line, if any, at the end.

## Own-branch mode

When the user asks to check their own branch before opening a PR (`--own`). The goal is a fix list, not a review to post.

Run Steps 1 to 5 unchanged; replace Step 6 with:

1. **Verdict, gates and merge risk**: as Step 6, parts 1 to 3.
2. **Ledger**: as Step 6, part 4.
3. **Fix list** for the overlay's handoff: Blockers only, one task each: `path:line`, what is wrong, and the failing test to write first, so the fix starts from a red test.
4. **Extract**: every Duplication row with its copies and the target location. Cheaper now than in a follow-up ticket.
5. **Lower the risk**: the `pr-risk` **Lower it** actions that are cheap and in the branch's scope.
6. **Non-blocking**: at most 5 lines, most important first. Not for the fix list.

No paste-ready comments and no review summary.

## Common mistakes

| Mistake | What goes wrong |
|---------|-----------------|
| Rating a finding before the stacked-branch check | A deliberate placeholder in a stack gets reported as the top blocker |
| Diffing a stacked branch as `HEAD..B` | Real changes get buried under the reversed merge of the base |
| Mentioning an own observation only in the notes | The reviewer never sees it: the ledger holds only what is written into it |
| Giving one finding a compound status | The parts cannot be re-checked separately, and a comment has nowhere to go |
| Writing `#n` inside a paste-ready block | GitHub links it to an unrelated issue or PR with that number |
| Leaving the file and line only in the heading URL | The reviewer has to open each link to learn where the comment goes |
| Calling a removed page a regression | Nothing on the base linked to it, so it was only reachable by typing the URL |
| Replying with findings and no verdict | The user has to ask "so can I approve?" |
| Leaving Dismissed findings out of the ledger | A wrong dismissal slips through silently |
| Running the gates only when asked | The verdict ships without the facts it rests on |
| Writing comment blocks in the chat language | They get pasted into a PR the team reads in another language |
| Making a Blocker you cannot reproduce | Noise from a high-variance bug hunt blocks the merge |
| Triaging a finding before opening its `path:line` | A plausible finding gets rated as fact |
| Accepting a changed assertion as a routine update | A test bent to fit the code hides the bug it was written to catch |
| Bug hunt on a branch that conflicts with the base | The most expensive step reviews code the conflict resolution will change |
| Leaving a duplicate for later | The copies drift apart, and the next fix lands in only one of them |
| Approving without the merge risk | A correct change that is a one-way door ships as if it were cheap to undo |
| Trusting the name `code-review` | A plugin skill with that name runs instead of the bug hunt, and nobody notices the bugs were never looked for |
| Reviewing without the spec | Well-built code that does the wrong thing gets approved |
| Inventing requirements when no spec exists | The review argues with a spec only the reviewer imagined |
