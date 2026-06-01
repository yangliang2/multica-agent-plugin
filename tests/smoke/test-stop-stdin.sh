#!/usr/bin/env bash
# test-stop-stdin.sh — stop.sh must detect DONE signal from stdin JSON
# (C1: Claude Code Stop hook contract passes data via stdin, not CLAUDE_TOOL_OUTPUT)
set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="${PLUGIN_ROOT}/hooks/stop.sh"

PASS=0
FAIL=0
pass() { echo "  PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*"; FAIL=$((FAIL+1)); }

WORKDIR=$(mktemp -d)
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

ISSUE_ID="STDIN-TEST-001"
STATE_DIR="${WORKDIR}/.multica/state/${ISSUE_ID}"
EVIDENCE_DIR="${STATE_DIR}/evidence"
mkdir -p "$STATE_DIR" "$EVIDENCE_DIR" "${WORKDIR}/.multica/logs"

# Passing evidence file for story S1
cat > "${EVIDENCE_DIR}/S1.txt" <<'EOF'
command: pytest tests/test_foo.py
exit_code: 0
output_hash: abc12345
summary: 1 passed in 0.12s
EOF

reset_loop() {
  cat > "${STATE_DIR}/loop.json" <<EOF
{"active":true,"iteration":1,"max_iterations":50,"issue_id":"${ISSUE_ID}","phase":"execute","stories":[{"id":"S1","title":"story1","acceptance":"test","passes":true}]}
EOF
}

# --- Test 1: DONE in raw stdin content → hook should NOT block (exit != 2) ---
reset_loop
MULTICA_ISSUE_ID="$ISSUE_ID" MULTICA_WORKDIR="$WORKDIR" MULTICA_AGENT_SESSION=1 \
  bash "$HOOK" <<< '{"stop_hook_active":true,"agent_output":"<promise>DONE</promise>"}' \
  2>/dev/null
_rc=$?
if [[ "$_rc" -ne 2 ]]; then
  pass "DONE in stdin content: hook does not block (exit ${_rc})"
else
  fail "DONE in stdin content: hook should not block (exit 2 = still blocking)"
fi

# --- Test 2: no DONE in stdin, no MULTICA_OUTPUT_FILE → hook blocks (exit 2) ---
reset_loop
MULTICA_ISSUE_ID="$ISSUE_ID" MULTICA_WORKDIR="$WORKDIR" MULTICA_AGENT_SESSION=1 \
  bash "$HOOK" <<< '{"stop_hook_active":true}' \
  2>/dev/null
_rc=$?
if [[ "$_rc" -eq 2 ]]; then
  pass "no DONE signal in stdin: hook blocks (exit 2)"
else
  fail "no DONE signal in stdin: hook should block with exit 2 (got exit ${_rc})"
fi

# --- Test 3: DONE in transcript_path file → hook should NOT block ---
reset_loop
TRANSCRIPT=$(mktemp)
echo '<promise>DONE</promise>' > "$TRANSCRIPT"
MULTICA_ISSUE_ID="$ISSUE_ID" MULTICA_WORKDIR="$WORKDIR" MULTICA_AGENT_SESSION=1 \
  bash "$HOOK" <<< "{\"stop_hook_active\":true,\"transcript_path\":\"${TRANSCRIPT}\"}" \
  2>/dev/null
_rc=$?
rm -f "$TRANSCRIPT"
if [[ "$_rc" -ne 2 ]]; then
  pass "DONE in transcript_path file: hook does not block (exit ${_rc})"
else
  fail "DONE in transcript_path file: hook should not block (exit 2 = still blocking)"
fi

# --- Test 4: M7 — exit 2 (block) must write JSON with additionalContext to stdout ---
reset_loop
stdout=$(MULTICA_ISSUE_ID="$ISSUE_ID" MULTICA_WORKDIR="$WORKDIR" MULTICA_AGENT_SESSION=1 \
  bash "$HOOK" <<< '{"stop_hook_active":true}' 2>/dev/null)
if printf '%s' "$stdout" | python3 -c "
import json, sys
d = json.load(sys.stdin)
ctx = d.get('hookSpecificOutput', {}).get('additionalContext', '')
sys.exit(0 if ctx else 1)
" 2>/dev/null; then
  pass "exit 2 block writes additionalContext JSON to stdout (M7)"
else
  fail "exit 2 block missing additionalContext in stdout (M7)"
fi

echo "  ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
