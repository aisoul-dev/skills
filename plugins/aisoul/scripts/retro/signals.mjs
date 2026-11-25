#!/usr/bin/env node
// Mechanical facts from one or more session transcripts, each with the line it
// comes from, so every retro finding can cite `<session>:L<n>`.
//
//   node signals.mjs <transcript.jsonl> [...]
//
// Env (thresholds):
//   RETRO_LARGE   tool result size in characters that counts as large (default 20000)
//   RETRO_REPEAT  same command run this many times counts as repeated (default 3)
//   RETRO_REREAD  same file read this many times counts as re-read (default 3)
//   RETRO_CHURN   same file edited this many times counts as churn (default 4)
// Exit: 0 on success, 2 on usage error or an unreadable transcript.

import { existsSync } from 'node:fs';
import { parseTranscript, skillUses, countBy, oneLine } from './transcript.mjs';

const REPEAT = Number(process.env.RETRO_REPEAT || 3);
const REREAD = Number(process.env.RETRO_REREAD || 3);
const CHURN = Number(process.env.RETRO_CHURN || 4);
const NAV_TOOLS = new Set(['Read', 'Grep', 'Glob', 'LS']);
const EDIT_TOOLS = new Set(['Edit', 'Write', 'MultiEdit', 'NotebookEdit']);

const files = process.argv.slice(2);
if (files.length === 0) {
  console.error('usage: signals.mjs <transcript.jsonl> [...]');
  process.exit(2);
}

const refs = (ns, max = 8) => {
  const shown = ns.slice(0, max).map((n) => `L${n}`).join(', ');
  return ns.length > max ? `${shown}, +${ns.length - max}` : shown;
};

function minutes(a, b) {
  const d = (Date.parse(b) - Date.parse(a)) / 60000;
  return Number.isFinite(d) ? `${Math.round(d)} min` : '?';
}

function report(path) {
  const s = parseTranscript(path);
  const out = [];
  const say = (line = '') => out.push(line);

  say(`# session ${s.session}`);
  say(`file: ${s.path}`);
  say(`cwd: ${s.cwd || '?'} | branch: ${s.branch || '?'} | claude ${s.version || '?'} | ${s.first || '?'} .. ${s.last || '?'} (${minutes(s.first, s.last)})`);
  const byTool = countBy(s.toolCalls, (c) => c.name).map(([k, v]) => `${k} ${v}`).join(', ');
  say(`events: ${s.events} | human: ${s.human.length} | interruptions: ${s.interruptions.length} | tool calls: ${s.toolCalls.length}${byTool ? ` (${byTool})` : ''} | tool errors: ${s.errors.length} | compactions: ${s.compactions.length} | subagent events: ${s.sidechain}`);

  const skills = countBy(skillUses(s), (u) => u.name);
  if (skills.length) {
    const uses = skillUses(s);
    say(`skills and commands: ${skills.map(([k, v]) => `${k} x${v} (${refs(uses.filter((u) => u.name === k).map((u) => u.n), 3)})`).join('; ')}`);
  }
  if (s.compactions.length) say(`compacted at: ${refs(s.compactions)}`);

  say('');
  say('## human messages');
  if (!s.human.length) say('none');
  for (const h of s.human) say(`L${h.n}  ${h.text}`);
  if (s.interruptions.length) say(`interrupted by the user at: ${refs(s.interruptions)}`);

  say('');
  say('## tool errors');
  if (!s.errors.length) say('none');
  for (const e of s.errors) {
    const what = e.call ? `${e.call.name} \`${oneLine(e.call.what, 100)}\`` : 'unknown call';
    say(`L${e.n}  ${what} -> ${e.text}`);
  }

  say('');
  say(`## repeated commands (${REPEAT}+ runs)`);
  const bash = s.toolCalls.filter((c) => c.name === 'Bash' && c.what);
  const groups = new Map();
  for (const c of bash) {
    const k = oneLine(c.what, 400);
    if (!groups.has(k)) groups.set(k, []);
    groups.get(k).push(c);
  }
  let repeated = 0;
  for (const [cmd, calls] of [...groups.entries()].sort((a, b) => b[1].length - a[1].length)) {
    if (calls.length < REPEAT) continue;
    repeated++;
    const failed = calls.filter((c) => c.error).length;
    say(`${calls.length}x \`${oneLine(cmd, 120)}\` (${refs(calls.map((c) => c.n))})${failed ? `, failed ${failed}` : ''}`);
  }
  if (!repeated) say('none');

  say('');
  say('## navigation');
  const firstEdit = s.toolCalls.find((c) => EDIT_TOOLS.has(c.name));
  const before = s.toolCalls.filter((c) => NAV_TOOLS.has(c.name) && (!firstEdit || c.n < firstEdit.n));
  const beforeBash = s.toolCalls.filter((c) => c.name === 'Bash' && /^\s*(ls|find|grep|rg|cat|head|tail|tree)\b/.test(c.what) && (!firstEdit || c.n < firstEdit.n));
  say(firstEdit ? `first edit at L${firstEdit.n}` : 'no edits in this session');
  say(`search and read calls before it: ${before.length + beforeBash.length} (${countBy([...before, ...beforeBash], (c) => c.name).map(([k, v]) => `${k} ${v}`).join(', ') || 'none'})`);
  const reads = countBy(s.toolCalls.filter((c) => c.name === 'Read' && c.what), (c) => c.what).filter(([, v]) => v >= REREAD);
  for (const [file, v] of reads) say(`read ${v}x: ${file} (${refs(s.toolCalls.filter((c) => c.name === 'Read' && c.what === file).map((c) => c.n))})`);

  say('');
  say(`## edit churn (${CHURN}+ edits to one file)`);
  const edits = countBy(s.toolCalls.filter((c) => EDIT_TOOLS.has(c.name) && c.what), (c) => c.what).filter(([, v]) => v >= CHURN);
  if (!edits.length) say('none');
  for (const [file, v] of edits) say(`${v}x ${file} (${refs(s.toolCalls.filter((c) => EDIT_TOOLS.has(c.name) && c.what === file).map((c) => c.n))})`);

  say('');
  say('## large tool results');
  if (!s.largeResults.length) say('none');
  for (const r of s.largeResults.sort((a, b) => b.size - a.size)) {
    const what = r.call ? `${r.call.name} \`${oneLine(r.call.what, 100)}\`` : 'unknown call';
    say(`L${r.n}  ${Math.round(r.size / 1000)}k chars  ${what}`);
  }
  return out.join('\n');
}

let status = 0;
const parts = [];
for (const f of files) {
  if (!existsSync(f)) { console.error(`signals: no such file: ${f}`); status = 2; continue; }
  try { parts.push(report(f)); } catch (e) { console.error(`signals: cannot read ${f}: ${e.message}`); status = 2; }
}
if (parts.length) console.log(parts.join('\n\n'));
process.exit(status);
