// Shared reader for Claude Code session transcripts (JSONL, one event per line).
// Import it, do not run it.
//
// The format is not a public contract, so every field is read defensively: an
// unknown or malformed line is skipped, never fatal. Line numbers are 1-based
// and are what the retro log cites as evidence (`<session>:L<n>`).

import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { join, basename } from 'node:path';

export function configDir() {
  return process.env.CLAUDE_CONFIG_DIR || join(homedir(), '.claude');
}

export function projectsDir() {
  return join(configDir(), 'projects');
}

export function queueFile() {
  return process.env.RETRO_QUEUE || join(configDir(), 'aisoul', 'retro-queue.tsv');
}

// Every top-level *.jsonl under the projects folder (subagent files live in
// subfolders and belong to their parent session).
export function allTranscripts() {
  const root = projectsDir();
  if (!existsSync(root)) return [];
  const out = [];
  for (const dir of readdirSync(root)) {
    const full = join(root, dir);
    let entries;
    try { entries = readdirSync(full); } catch { continue; }
    for (const f of entries) {
      if (!f.endsWith('.jsonl')) continue;
      const path = join(full, f);
      try {
        const st = statSync(path);
        if (st.isFile()) out.push({ path, mtime: st.mtimeMs, size: st.size });
      } catch { /* vanished */ }
    }
  }
  return out;
}

export function readLines(path) {
  const rows = [];
  const text = readFileSync(path, 'utf8');
  const lines = text.split('\n');
  for (let i = 0; i < lines.length; i++) {
    if (!lines[i].trim()) continue;
    try { rows.push({ n: i + 1, o: JSON.parse(lines[i]) }); } catch { /* partial line */ }
  }
  return rows;
}

// The cwd a session ran in: the first event that records one.
export function sessionCwd(path) {
  for (const { o } of readLines(path)) if (o && typeof o.cwd === 'string') return o.cwd;
  return null;
}

export function textOf(content) {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return '';
  return content
    .map((b) => (typeof b === 'string' ? b : b && b.type === 'text' ? b.text || '' : ''))
    .join('\n');
}

function resultSize(content) {
  if (typeof content === 'string') return content.length;
  if (Array.isArray(content)) return content.reduce((s, b) => s + (b && typeof b.text === 'string' ? b.text.length : 0), 0);
  return 0;
}

export function oneLine(s, max = 160) {
  const t = String(s || '').replace(/\s+/g, ' ').trim();
  return t.length > max ? `${t.slice(0, max - 1)}…` : t;
}

// What a tool call was about, in one short line.
export function describeInput(name, input) {
  if (!input || typeof input !== 'object') return '';
  if (name === 'Bash') return input.command || '';
  if (name === 'Skill') return input.skill || input.command || input.name || '';
  return input.file_path || input.path || input.pattern || input.url || input.query || input.description || '';
}

const COMMAND_RE = /<command-name>\s*\/?([^<\s]+)\s*<\/command-name>/;
const INTERRUPT_RE = /^\[Request interrupted/;

// Turns a transcript into facts. Sidechain (subagent) events are counted but
// kept out of the main-thread statistics.
export function parseTranscript(path) {
  const rows = readLines(path);
  const s = {
    path,
    session: basename(path, '.jsonl'),
    cwd: null,
    branch: null,
    version: null,
    first: null,
    last: null,
    events: rows.length,
    sidechain: 0,
    compactions: [],
    human: [],
    interruptions: [],
    commands: [],
    toolCalls: [],
    errors: [],
    largeResults: [],
  };
  const byId = new Map();
  const large = Number(process.env.RETRO_LARGE || 20000);

  for (const { n, o } of rows) {
    if (!o || typeof o !== 'object') continue;
    if (o.cwd && !s.cwd) s.cwd = o.cwd;
    if (o.gitBranch && !s.branch) s.branch = o.gitBranch;
    if (o.version && !s.version) s.version = o.version;
    if (o.timestamp) { s.first = s.first || o.timestamp; s.last = o.timestamp; }
    if (o.isSidechain) { s.sidechain++; continue; }
    if (o.type === 'summary' || o.isCompactSummary || (o.type === 'system' && o.subtype === 'compact_boundary')) {
      s.compactions.push(n);
      continue;
    }

    const content = o.message && o.message.content;

    if (o.type === 'assistant' && Array.isArray(content)) {
      for (const b of content) {
        if (!b || b.type !== 'tool_use') continue;
        const call = { n, id: b.id, name: b.name || '?', what: describeInput(b.name, b.input), input: b.input || {} };
        s.toolCalls.push(call);
        if (b.id) byId.set(b.id, call);
      }
      continue;
    }

    if (o.type !== 'user') continue;

    if (Array.isArray(content) && content.some((b) => b && b.type === 'tool_result')) {
      for (const b of content) {
        if (!b || b.type !== 'tool_result') continue;
        const call = byId.get(b.tool_use_id);
        const size = resultSize(b.content);
        if (call) { call.size = size; call.error = !!b.is_error; call.resultLine = n; }
        if (b.is_error) s.errors.push({ n, call, text: oneLine(textOf(b.content), 200) });
        if (size >= large) s.largeResults.push({ n, call, size });
      }
      continue;
    }

    if (o.isMeta) continue;
    const text = textOf(content);
    if (!text.trim()) continue;
    const cmd = text.match(COMMAND_RE);
    if (cmd) { s.commands.push({ n, name: cmd[1] }); continue; }
    if (INTERRUPT_RE.test(text.trim())) { s.interruptions.push(n); continue; }
    if (/^\s*<(local-command|system-reminder|bash-|task-notification)/.test(text) || /^Caveat:/.test(text)) continue;
    s.human.push({ n, text: oneLine(text, 220) });
  }
  return s;
}

// Skills used in a session: Skill tool calls and slash commands.
export function skillUses(s) {
  const uses = [];
  for (const c of s.toolCalls) if (c.name === 'Skill' && c.what) uses.push({ n: c.n, name: c.what });
  for (const c of s.commands) uses.push({ n: c.n, name: c.name });
  return uses;
}

export function countBy(items, key) {
  const m = new Map();
  for (const it of items) { const k = key(it); m.set(k, (m.get(k) || 0) + 1); }
  return [...m.entries()].sort((a, b) => b[1] - a[1]);
}
