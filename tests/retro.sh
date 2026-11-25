#!/usr/bin/env bash
# Tests for the retro transcript scripts on a synthetic Claude Code config
# directory. No model is run and nothing outside a temp folder is touched.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$ROOT/plugins/aisoul/scripts/retro"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

export CLAUDE_CONFIG_DIR="$TMP/config"
unset RETRO_QUEUE AISOUL_RETRO_COLLECT AISOUL_RETRO_SKIP RETRO_IGNORE
PROJ="$TMP/work/app"
mkdir -p "$PROJ/sub" "$CLAUDE_CONFIG_DIR/projects/p1" "$CLAUDE_CONFIG_DIR/projects/p2/sess-a"

# One event per line, in the shape Claude Code writes. Line numbers matter:
# the assertions below cite them.
A="$CLAUDE_CONFIG_DIR/projects/p1/sess-a.jsonl"
u()  { printf '{"type":"user","cwd":"%s","gitBranch":"feat/x","timestamp":"%s","message":{"role":"user","content":%s}}\n' "$1" "$2" "$3"; }
tu() { printf '{"type":"assistant","cwd":"%s","timestamp":"%s","message":{"role":"assistant","content":[{"type":"tool_use","id":"%s","name":"%s","input":%s}]}}\n' "$PROJ" "$1" "$2" "$3" "$4"; }
tr() { printf '{"type":"user","cwd":"%s","timestamp":"%s","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"%s","is_error":%s,"content":%s}]}}\n' "$PROJ" "$1" "$2" "$3" "$4"; }
big="$(printf 'x%.0s' $(seq 1 25000))"
{
  u "$PROJ" 2026-11-20T10:00:00Z '"add the export button"'                                     # L1
  tu 2026-11-20T10:01:00Z t1 Grep '{"pattern":"ExportButton"}'                                   # L2
  tr 2026-11-20T10:01:01Z t1 false '"no matches"'                                                # L3
  tu 2026-11-20T10:02:00Z t2 Read '{"file_path":"/w/app/a.ts"}'                                   # L4
  tr 2026-11-20T10:02:01Z t2 false '"code"'                                                      # L5
  tu 2026-11-20T10:03:00Z t3 Read '{"file_path":"/w/app/a.ts"}'                                   # L6
  tr 2026-11-20T10:03:01Z t3 false '"code"'                                                      # L7
  tu 2026-11-20T10:04:00Z t4 Read '{"file_path":"/w/app/a.ts"}'                                   # L8
  tr 2026-11-20T10:04:01Z t4 false "\"$big\""                                                    # L9
  tu 2026-11-20T10:05:00Z t5 Bash '{"command":"pnpm test"}'                                      # L10
  tr 2026-11-20T10:05:01Z t5 true '"1 failed"'                                                   # L11
  tu 2026-11-20T10:06:00Z t6 Bash '{"command":"pnpm  test"}'                                     # L12
  tr 2026-11-20T10:06:01Z t6 true '[{"type":"text","text":"1 failed again"}]'                   # L13
  u "$PROJ" 2026-11-20T10:07:00Z '"no, credentials include only on the handshake call"'        # L14
  tu 2026-11-20T10:08:00Z t7 Edit '{"file_path":"/w/app/a.ts"}'                                   # L15
  tr 2026-11-20T10:08:01Z t7 false '"ok"'                                                        # L16
  tu 2026-11-20T10:09:00Z t8 Bash '{"command":"pnpm test"}'                                      # L17
  tr 2026-11-20T10:09:01Z t8 false '"passed"'                                                    # L18
  tu 2026-11-20T10:10:00Z t9 Skill '{"skill":"aisoul:pr-describe"}'                              # L19
  tr 2026-11-20T10:10:01Z t9 false '"loaded"'                                                    # L20
  u "$PROJ" 2026-11-20T10:11:00Z '"<command-name>/aisoul:pr-risk</command-name>"'              # L21
  u "$PROJ" 2026-11-20T10:12:00Z '"[Request interrupted by user]"'                              # L22
  printf '{"type":"user","isMeta":true,"cwd":"%s","message":{"role":"user","content":"skill text"}}\n' "$PROJ"   # L23
  printf '{"type":"assistant","isSidechain":true,"message":{"content":[{"type":"tool_use","id":"s1","name":"Bash","input":{"command":"ls"}}]}}\n'  # L24
  printf '{"type":"system","subtype":"compact_boundary"}\n'                                     # L25
  printf 'not json\n'                                                                            # L26
} > "$A"

# A second project, and a session in a subfolder of the first.
B="$CLAUDE_CONFIG_DIR/projects/p1/sess-b.jsonl"
u "$TMP/elsewhere" 2026-11-21T09:00:00Z '"hello"' > "$B"
C="$CLAUDE_CONFIG_DIR/projects/p2/sess-c.jsonl"
u "$PROJ/sub" 2026-11-21T09:00:00Z '"in a subfolder"' > "$C"
# Subagent files in a session folder are not sessions of their own.
u "$PROJ" 2026-11-21T09:00:00Z '"subagent"' > "$CLAUDE_CONFIG_DIR/projects/p2/sess-a/agent.jsonl"

