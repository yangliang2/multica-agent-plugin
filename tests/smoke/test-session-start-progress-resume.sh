#!/usr/bin/env bash
# test-session-start-progress-resume.sh — REQ-06-03 context-handoff resume
#
# Covers:
#   1. loop.json.progress → "Saved Progress" section with current_step + pct + done list
#   2. no progress field → no Saved Progress section
#   3. control chars / newlines in progress strings are normalized
#   4. output remains valid JSON
set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="${PLUGIN_ROOT}/hooks/session-start.sh"

PASS=0; FAIL=0
pass() { echo "  PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*"; FAIL=$((FAIL+1)); }

WORKDIR=$(mktemp -d)
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

ISSUE_ID="PROGRESS-RESUME-TEST-001"
STATE_DIR="${WORKDIR}/.multica/state/${ISSUE_ID}"
mkdir -p "$STATE_DIR" "${WORKDIR}/.multica/logs"

run_hook() {
  MULTICA_ISSUE_ID="$ISSUE_ID" MULTICA_WORKDIR="$WORKDIR" MULTICA_AGENT_SESSION=1 \
    bash "$HOOK" 2>/dev/null
}

# --- Test 1: progress fields injected ---
cat > "${STATE_DIR}/loop.json" <<EOF
{"active":true,"iteration":3,"max_iterations":50,"issue_id":"${ISSUE_ID}","phase":"execute","mode":"execution","verification_cmd":"true",
 "progress":{"current_step":"wire-up-auth-routes","pct":60,"completed_steps":["scaffold","db-schema"],"summary":"auth module half done"}}
EOF
OUT=$(run_hook)
if printf '%s' "$OUT" | grep -qF "Saved Progress (context handoff)" \
   && printf '%s' "$OUT" | grep -qF "Resume from sub-step: wire-up-auth-routes" \
   && printf '%s' "$OUT" | grep -qF "60% complete" \
   && printf '%s' "$OUT" | grep -qF "scaffold, db-schema"; then
  pass "progress fields injected (current_step, pct, completed_steps)"
else
  fail "Saved Progress section incomplete"
fi

# --- Test 2: no progress → no section ---
cat > "${STATE_DIR}/loop.json" <<EOF
{"active":true,"iteration":1,"max_iterations":50,"issue_id":"${ISSUE_ID}","phase":"execute","mode":"execution","verification_cmd":"true"}
EOF
OUT2=$(run_hook)
if ! printf '%s' "$OUT2" | grep -qF "Saved Progress"; then
  pass "no progress field → no Saved Progress section"
else
  fail "Saved Progress section appeared without progress data"
fi

# --- Test 3: newlines in progress strings normalized ---
python3 - "$STATE_DIR/loop.json" "$ISSUE_ID" <<'PYEOF'
import json, sys
json.dump({
    "active": True, "iteration": 1, "max_iterations": 50,
    "issue_id": sys.argv[2], "phase": "execute", "mode": "execution",
    "verification_cmd": "true",
    "progress": {"current_step": "step\nwith\nnewlines", "pct": 10,
                 "completed_steps": [], "summary": ""},
}, open(sys.argv[1], "w"))
PYEOF
OUT3=$(run_hook)
if printf '%s' "$OUT3" | grep -qF "Resume from sub-step: step with newlines"; then
  pass "newlines in current_step normalized to spaces"
else
  fail "newline normalization failed"
fi

# --- Test 4: output is valid JSON ---
if printf '%s' "$OUT" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null \
   && printf '%s' "$OUT3" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  pass "hook output is valid JSON"
else
  fail "hook output is not valid JSON"
fi

echo "  ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
