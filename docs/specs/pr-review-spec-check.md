# Spec: spec and standards as review inputs (aisoul 1.4.0)

## Problem

`pr-review` checks whether a change is built right and safe to merge, but never whether it is the change that was asked for. Its default bug hunt calls a skill named `code-review`, and a plugin skill with that name (Matt Pocock's, which reviews standards and spec, not bugs) can silently replace the built-in one.

## Requirements

- R1. The bug hunt calls Claude Code's built-in `/code-review`. When more than one skill answers to that name, or the one available is not a bug hunt, `pr-review` asks which to use instead of guessing.
- R2. A new context check, **Spec**, finds the originating spec in this order: a path the user passed, a spec file the branch itself adds or changes, ticket or issue references in the commit messages and branch name, a spec file in the spec folders matching the branch or ticket, then asks the user. With no spec, the check reports "no spec available" and invents no requirements.
- R3. Spec findings are of three kinds: missing or partial requirements, behaviour nobody asked for, requirements implemented wrongly. Each quotes the spec line. Missing and wrong can be Blockers under the existing triage rules; unasked behaviour is Non-blocking.
- R4. When a standards review skill is installed, its findings enter the ledger with the source `standards`, after the same verify-first check as every other finding. A breach of a documented standard can be an architectural Blocker; a code smell is always Non-blocking.
- R5. Every subagent brief in `pr-review` says not to invoke review skills, so a subagent never starts another review.
- R6. `scripts/pr/spec-find.sh` lists the references and candidate spec files mechanically, with tests. The overlay can set the spec folders and the ticket pattern.
- R7. `pr-risk` judges Scope fit against the spec when one is found.

## Out of scope

- Fetching tickets from an issue tracker; the user or the agent reads them.
- Changing the verdict rules or the merge-risk rules.
