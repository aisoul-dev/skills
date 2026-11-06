// dependency-cruiser rules for a Nuxt layout.
// One idea: stable code must not depend on more volatile code.
//
// Env:
//   UNTANGLE_APP_PREFIX  'app/' for Nuxt 4 (default), '' for Nuxt 3 without app/
//   UNTANGLE_TSCONFIG    tsconfig used for path aliases (deps.sh picks one)

const fs = require('node:fs');

const A = process.env.UNTANGLE_APP_PREFIX ?? 'app/';
const TSCONFIG = process.env.UNTANGLE_TSCONFIG || '.nuxt/tsconfig.app.json';
// Everything that belongs to the client app, for either layout.
const APP = A ? `^${A}` : '^(components|composables|stores|pages|layouts|utils|plugins|middleware)/';

module.exports = {
  forbidden: [
    { name: 'no-cycles', severity: 'error', from: {}, to: { circular: true } },
    {
      name: 'utils-are-leaves', severity: 'error',
      from: { path: `^${A}utils` },
      to: { path: `^${A}(components|composables|stores|pages|layouts)` },
    },
    {
      name: 'logic-does-not-know-ui', severity: 'error',
      from: { path: `^${A}(composables|stores|utils)` },
      to: { path: `^${A}(components|pages|layouts)` },
    },
    {
      name: 'components-do-not-know-pages', severity: 'error',
      from: { path: `^${A}components` },
      to: { path: `^${A}pages` },
    },
    {
      name: 'shared-is-a-leaf', severity: 'error',
      from: { path: '^shared/' },
      to: { path: `${APP}|^server/` },
    },
    {
      name: 'client-does-not-import-server', severity: 'warn',
      from: { path: APP },
      to: { path: '^server/' },
    },
  ],
  options: {
    // Without a tsconfig, path aliases (~/, #imports) stay unresolved; relative imports still work.
    ...(fs.existsSync(TSCONFIG) ? { tsConfig: { fileName: TSCONFIG } } : {}),
    tsPreCompilationDeps: true,
    doNotFollow: { path: 'node_modules' },
    exclude: { path: '^(\\.nuxt|\\.output|node_modules|dist)' },
  },
};
