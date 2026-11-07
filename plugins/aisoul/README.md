# aisoul

Grygorii Liashenko's skill set for Claude Code, tuned for Nuxt / Vue / TypeScript work. Every skill is invoked as `/aisoul:<skill>`.

## Skills

| Skill | Group | What it does |
|-------|-------|--------------|
| `/aisoul:untangle-audit [path or concern]` | untangle | Read-only. Measures change locality and patches, finds causes, writes a decision log of PR-sized fixes to `docs/untangle/`. Changes no code. |
| `/aisoul:untangle-fix <log path> <fix id>` | untangle | Applies one fix from the log as one branch and one PR: re-verify, pin behavior with tests, implement, separate review, update the log. |
| `/aisoul:pr-describe [branch \| --squash <sha>]` | pr | Writes a short, evidence-first PR description whose length follows the diff. Also triggers when you ask for a PR description. |
| `/aisoul:pr-review [PR \| branch] [--own]` | pr | Reviews a branch for approval: scope, bug hunt, context checks, gates, merge risk, triage with proof, a ledger of every finding and paste-ready comments. `--own` returns a fix list instead. |
| `/aisoul:pr-risk [PR \| branch \| --squash <sha>]` | pr | Assesses merge risk in five dimensions with evidence and one risk-lowering action each. Read-only; posts a PR comment only when asked. Also triggers when you ask how risky a PR is. |

Skills are named `<group>-<action>` so related ones sort together in `/` completion. Heavy workflows run only when you call them (`disable-model-invocation: true`).

## Project overlays

A skill that needs project facts (where files go, what CI already checks, which environment is "real") reads them from `.claude/aisoul/<skill>.md` in the project, if it exists, and falls back to its defaults otherwise. Project specifics stay in the project; this plugin stays general. Each such skill ships an `overlay-template.md` next to its `SKILL.md`.

## pr

`/aisoul:pr-describe` treats a PR description as evidence a reviewer can check, ordered so the reader can stop at any point.

- **Size follows the diff.** Up to ~50 changed lines (tests count, `docs/` and lockfiles do not): title, one paragraph, the evidence, a **Not checked:** line, ~150 words, no headings. Larger: `What`, an optional `Why <the hard part>`, `Evidence`, `Review notes`, `Follow-ups`, ~400 words outside `<details>`.
- **Evidence by change type**: captures for UI, the failing test for a bug fix, a table for performance, real output for tooling, the literal shape for API contracts.
- **Nothing the Checks tab already shows**, unless it is what the change is about.
- **Long proof goes in `<details>`**, so it stays in the PR without costing the reader.

Scripts in `scripts/pr/`:

| Script | What it does |
|--------|--------------|
| `size.sh [branch \| --squash <sha>]` | changed lines without excluded paths, and the shape (`PR_BASE`, `PR_EXCLUDE`, `PR_SMALL_MAX`) |
| `check.sh <file> <small\|large>` | word budget, Not checked line, no headings in small, no bare `#<number>` outside code, no em dash |

Overlay: copy `skills/pr-describe/overlay-template.md` to `.claude/aisoul/pr-describe.md` in the project and fill in location, title format, excluded paths, what the Checks tab shows, the live environment, screenshot widths, an optional disclosure line and an optional house example.

`/aisoul:pr-risk` answers the reviewer's real question: what happens if this is merged and it is wrong.

| Dimension | Asks |
|-----------|------|
| Scope fit | does the change do what it says, and only that? |
| Blast radius | if it is wrong, how much breaks, for whom? Sensitive paths raise it |
| Verification | is it proven at the level the change needs? |
| Reversibility | does a revert undo it, or is it a one-way door? |
| Observability | if it breaks in production, does someone find out first? |

Overall risk comes from explicit rules (a one-way door on anything but an isolated change is high; a large blast radius without proof is high; two high dimensions are high), not an average that would hide them. `scripts/pr/risk-facts.sh` collects the mechanical facts first: sensitive paths by category and signals in the changed lines. Overlay: `skills/pr-risk/overlay-template.md` to `.claude/aisoul/pr-risk.md` (extra sensitive paths, error reporting and flag APIs, how rollback works).

Use it as a review aid (chat, or a PR comment when asked) or as a self-check before asking for review: pair it with `pr-describe`, whose Evidence section is what Verification reads.