### signals
sig="$(node "$SCRIPTS/signals.mjs" "$A")"
echo "$sig"
grep -q 'branch: feat/x' <<<"$sig"                     || fail "branch"
grep -q 'human: 2 | interruptions: 1' <<<"$sig"         || fail "human count excludes commands, meta and interruptions"
grep -q 'tool calls: 9' <<<"$sig"                       || fail "sidechain calls stay out of tool calls"
grep -q 'tool errors: 2' <<<"$sig"                      || fail "tool errors"
grep -q 'compactions: 1' <<<"$sig"                      || fail "compaction"
grep -q 'subagent events: 1' <<<"$sig"                  || fail "subagent events"
grep -q '^L14  no, credentials include' <<<"$sig"       || fail "human message with its line"
grep -q 'interrupted by the user at: L22' <<<"$sig"     || fail "interruption line"
grep -q '^L13  Bash `pnpm test` -> 1 failed again' <<<"$sig" || fail "error from a text-block result"
grep -q '^3x `pnpm test` (L10, L12, L17), failed 2' <<<"$sig" || fail "repeated command, whitespace-normalised"
grep -q 'first edit at L15' <<<"$sig"                   || fail "first edit"
grep -q 'read 3x: /w/app/a.ts (L4, L6, L8)' <<<"$sig"  || fail "re-reads"
grep -q '^L9  25k chars  Read' <<<"$sig"                || fail "large result"
grep -q 'aisoul:pr-describe x1 (L19)' <<<"$sig"         || fail "Skill tool use"
grep -q 'aisoul:pr-risk x1 (L21)' <<<"$sig"             || fail "slash command"
RETRO_CHURN=1 node "$SCRIPTS/signals.mjs" "$A" | grep -q '^1x /w/app/a.ts (L15)' || fail "edit churn threshold"
if node "$SCRIPTS/signals.mjs" "$TMP/missing.jsonl" 2>/dev/null; then fail "missing file should exit 2"; fi
if node "$SCRIPTS/signals.mjs" 2>/dev/null; then fail "no args should exit 2"; fi

### sessions
s="$(node "$SCRIPTS/sessions.mjs" --cwd "$PROJ")"
echo "$s"
grep -q "sess-a.jsonl" <<<"$s"    || fail "project session listed"
grep -q "sess-c.jsonl" <<<"$s"    || fail "subfolder session listed"
if grep -q "sess-b.jsonl" <<<"$s"; then fail "other project listed"; fi
if grep -q "agent.jsonl" <<<"$s"; then fail "subagent file listed"; fi
[ "$(grep -c . <<<"$s")" = 2 ]    || fail "two sessions expected"
head -n1 <<<"$s" | grep -q 'sess-c' || fail "newest first"
node "$SCRIPTS/sessions.mjs" --all | grep -q "sess-b.jsonl" || fail "--all lists every project"
[ "$(node "$SCRIPTS/sessions.mjs" --cwd "$PROJ" --limit 1 | grep -c .)" = 1 ] || fail "--limit"
if node "$SCRIPTS/sessions.mjs" --cwd "$TMP/nothing" 2>/dev/null; then fail "no sessions should exit 1"; fi

### collect (SessionEnd hook)
Q="$CLAUDE_CONFIG_DIR/aisoul/retro-queue.tsv"
hook() { printf '{"session_id":"x","transcript_path":"%s","cwd":"%s","reason":"exit"}' "$1" "$2" | node "$SCRIPTS/collect.mjs"; }
hook "$A" "$PROJ"
[ ! -e "$Q" ] || fail "collector must be inert without opt-in"
mkdir -p "$CLAUDE_CONFIG_DIR/aisoul" && touch "$CLAUDE_CONFIG_DIR/aisoul/retro-collect"
hook "$A" "$PROJ"
grep -q "sess-a.jsonl	9	2	2	errors,interrupted" "$Q" || fail "queued with counts and reasons: $(cat "$Q")"
hook "$B" "$TMP/elsewhere"
[ "$(grep -c . "$Q")" = 1 ] || fail "quiet session must not be queued"
AISOUL_RETRO_SKIP=1 hook "$A" "$PROJ"
RETRO_IGNORE='/work/' hook "$A" "$PROJ"
[ "$(grep -c . "$Q")" = 1 ] || fail "skip and ignore must not queue"
echo 'not json' | node "$SCRIPTS/collect.mjs" || fail "bad input must still exit 0"
printf '{"transcript_path":"%s/nope.jsonl"}' "$TMP" | node "$SCRIPTS/collect.mjs" || fail "missing transcript must exit 0"
hook "$A" "$PROJ"

qs="$(node "$SCRIPTS/sessions.mjs" --queue --cwd "$PROJ")"
[ "$(grep -c . <<<"$qs")" = 1 ] || fail "queue lists a session once: $qs"
if node "$SCRIPTS/sessions.mjs" --queue --cwd "$TMP/elsewhere" 2>/dev/null; then fail "empty queue for another project should exit 1"; fi
node "$SCRIPTS/sessions.mjs" --drop "$A" | grep -q 'queue: 0 left' || fail "drop"

### usage
us="$(node "$SCRIPTS/usage.mjs" --days 100000 pr-describe untangle-audit)"
echo "$us"
grep -qP '^1\t1\t2026-11-20\taisoul:pr-describe$' <<<"$us" || fail "skill use counted"
grep -qP '^1\t1\t2026-11-20\taisoul:pr-risk$' <<<"$us"     || fail "slash command counted"
grep -qP '^0\t0\t-\tuntangle-audit$' <<<"$us"              || fail "unused known skill listed as 0"
if grep -qP '\tpr-describe$' <<<"$us"; then fail "known name matched to its plugin form must not be listed twice"; fi
if node "$SCRIPTS/usage.mjs" --days x 2>/dev/null; then fail "bad --days should exit 2"; fi

echo "retro: OK"
