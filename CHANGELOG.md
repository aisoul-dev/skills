# Changelog

Versions of the `aisoul` plugin, newest first. Semver: major for breaking changes to a skill's name, arguments or output format; minor for new skills or capabilities; patch for fixes and wording.

## 1.2.0 (2026-11-07)

### pr
- `pr-risk`: merge-risk assessment in five dimensions (scope fit, blast radius, verification, reversibility, observability), each with evidence and one action that lowers it, and an overall low/medium/high decided by explicit rules rather than an average. Review mode prints to chat and posts only when asked; self-check mode applies the cheap actions and reports the risk before and after.
- `scripts/pr/risk-facts.sh`: changed files, sensitive paths by category, and signals in changed lines (swallowed errors, removed error reporting, type escapes, skipped or deleted tests, destructive data operations, feature flags). Overlay at `.claude/aisoul/pr-risk.md`.

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
