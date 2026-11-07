# Changelog

Versions of the `aisoul` plugin, newest first. Semver: major for breaking changes to a skill's name, arguments or output format; minor for new skills or capabilities; patch for fixes and wording.

## 1.3.0 (2026-11-07)

### pr
- `pr-review`: a review that ends in a verdict a reviewer can act on. Scope against the remote base (stop on conflicts), a bug hunt, context checks before any status (verify in code, stacked branches, pre-existing, reachable on the base, feature flags, contract source, changed test expectations, duplication), mechanical gates and ratchets, the merge risk from `pr-risk`, triage with proof for every Blocker, a ledger of every finding, and paste-ready comments with links and placement lines. Own-branch mode returns a fix list instead. Project specifics in `.claude/aisoul/pr-review.md`.
- `scripts/pr/`: `scope.sh`, `stacked.sh`, `ratchet.sh`, `changed-expects.sh` (JS and shell assertions, `PR_ASSERT`), `comment-link.sh` (refuses unpushed branches, detached HEAD and lines past the end; warns when the local file differs).
- The full `pr-risk` assessment is part of the reply; pre-existing findings become tickets in the summary instead of PR comments; gates mirror CI by default.

### Repo
- This repository's own `.claude/aisoul/pr-review.md`: gates as in CI, constraints from the README rules.

## 1.2.0 (2026-11-07)

### pr
- `pr-risk`: merge-risk assessment in five dimensions (scope fit, blast radius, verification, reversibility, observability), each with evidence and one action that lowers it, and an overall low/medium/high decided by explicit rules rather than an average. Review mode prints to chat and posts only when asked; self-check mode applies the cheap actions and reports the risk before and after.
- `scripts/pr/risk-facts.sh`: changed files, sensitive paths by category, and signals in changed lines (swallowed errors, catch blocks that only log, removed error reporting, type escapes, skipped or deleted tests, destructive data operations, feature flags), with `PR_RISK_EXCLUDE` for fixtures. Says so when a range is empty. Overlay at `.claude/aisoul/pr-risk.md`.
- `scripts/pr/risk-check.sh`: checks an assessment against the output format.
- `pr-describe`: on an unpushed branch, local passes of CI jobs are not listed; Not checked says CI has not run.
- `scripts/pr/lib.sh`: one base resolution for every script (`PR_BASE`, else `origin/HEAD`, else `origin/main`, else `main`) and one empty-range hint. `overlay-env.sh` loads an overlay into the environment.
- `size.sh --squash` now compares with the first parent, so a merge commit counts its whole PR, and an empty range fails with a hint instead of reporting 0 lines.

### Repo
- This repository's own `.claude/aisoul/pr-risk.md`: plugin manifests and skill files are sensitive, scripts and tests are excluded from code signals, rollback is a forward version.

## 1.1.0 (2026-11-06)

### pr
- `pr-describe`: PR descriptions whose size follows the diff (small: ~150 words, no headings; large: What, Why, Evidence, Review notes, Follow-ups, ~400 words outside `<details>`), evidence chosen by change type, no repeats of the Checks tab, one **Not checked:** line, no trailer.
- Project overlay at `.claude/aisoul/pr-describe.md` for location, title format, excluded paths, Checks tab, live environment, screenshots, disclosure and a house example; template in `skills/pr-describe/overlay-template.md`.
- `scripts/pr/`: `size.sh` (shape from the diff, squash mode) and `check.sh` (word budget, Not checked, headings, bare `#<number>`, em dash).

### Repo
- Overlay convention `.claude/aisoul/<skill>.md` documented; CI runs `tests/pr.sh`, which also checks the skill's own example.

## 1.0.0 (2026-11-06)

### untangle
- `untangle-audit`: read-only structural audit with five finding kinds (C, D, M, W, P), change locality and patch count as headline metrics, "design it twice" redesign step, independent pass, decision log format.
- `untangle-fix`: one fix from the log per branch and PR, behavior pinned by tests first, separate review, log update.
- `scripts/untangle/`: `measure.sh`, `locality.sh`, `churn.sh`, `cochange.sh`, `patches.sh`, `deps.sh` (dependency-cruiser rules for Nuxt), `deadweight.sh` (knip), `surface.sh` (vue-tsc declarations).