`/aisoul:pr-review` turns a review into a decision. Findings from a bug hunt are not rated until context checks have run on them: verified in the code, checked against stacked branches, against the base (pre-existing, reachable), against feature flags and the contract source, against changed test expectations and duplication. A finding is a Blocker only if this branch introduced it, nothing stacked handles it, it is a broken valid-input flow, data loss, a security issue, a red gate or an architectural violation, and it can be shown to fail. The reply is a verdict with the merge risk from `pr-risk`, gate results, a ledger of every finding with its status, and paste-ready comments whose links and placement lines come from `comment-link.sh`.

| Script | What it does |
|--------|--------------|
| `scope.sh [branch]` | ahead/behind the remote base, merge state and conflicting files (exit 3: stop), commits, diffstat |
| `stacked.sh [branch] [-- paths]` | branches built on this one, counted from the merge base, with merge states and their diff for given paths |
| `ratchet.sh '<ERE>' [branch] [-- pathspec]` | a pattern added vs removed; exit 0 down, 1 even, 2 up |
| `changed-expects.sh [branch]` | test assertions the branch changed or removed, not just added |
| `comment-link.sh <path> <line> [end] [branch]` | link at the pushed commit and the placement line GitHub will accept |

Overlay: `skills/pr-review/overlay-template.md` to `.claude/aisoul/pr-review.md`: gates, ratchets, constraints, feature flags, where the API contract lives, the own-branch handoff, comment language and a disclosure line.

## untangle

Measure how expensive change is in a codebase, log the causes, and fix them one small PR at a time.

### Finding kinds

| ID | Kind | Question |
|----|------|----------|
| C | Change coupling | does one change silently require edits elsewhere? |
| D | Dependency direction | does stable code depend on more volatile code? |
| M | Shallow modules | does the interface cost as much as it saves? |
| W | Dead weight | does it exist without a current reason? |
| P | Patches | is this code hiding a gap in the design? |

Headline metrics: **change locality** (median and p90 files per commit) and **patch count**.

### Scripts

`scripts/untangle/` holds the measurements the audit runs. They also work standalone from any repo root:

```bash
bash plugins/aisoul/scripts/untangle/measure.sh                  # all measurements
bash plugins/aisoul/scripts/untangle/measure.sh app/features/x   # scoped
UNTANGLE_SKIP_NET=1 bash plugins/aisoul/scripts/untangle/measure.sh   # git and grep only
```

| Script | Needs | Output in `$UNTANGLE_OUT` (default `/tmp/untangle`) |
|--------|-------|------|
| `locality.sh` | git | `locality.txt` |
| `churn.sh` | git | `churn.txt` |
| `cochange.sh` | git | `cochange.txt` |
| `patches.sh` | ripgrep or grep | `patches.txt` + counts |
| `deps.sh` | pnpm or npx (downloads dependency-cruiser) | `depcruise.txt` |
| `deadweight.sh` | pnpm or npx (downloads knip) | `knip.txt` |
| `surface.sh` | `vue-tsc` in the project | `surface/*.d.ts` |

Env: `UNTANGLE_SINCE` (default `6 months ago`), `UNTANGLE_OUT`, `UNTANGLE_TOP`, `UNTANGLE_MAX_FILES` (co-change skips bigger commits, default 25), `UNTANGLE_APP_PREFIX` (`app/` for Nuxt 4, empty for Nuxt 3), `UNTANGLE_TSCONFIG`.

Nothing is installed into the audited project and no config is written there.

## Credits

- **untangle**: inspired by [caldoai/skills `untangle-codebase`](https://github.com/caldoai/skills) (MIT). The taxonomy, metrics, scripts and workflow here are independent. Background reading is listed at the end of the audit skill.
- **pr-describe**: ideas taken from Hugo RCD's [What my pull requests look like now](https://hugorcd.com/writing/what-my-pull-requests-look-like-now): evidence chosen by change type, an order the reader can stop at, "before" from the base branch, demo data only, one line on what was not checked. The size rule, word budgets, scripts and overlay are ours.
- **pr-review**: generalised from the author's own project review skill; every project-specific value moved to the overlay.
- **pr-risk**: inspired by Warp's [`merge-risk`](https://github.com/warpdotdev/common-skills) (MIT), which credits Matt Pocock's `pr` skill. The idea of rating alignment, impact, verification, rollback cost and error detection comes from there; the wording, the rule-based overall risk, the "Lower it" actions, the self-check mode, the facts script and the overlay are ours.
