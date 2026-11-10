# aisoul skills

A Claude Code plugin marketplace with my skills. One plugin, `aisoul`, so every skill is invoked as `/aisoul:<skill>`. The `pr` skills work on any stack; the `untangle` skills are for Nuxt / Vue / TypeScript.

| Skill | Stack | What it does |
|-------|-------|--------------|
| `/aisoul:untangle-audit` | Nuxt / Vue / TS | Read-only structural audit, writes a decision log of PR-sized fixes |
| `/aisoul:untangle-fix` | Nuxt / Vue / TS | Applies one fix from that log as one small PR |
| `/aisoul:pr-describe` | any | Short, evidence-first PR description sized to the diff |
| `/aisoul:pr-risk` | any | Merge-risk assessment in five dimensions, for a reviewer or as a self-check |
| `/aisoul:pr-review` | any | Branch review with a verdict: bug hunt, context checks, gates, merge risk, paste-ready comments |

Details: [plugins/aisoul](plugins/aisoul).

## Install

```bash
claude plugin marketplace add aisoul-dev/skills
claude plugin install aisoul@aisoul
```

Inside a session the same works as `/plugin marketplace add aisoul-dev/skills`, then `/plugin install aisoul@aisoul`.

### Update

Two steps: `marketplace update` refreshes the catalog only, `plugin update` installs the new version.

```bash
claude plugin marketplace update aisoul
claude plugin update aisoul@aisoul
```

Restart Claude Code afterwards: a running session keeps the version it started with. To see what is installed, list the cached versions:

```bash
ls ~/.claude/plugins/cache/aisoul/aisoul/
```

### Several Claude Code config directories

Plugins are registered per config directory. If you keep separate contexts (for example one for work and one for personal projects), add the marketplace in each:

```bash
CLAUDE_CONFIG_DIR=~/.claude-personal claude plugin marketplace add aisoul-dev/skills
CLAUDE_CONFIG_DIR=~/.claude-personal claude plugin install aisoul@aisoul

CLAUDE_CONFIG_DIR=~/.claude-work claude plugin marketplace add aisoul-dev/skills
CLAUDE_CONFIG_DIR=~/.claude-work claude plugin install aisoul@aisoul
```

Update each of them the same way, with the same `CLAUDE_CONFIG_DIR` in front of both update commands; the cache is then under that directory (`~/.claude-personal/plugins/cache/aisoul/aisoul/`).

## Layout

```
.claude-plugin/marketplace.json     catalog (marketplace name: aisoul)
plugins/aisoul/
  .claude-plugin/plugin.json        manifest: name, version, description
  skills/<group>-<action>/SKILL.md  invoked as /aisoul:<group>-<action>
  scripts/<group>/                  helpers, referenced as ${CLAUDE_PLUGIN_ROOT}/scripts/<group>/...
  README.md                         skill list and per-group docs
tests/                              smoke tests for plugin scripts
```

## Rules for this repo

- **General only.** No employer code, internal paths, colleague names or team rules. Project-specific facts live in the project, in an overlay at `.claude/aisoul/<skill>.md` that the skill reads when present; each skill that supports one ships an `overlay-template.md`.
- **Skill names are `<group>-<action>`** (e.g. `untangle-audit`, `plan-create`), so related skills sort together.
- **Scripts live in `scripts/<group>/`**, never at the plugin root, so groups do not collide.
- **Every change to the plugin bumps its `version`** in `plugin.json` (semver) and adds a line to [CHANGELOG.md](CHANGELOG.md). Installed copies are cached per version, so an unbumped change may not reach users.
- **Scripts never install into the target project.** Use `pnpm dlx` / `npx`, write to `/tmp`.
- **No em dashes** in skill text.
- **The marketplace name `aisoul` and the plugin name `aisoul` do not change.** They are stored in every install; renaming breaks updates. Moving the repo is fine, GitHub redirects.

## Develop

```bash
# validate catalog and plugin
claude plugin validate .
claude plugin validate ./plugins/aisoul

# use the working copy directly
claude plugin marketplace add ./
claude plugin install aisoul@aisoul
# edits apply on the next session start or after /reload-plugins

# script tests
bash tests/smoke.sh
bash tests/pr.sh
bash tests/pr-risk.sh
bash tests/pr-review.sh
shellcheck -x plugins/*/scripts/*/*.sh tests/*.sh
```

CI runs the same checks on every push and pull request.

## Release

1. Bump `version` in `plugins/aisoul/.claude-plugin/plugin.json`.
2. Add the entry to `CHANGELOG.md`.
3. Merge to `main`. Only then tag the merge commit and push the tag:

   ```bash
   git fetch origin
   git tag v<version> origin/main
   git push origin v<version>
   ```

   A tag made before the merge points at the old `main`. Move it with `git tag -f v<version> <merge sha>` and `git push --force origin v<version>`.
4. Update the installed copies (Update, above).

## License

[MIT](LICENSE). Third-party credits are listed in [plugins/aisoul/README.md](plugins/aisoul/README.md).
