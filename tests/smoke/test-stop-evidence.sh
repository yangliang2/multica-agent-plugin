#!/usr/bin/env bash
# test-stop-evidence.sh — evidence file gate for Verification Iron Law
# stop.sh must reject DONE if any passes=true story lacks an evidence file
set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="${PLUGIN_ROOT}/hooks/stop.sh"

PASS=0
FAIL=0
pass()  { echo "  PASS: $*"; PASS=$((PASS+1)); }
fail()  { echo "  FAIL: $*"; FAIL=$((FAIL+1)); }

WORKDIR=$(mktemp -d)
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

ISSUE_ID="TEST-EV-001"
STATE_DIR="${WORKDIR}/.multica/state/${ISSUE_ID}"
EVIDENCE_DIR="${STATE_DIR}/evidence"
mkdir -p "$STATE_DIR" "$EVIDENCE_DIR"
mkdir -p "${WORKDIR}/.multica/logs"

DONE_FILE=$(mktemp)
echo '<promise>DONE</promise>' > "$DONE_FILE"

# --- Test 1: passes=true story WITHOUT evidence file → DONE rejected ---
cat > "${STATE_DIR}/loop.json" <<EOF
{"active":true,"iteration":1,"max_iterations":50,"issue_id":"${ISSUE_ID}","phase":"execute","stories":[{"id":"S1","title":"story1","acceptance":"test","passes":true}]}
EOF

result=$(MULTICA_ISSUE_ID="$ISSUE_ID" MULTICA_WORKDIR="$WORKDIR" \
  MULTICA_OUTPUT_FILE="$DONE_FILE" MULTICA_AGENT_SESSION=1 \
  bash "$HOOK" 2>/dev/null; echo "exit:$?")
EXIT_CODE=$(echo "$result" | grep -o "exit:[0-9]*" | cut -d: -f2)

if [[ "$EXIT_CODE" != "0" ]]; then
  pass "DONE rejected when evidence file missing"
else
  fail "DONE should be rejected when evidence file missing"
fi

# --- Test 2: passes=true story WITH evidence file → DONE accepted ---
cat > "${EVIDENCE_DIR}/S1.txt" <<EOF
command: pytest tests/test_foo.py
exit_code: 0
output_hash: abc12345
summary: 1 passed in 0.12s
EOF

result=$(MULTICA_ISSUE_ID="$ISSUE_ID" MULTICA_WORKDIR="$WORKDIR" \
  MULTICA_OUTPUT_FILE="$DONE_FILE" MULTICA_AGENT_SESSION=1 \
  bash "$HOOK" 2>/dev/null; echo "exit:$?")
EXIT_CODE=$(echo "$result" | grep -o "exit:[0-9]*" | cut -d: -f2)

if [[ "$EXIT_CODE" == "0" ]]; then
  pass "DONE accepted when evidence file present"
else
  fail "DONE should be accepted when evidence file present (exit: $EXIT_CODE)"
fi

# --- Test 3: passes=true story with EMPTY evidence file → DONE rejected ---
cat > "${STATE_DIR}/loop.json" <<EOF
{"active":true,"iteration":2,"max_iterations":50,"issue_id":"${ISSUE_ID}","phase":"execute","stories":[{"id":"S2","title":"story2","acceptance":"test","passes":true}]}
EOF
touch "${EVIDENCE_DIR}/S2.txt"  # empty file

result=$(MULTICA_ISSUE_ID="$ISSUE_ID" MULTICA_WORKDIR="$WORKDIR" \
  MULTICA_OUTPUT_FILE="$DONE_FILE" MULTICA_AGENT_SESSION=1 \
  bash "$HOOK" 2>/dev/null; echo "exit:$?")
EXIT_CODE=$(echo "$result" | grep -o "exit:[0-9]*" | cut -d: -f2)

if [[ "$EXIT_CODE" != "0" ]]; then
  pass "DONE rejected when evidence file is empty"
else
  fail "DONE should be rejected when evidence file is empty"
fi

# --- Test 4: passes=false story with no evidence → DONE not triggered (loop continues) ---
cat > "${STATE_DIR}/loop.json" <<EOF
{"active":true,"iteration":3,"max_iterations":50,"issue_id":"${ISSUE_ID}","phase":"execute","stories":[{"id":"S3","title":"story3","acceptance":"test","passes":false}]}
EOF

result=$(MULTICA_ISSUE_ID="$ISSUE_ID" MULTICA_WORKDIR="$WORKDIR" \
  MULTICA_OUTPUT_FILE="$DONE_FILE" MULTICA_AGENT_SESSION=1 \
  bash "$HOOK" 2>/dev/null; echo "exit:$?")
EXIT_CODE=$(echo "$result" | grep -o "exit:[0-9]*" | cut -d: -f2)

if [[ "$EXIT_CODE" == "2" ]]; then
  pass "loop continues (exit 2) when story still failing"
else
  fail "should exit 2 when story still failing (got exit: $EXIT_CODE)"
fi

rm -f "$DONE_FILE"
echo "  ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
