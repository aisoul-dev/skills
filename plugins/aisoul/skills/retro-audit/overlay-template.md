# retro overlay

<!--
Copy this file to `.claude/aisoul/retro-audit.md` in a repository to adapt
/aisoul:retro-audit, /aisoul:retro-fix and /aisoul:retro-curate to it. Every
section is optional: delete what you do not need and the default applies.
Keep project specifics here, never in a shared skill.
-->

## Log folder

Where decision logs go. Default `docs/retro`. A folder outside git (for
example `.scratch/retro`) keeps logs out of the repo history.

`docs/retro`

## Standards file

Where judgement-call rules for the reviewer live, the target of S fixes.
Default: `CODING_STANDARDS.md`, then `docs/CODING_STANDARDS.md`, then the
Constraints section of `.claude/aisoul/pr-review.md`.

`docs/CODING_STANDARDS.md`

## Skill sources

Where the skills this project uses are maintained, so P fixes land in the
source and not in a read-only plugin copy. One per line: a folder, or
`<plugin>: <git repo path>` for a plugin you maintain.

```text
.claude/skills
~/.claude/skills
aisoul: ~/Develop/skills
```

## Steering files

Extra always-loaded files, besides `CLAUDE.md`, `AGENTS.md`,
`.claude/CLAUDE.md` and the user's global `CLAUDE.md`.

```text
docs/agents/README.md
```

## Guardrails

Check commands, if they are not in `package.json`, a `Makefile` or CI.

```text
pnpm lint
pnpm typecheck
pnpm test
```
