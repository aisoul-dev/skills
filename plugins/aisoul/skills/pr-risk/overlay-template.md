# pr-risk overlay

<!--
Copy this file to `.claude/aisoul/pr-risk.md` in a repository to adapt
/aisoul:pr-risk to it. Every section is optional: delete what you do not need
and the default applies. Keep the headings as they are: `overlay-env.sh`
reads the first ```text block (or, for the base, the first `code`) under them.
-->

## Base branch

`origin/main`

## Sensitive paths

Extra path patterns (extended regex, one per line, matched anywhere in the
path), passed as `PR_RISK_SENSITIVE`. Each is checked in addition to the
built-in categories:

```text
app/composables/usePermissions
app/plugins/auth
server/api/admin/
```

## Excluded from code signals

Paths (extended regex, one per line, anchored at the repository root) whose
changed lines produce no signals, passed as `PR_RISK_EXCLUDE`. Markdown and
plain-text files are always excluded.

```text
tests/fixtures/
```

## Error reporting

Calls that report errors in this project, passed as `PR_RISK_REPORTING`:

```text
useErrorReporter|trackError
```

Where reports go: Sentry, project `web`. Unhandled promise rejections are reported; errors caught and logged with `console.error` are not.

## Feature flags

Flag API, passed as `PR_RISK_FLAGS`:

```text
useFeatureFlag|posthog\.isFeatureEnabled
```

## Rollback

How a bad merge is undone here, and what a revert does not undo:

- Revert on `main`, then the next release tag; a release takes about 30 minutes.
- Database migrations run on deploy and are not reverted automatically: any migration is a one-way door until a down migration is written and tested.

## Runtime

Where the code runs and what "someone finds out" means there, e.g. a deployed
service reporting to Sentry, or a CLI that must fail with a non-zero exit and a
clear message.

## Verification evidence

Where proof for a PR normally lives, e.g. the PR description written with
/aisoul:pr-describe, CI artifacts, or a QA comment.
