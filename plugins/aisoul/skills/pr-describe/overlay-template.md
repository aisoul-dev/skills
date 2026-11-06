# pr-describe overlay

<!--
Copy this file to `.claude/aisoul/pr-describe.md` in a repository to adapt
/aisoul:pr-describe to it. Every section is optional: delete the ones you do
not need and the skill's default applies. Keep the headings as they are.
-->

## Location

`docs/pull-requests/<ticket>-pr-description.md`, untracked.

## Title

`# [<ticket>] <title>`, ticket format `ABC-123`.

## Base branch

`main`

## Excluded paths

These do not count towards the diff size, in addition to the defaults:

- `src/api/generated/`

## Checks tab

What CI reports on every PR, so the description does not repeat it:

- ESLint
- `tsc --noEmit`
- Prettier
- unit suite (Vitest)
- e2e lane

## Live environment

Both test suites mock the API. The real environment is the dockerised backend
started with `docker compose up api`. Name what running the branch against it
caught, or say on the **Not checked** line that it was not run.

## Screenshots

Desktop width only: the product does not support narrow screens.

## Disclosure

<!-- Optional. One line placed under the title, e.g.:
> Written by an AI agent on behalf of @handle. @handle has reviewed it.
Delete this section for no disclosure. -->

## Example

<!-- Optional. A real description from this repository in the small shape,
fenced as markdown. It replaces the example in the skill as the reference
for length and tone. -->
