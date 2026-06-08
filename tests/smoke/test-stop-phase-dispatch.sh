#!/usr/bin/env bash
# test-stop-phase-dispatch.sh — v2.3.0 phase dispatch behavior in stop.sh
#
# Covers:
#   1. phase=spec  + DONE → exit 0 (checkpoint, no evidence gate)
#   2. phase=demo  + DONE → exit 0 (checkpoint, no evidence gate)
#   3. phase=plan  + DONE → exit 0, loop.json.phase updated to "demo"
#   4. phase=verify+ DONE → exit 0, loop.json.phase updated to "result"
#   5. phase=""    + no DONE → exit 2 (v2.2.0 backward compat)
#   6. phase=execution + no DONE → exit 2 (v2.2.0 backward compat)
set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="${PLUGIN_ROOT}/hooks/stop.sh"

PASS=0; FAIL=0
pass() { echo "  PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*"; FAIL=$((FAIL+1)); }

WORKDIR=$(mktemp -d)
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

ISSUE_ID="PHASE-DISPATCH-TEST-001"
STATE_DIR="${WORKDIR}/.multica/state/${ISSUE_ID}"
mkdir -p "$STATE_DIR" "${WORKDIR}/.multica/logs"

DONE_STDIN='{"stop_hook_active":true,"agent_output":"<promise>DONE</promise>"}'
NO_DONE_STDIN='{"stop_hook_active":true}'

# Write a fresh loop.json with the given phase (no stories — checkpoint phases skip evidence gate)
write_loop() {
  local _phase="$1"
  cat > "${STATE_DIR}/loop.json" <<EOF
{"active":true,"iteration":1,"max_iterations":50,"issue_id":"${ISSUE_ID}","phase":"${_phase}"}
EOF
}

# Run hook and store exit code in global _rc; discard stdout (M7 JSON noise)
run_hook() {
  local _stdin="$1"
  MULTICA_ISSUE_ID="$ISSUE_ID" MULTICA_WORKDIR="$WORKDIR" MULTICA_AGENT_SESSION=1 \
    bash "$HOOK" <<< "$_stdin" >/dev/null 2>/dev/null
  _rc=$?
}

read_phase() {
  python3 -c "
import json, sys
try: print(json.load(open(sys.argv[1])).get('phase',''))
except: print('')
" "${STATE_DIR}/loop.json" 2>/dev/null
}

# --- Test 1: phase=spec + DONE → exit 0 (checkpoint phase) ---
write_loop "spec"
run_hook "$DONE_STDIN"; rc=$_rc
if [[ "$rc" -eq 0 ]]; then
  pass "phase=spec + DONE: exit 0 (checkpoint, not exit 2)"
else
  fail "phase=spec + DONE: expected exit 0, got $rc"
fi

# --- Test 2: phase=demo + DONE → exit 0 (checkpoint phase) ---
write_loop "demo"
run_hook "$DONE_STDIN"; rc=$_rc
if [[ "$rc" -eq 0 ]]; then
  pass "phase=demo + DONE: exit 0 (checkpoint, not exit 2)"
else
  fail "phase=demo + DONE: expected exit 0, got $rc"
fi

# --- Test 3: phase=plan + DONE → exit 0 AND loop.json.phase="demo" ---
write_loop "plan"
run_hook "$DONE_STDIN"; rc=$_rc
new_phase=$(read_phase)
if [[ "$rc" -eq 0 ]]; then
  pass "phase=plan + DONE: exit 0 (auto-advance)"
else
  fail "phase=plan + DONE: expected exit 0, got $rc"
fi
if [[ "$new_phase" == "demo" ]]; then
  pass "phase=plan + DONE: loop.json.phase advanced to 'demo'"
else
  fail "phase=plan + DONE: expected phase='demo', got '${new_phase}'"
fi

# --- Test 4: phase=verify + DONE → exit 0 AND loop.json.phase="result" ---
write_loop "verify"
run_hook "$DONE_STDIN"; rc=$_rc
new_phase=$(read_phase)
if [[ "$rc" -eq 0 ]]; then
  pass "phase=verify + DONE: exit 0 (auto-advance)"
else
  fail "phase=verify + DONE: expected exit 0, got $rc"
fi
if [[ "$new_phase" == "result" ]]; then
  pass "phase=verify + DONE: loop.json.phase advanced to 'result'"
else
  fail "phase=verify + DONE: expected phase='result', got '${new_phase}'"
fi

# --- Test 5: phase="" (empty) + no DONE → exit 2 (v2.2.0 backward compat) ---
write_loop ""
run_hook "$NO_DONE_STDIN"; rc=$_rc
if [[ "$rc" -eq 2 ]]; then
  pass "phase='' + no DONE: exit 2 (v2.2.0 backward compat preserved)"
else
  fail "phase='' + no DONE: expected exit 2 (backward compat), got $rc"
fi

# --- Test 6: phase=execution + no DONE → exit 2 (v2.2.0 backward compat) ---
write_loop "execution"
run_hook "$NO_DONE_STDIN"; rc=$_rc
if [[ "$rc" -eq 2 ]]; then
  pass "phase=execution + no DONE: exit 2 (v2.2.0 backward compat preserved)"
else
  fail "phase=execution + no DONE: expected exit 2 (backward compat), got $rc"
fi

echo "  ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
