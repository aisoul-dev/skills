#!/usr/bin/env node
// SessionEnd hook: queues a finished session for the next /aisoul:retro-audit.
// It runs no model and changes nothing in the project: it reads the transcript,
// and if the session shows signs of friction, appends one line to the queue.
//
// The plugin registers it (hooks/hooks.json), but it stays inert until you opt
// in, per config directory:
//   mkdir -p "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/aisoul"
//   touch "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/aisoul/retro-collect"
// Remove that file to opt out. Separate config directories keep separate queues.
//
// Input: the hook's JSON on stdin (transcript_path, cwd, reason).
// Queue: $RETRO_QUEUE, default $CLAUDE_CONFIG_DIR/aisoul/retro-queue.tsv (~/.claude/aisoul/...).
// Env:
//   AISOUL_RETRO_COLLECT=1  opt in without the file
//   AISOUL_RETRO_SKIP=1     do nothing (set it for headless runs you never want queued)
//   RETRO_IGNORE          regex on the session cwd; matching sessions are not queued
//   RETRO_MIN_TOOLS       queue when tool calls >= this (default 15)
//   RETRO_MIN_ERRORS      queue when tool errors >= this (default 2)
//   RETRO_MIN_HUMAN       queue when human messages >= this (default 4)
// Any interruption by the user also queues the session.
// Always exits 0: a hook must never break the session it ends.

import { appendFileSync, mkdirSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { configDir, parseTranscript, queueFile } from './transcript.mjs';

function main(raw) {
  if (process.env.AISOUL_RETRO_SKIP) return;
  if (!process.env.AISOUL_RETRO_COLLECT && !existsSync(join(configDir(), 'aisoul', 'retro-collect'))) return;
  let input;
  try { input = JSON.parse(raw || '{}'); } catch { return; }
  const path = input.transcript_path;
  if (!path || !existsSync(path)) return;

  const s = parseTranscript(path);
  const cwd = input.cwd || s.cwd || '';
  const ignore = process.env.RETRO_IGNORE;
  if (ignore && new RegExp(ignore).test(cwd)) return;

  const minTools = Number(process.env.RETRO_MIN_TOOLS || 15);
  const minErrors = Number(process.env.RETRO_MIN_ERRORS || 2);
  const minHuman = Number(process.env.RETRO_MIN_HUMAN || 4);
  const why = [];
  if (s.toolCalls.length >= minTools) why.push('tools');
  if (s.errors.length >= minErrors) why.push('errors');
  if (s.human.length >= minHuman) why.push('human');
  if (s.interruptions.length) why.push('interrupted');
  if (!why.length) return;

  const q = queueFile();
  mkdirSync(dirname(q), { recursive: true });
  const clean = (v) => String(v).replace(/[\t\n]/g, ' ');
  appendFileSync(q, `${[new Date().toISOString(), cwd, path, s.toolCalls.length, s.errors.length, s.human.length, why.join(',')].map(clean).join('\t')}\n`);
}

let raw = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (d) => { raw += d; });
process.stdin.on('end', () => {
  try { main(raw); } catch { /* never fail the session */ }
  process.exit(0);
});
setTimeout(() => process.exit(0), 10000).unref();
