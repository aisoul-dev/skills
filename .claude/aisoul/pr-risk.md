# pr-risk overlay for this repository

## Base branch

`main`

## Sensitive paths

What users install and what decides when a skill runs:

```text
(^|/)\.claude-plugin/
(^|/)skills/[^/]+/SKILL\.md$
```

## Excluded from code signals

The scripts carry the patterns they search for, and the tests carry fixtures
with every signal on purpose:

```text
plugins/aisoul/scripts/
tests/
```

## Rollback

A revert on `main` plus a version bump in `plugin.json`; users get it with
`claude plugin marketplace update aisoul`. Installed copies are cached per
version, so a fix must ship as a new version, never as a revert that lowers it.

## Runtime

Skills are read by an agent, scripts run on users' machines. Observability
means scripts fail loudly (non-zero exit, a message that names the fix) and
never print a plausible but wrong result.
