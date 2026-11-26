# Nuxt / Vue / TypeScript

Detected by `nuxt.config.*` or `nuxt` in `package.json`. Measures `app/ server/ shared/ src/` by default.

## Prepare and commands

- Run `pnpm nuxt prepare` before measuring, so `.nuxt/` types and path aliases exist.
- Typecheck: `pnpm nuxt typecheck` or the repo's script. Lint and unit tests: the repo's scripts.
- Env: `UNTANGLE_APP_PREFIX` (`app/` for Nuxt 4, empty for Nuxt 3 without `app/`), `UNTANGLE_TSCONFIG`, `UNTANGLE_TS_VERSION` (TypeScript run next to dependency-cruiser, default `^6`).

## Steps

| Step | Tool | Output |
|------|------|--------|
| `deps.sh` | dependency-cruiser with `depcruise.cjs` | `deps.txt`: cycles, utils importing UI, logic importing components, components importing pages, shared importing app or server, client importing server |
| `deadweight.sh` | knip | `deadweight.txt` |
| `surface.sh` (optional) | `vue-tsc --emitDeclarationOnly` (needs vue-tsc in the project) | `surface/*.d.ts` |
| patch census | adds `route-branch` (`route.name ===` / `route.path ===`) | |

## Caveats

- knip: verify every hit with grep before it becomes a finding. `resolveComponent`, `<component :is>`, string lookups, server routes and test-only usage give false positives.
- dependency-cruiser: a run that parsed 0 modules is marked `UNVERIFIED` at the top of `deps.txt`, never read it as "no violations". The usual cause is a TypeScript version it does not support (it parses no `.ts` then); `deps.sh` pins one, `UNTANGLE_TS_VERSION` changes it.
- dependency-cruiser: auto-imported components and composables have no import statement, so the graph misses them. For each composable and store in scope, list consumers with grep (`grep -rn "useXxx(" app/`). If `.vue` files show zero dependencies, the SFC parser was not resolved: do not fix it, rely on grep for `.vue` and note it in the log.
- surface: if nothing is emitted, skip it and use subagent summaries per area.

## What the kinds look like here

**C. Change coupling**
- two components each build the same select options
- one feature sends a business ID, another sends a UUID for the same field
- a plugin must init before a middleware reads its state; a watcher relies on another watcher having run
- module-level `let` in a composable, `provide`/`inject` with string keys, `window` events, ad-hoc event buses
- parents driving children through template refs and `defineExpose` instead of props and emits

**D. Dependency direction**
- leaf UI components that import stores or call the API directly
- utils that read stores or runtime config
- business rules inside pages, needed by another page

**M. Shallow modules**
- a component that only forwards props to a UI library component
- a composable that wraps one call and adds nothing
- props drilled through 3+ levels that nothing in between uses

**W. Dead weight**
- props nobody passes, store state nobody reads
- hand-written types that duplicate generated API types

**P. Patches**
- `nextTick` or `setTimeout` to win a race with rendering
- `@ts-ignore`, `as any`, `eslint-disable`
- guard flags that stop watcher loops or double fetches
- branches on `route.name` or a specific id

## Pinning behavior

Test the way the code is used: component props, emits and rendered output; composable inputs and returned values; store actions and resulting state. Never assert on private functions or call counts of internals.
