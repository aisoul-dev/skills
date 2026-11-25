#!/usr/bin/env node
// How often each skill and slash command was used, across all sessions of the
// current config directory. For /aisoul:retro-curate.
//
//   node usage.mjs [--days <n>] [name ...]
//
// --days  only sessions active in the last n days (default 60)
// name    skills you have installed; each one with no use is listed as 0, so
//         unused skills show up instead of being invisible
// Output, tab separated: uses, sessions, last used (date), name. Most used first.
// Exit: 0, or 2 on usage error.

import { allTranscripts, parseTranscript, skillUses } from './transcript.mjs';

const args = process.argv.slice(2);
let days = 60;
const known = [];
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--days') days = Number(args[++i]);
  else known.push(args[i]);
}
if (!Number.isFinite(days) || days < 1) { console.error('usage: usage.mjs [--days <n>] [name ...]'); process.exit(2); }

// Plugin skills are recorded as `plugin:skill`; match a known bare name to either form.
const key = (name) => name.replace(/^\//, '');
const since = Date.now() - days * 86400000;
const stats = new Map();
let sessions = 0;
for (const t of allTranscripts()) {
  if (t.mtime < since) continue;
  sessions++;
  const s = parseTranscript(t.path);
  const seen = new Set();
  for (const u of skillUses(s)) {
    const k = key(u.name);
    const st = stats.get(k) || { uses: 0, sessions: 0, last: '' };
    st.uses++;
    if (!seen.has(k)) { st.sessions++; seen.add(k); }
    const day = (s.last || '').slice(0, 10);
    if (day > st.last) st.last = day;
    stats.set(k, st);
  }
}
for (const name of known) {
  const k = key(name);
  const hit = [...stats.keys()].some((s) => s === k || s.endsWith(`:${k}`));
  if (!hit) stats.set(k, { uses: 0, sessions: 0, last: '-' });
}
console.log(`# ${sessions} sessions in the last ${days} days`);
for (const [name, st] of [...stats.entries()].sort((a, b) => b[1].uses - a[1].uses || a[0].localeCompare(b[0]))) {
  console.log([st.uses, st.sessions, st.last || '-', name].join('\t'));
}
