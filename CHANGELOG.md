# Changelog

Versions of the `aisoul` plugin, newest first. Semver: major for breaking changes to a skill's name, arguments or output format; minor for new skills or capabilities; patch for fixes and wording.

## 1.5.0 (2026-11-10)

The `pr` skills pick sensible defaults on any stack. The JS/Nuxt path gives the same results as before, and the overlay stays the way to tune a project.

### pr
- `pr-review`: gates come from the first source that has them: the overlay, CI config, the tests section of `CLAUDE.md`, `AGENTS.md` or `CONTRIBUTING.md` (running only what the diff touches), then the build files (`package.json`, `Makefile`/`justfile`, `pyproject.toml`/`tox.ini`/`noxfile.py`, `go.mod`, `Cargo.toml`, `Gemfile`, `composer.json`). A linter or formatter runs only with its config present; a long suite runs the part the diff touches. The reply names the source.
- `pr-review`: the Contract row no longer assumes a frontend ("the calling side's own types"); Duplication says "function, module, helper or component".
- Default ticket pattern `[A-Z][A-Z0-9]*-[0-9]+`, so one-letter board prefixes such as `T-25` count. Checked first on the orgmaps history: one-letter ids appear only in old merged commits (acceptance and finding labels), none in the 58 latest branch ranges. Standards (UTF-8, SHA-256, ...) are still filtered.
- `risk-facts.sh`: type and lint escapes for Python (`# type: ignore`, `# noqa`, `# pylint: disable`), Go (`//nolint`), Rust (`#[allow(`), Java (`@SuppressWarnings`), shell (`# shellcheck disable`), Ruby (`rubocop:disable`) and `@ts-nocheck`; swallowed errors for Python `except ...: pass` and an empty Go `if err != nil {}`, one-line and two-line; skipped tests for pytest, Go `t.Skip`, `xit`/`xdescribe` and RSpec `skip`; deleted tests and the test count know Go and Python test files. Each pattern has a test with a line it must catch and a near miss it must not.
- One lockfile list in `scripts/pr/lib.sh` (JS, Python, Ruby, PHP, Rust, Go), read by `size.sh`, `risk-facts.sh` and pr-describe. `size.sh` now leaves out lockfiles in subfolders too; `risk-facts.sh` lists Python, Ruby and PHP manifests as dependencies.
- The pr-risk overlay template documents Sensitive paths as the place for a framework's own config; the built-in list stays short.
- README: which skills work on any stack (`pr-*`) and which are Nuxt / Vue / TS only (`untangle-*`).

## 1.4.1 (2026-11-09)

### pr
- `comment-link.sh`: a line range no longer fails with `unbound variable` under `LC_CTYPE=C` on bash 3.2 (macOS), where the en dash in `$line–$end` was read as part of the variable name. Now `${line}–${end}`.
- CI fails on any `$name` followed directly by a non-ASCII character in scripts and tests; a regression test runs the range under `LC_ALL=C`.

## 1.4.0 (2026-11-08)

### pr
- `pr-review`: a Spec check. It finds the spec (references in the branch and commits, spec files the branch changes or names, then the user) and reports missing or partial, wrong, and unasked behaviour, each quoting the spec line; missing and wrong can be Blockers. With no spec it says so and invents nothing.
- `pr-review`: the bug hunt is the built-in `/code-review`; when a plugin skill shares the name, or the one found is not a bug hunt, it asks instead of guessing. A standards review skill, when installed, is a second source of findings (source `standards`).
- `pr-review`: every subagent brief forbids invoking review skills, so subagents never start another review.
- `pr-risk`: Scope fit is judged against the spec when one exists.
- The reply carries one line per spec (`Spec: ...: R1 met, R2 partial`), and says under Not checked which bug hunt ran and when no standards review did.
- `scripts/pr/spec-find.sh`, with tests: works from any subdirectory and with non-ASCII names, exits 2 on an empty range or an invalid ticket pattern, matches whole tickets only, scores branch words against file names, ignores standards such as UTF-8 in the default pattern. `overlay-env.sh` reads Spec folders and Ticket pattern.

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
