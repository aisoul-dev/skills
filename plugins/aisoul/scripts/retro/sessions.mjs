#!/usr/bin/env node
// Finds session transcripts to run a retro on.
//
//   node sessions.mjs [--cwd <dir>] [--all] [--limit <n>]   newest sessions of a project
//   node sessions.mjs --queue [--cwd <dir>] [--all]          sessions the SessionEnd collector queued
//   node sessions.mjs --drop <transcript> [...]              remove handled sessions from the queue
//
// A session belongs to a project when it ran in that directory or below it.
// Default project: the current directory. --all ignores the project.
// Transcripts are read from $CLAUDE_CONFIG_DIR/projects (default ~/.claude),
// so separate config directories never see each other's sessions.
// Output, tab separated: last activity, tool calls, tool errors, human messages, transcript path.
// Exit: 0 with results, 1 with none, 2 on usage error.

import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { allTranscripts, parseTranscript, queueFile, sessionCwd } from './transcript.mjs';

const args = process.argv.slice(2);
const opt = { cwd: process.cwd(), all: false, limit: 10, queue: false, drop: [] };
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === '--cwd') opt.cwd = resolve(args[++i] || '.');
  else if (a === '--all') opt.all = true;
  else if (a === '--limit') opt.limit = Number(args[++i]);
  else if (a === '--queue') opt.queue = true;
  else if (a === '--drop') {
    opt.drop = args.slice(i + 1).map((p) => resolve(p));
    if (!opt.drop.length) { console.error('sessions: --drop needs at least one transcript'); process.exit(2); }
    break;
  } else { console.error(`sessions: unknown argument ${a}`); process.exit(2); }
}
if (!Number.isFinite(opt.limit) || opt.limit < 1) { console.error('sessions: --limit needs a positive number'); process.exit(2); }

const inProject = (cwd) => opt.all || (!!cwd && (cwd === opt.cwd || cwd.startsWith(`${opt.cwd}/`)));
const row = (s) => [s.last || '?', s.toolCalls.length, s.errors.length, s.human.length, s.path].join('\t');

function readQueue() {
  const f = queueFile();
  if (!existsSync(f)) return [];
  return readFileSync(f, 'utf8').split('\n').filter(Boolean).map((line) => {
    const [at, cwd, path, tools, errors, human, reason] = line.split('\t');
    return { line, at, cwd, path, tools, errors, human, reason };
  });
}

if (opt.drop.length) {
  const f = queueFile();
  const keep = readQueue().filter((q) => !opt.drop.includes(resolve(q.path)));
  writeFileSync(f, keep.map((q) => `${q.line}\n`).join(''));
  console.log(`queue: ${keep.length} left`);
  process.exit(0);
}

if (opt.queue) {
  const seen = new Set();
  const rows = [];
  for (const q of readQueue().reverse()) {
    if (seen.has(q.path) || !inProject(q.cwd)) continue;
    seen.add(q.path);
    if (!existsSync(q.path)) continue;
    rows.push([q.at, q.tools, q.errors, q.human, q.path].join('\t'));
  }
  if (!rows.length) { console.error('sessions: queue is empty for this project'); process.exit(1); }
  console.log(rows.join('\n'));
  process.exit(0);
}

const found = [];
for (const t of allTranscripts().sort((a, b) => b.mtime - a.mtime)) {
  if (found.length >= opt.limit) break;
  if (!inProject(sessionCwd(t.path))) continue;
  const s = parseTranscript(t.path);
  if (s.toolCalls.length === 0 && s.human.length === 0) continue;
  found.push(s);
}
if (!found.length) { console.error(`sessions: none found for ${opt.all ? 'any project' : opt.cwd}`); process.exit(1); }
found.sort((a, b) => String(b.last || '').localeCompare(String(a.last || '')));
console.log(found.map(row).join('\n'));
