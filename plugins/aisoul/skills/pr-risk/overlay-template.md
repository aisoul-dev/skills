# pr-risk overlay

<!--
Copy this file to `.claude/aisoul/pr-risk.md` in a repository to adapt
/aisoul:pr-risk to it. Every section is optional: delete what you do not need
and the default applies. Keep the headings as they are.
-->

## Base branch

`main`

## Sensitive paths

Extra path patterns (extended regex, one per line), passed as `PR_RISK_SENSITIVE`.
Each is checked in addition to the built-in categories:

```text
app/composables/usePermissions
app/plugins/auth
server/api/admin/
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

## Verification evidence

Where proof for a PR normally lives, e.g. the PR description written with
/aisoul:pr-describe, CI artifacts, or a QA comment.
