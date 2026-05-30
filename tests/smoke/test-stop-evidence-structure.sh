#!/usr/bin/env bash
# test-stop-evidence-structure.sh — H3 evidence content structure check
# Evidence files must contain at least one structured field.
set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="${PLUGIN_ROOT}/hooks/stop.sh"

PASS=0; FAIL=0
pass() { echo "  PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*"; FAIL=$((FAIL+1)); }

WORKDIR=$(mktemp -d)
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

ISSUE_ID="TEST-STRUCT-001"
STATE_DIR="${WORKDIR}/.multica/state/${ISSUE_ID}"
EVIDENCE_DIR="${STATE_DIR}/evidence"
mkdir -p "$STATE_DIR" "$EVIDENCE_DIR" "${WORKDIR}/.multica/logs"

DONE_FILE=$(mktemp)
echo '<promise>DONE</promise>' > "$DONE_FILE"

run_hook() {
  MULTICA_ISSUE_ID="$ISSUE_ID" MULTICA_WORKDIR="$WORKDIR" \
    MULTICA_OUTPUT_FILE="$DONE_FILE" MULTICA_AGENT_SESSION=1 \
    bash "$HOOK" 2>/dev/null; echo "exit:$?"
}

# --- Test 1: freeform text evidence (no structured fields) → DONE rejected ---
cat > "${STATE_DIR}/loop.json" <<EOF
{"active":true,"iteration":1,"max_iterations":50,"issue_id":"${ISSUE_ID}","phase":"execute","stories":[{"id":"S1","title":"story1","acceptance":"test","passes":true}]}
EOF
echo "Tests passed, everything looks good!" > "${EVIDENCE_DIR}/S1.txt"

result=$(run_hook)
EXIT_CODE=$(echo "$result" | grep -o "exit:[0-9]*" | cut -d: -f2)
if [[ "$EXIT_CODE" != "0" ]]; then
  pass "freeform text evidence rejected (no structured fields)"
else
  fail "freeform text evidence should be rejected"
fi

# --- Test 2: structured evidence with exit_code: → DONE accepted ---
cat > "${EVIDENCE_DIR}/S1.txt" <<EOF
command: npm test
exit_code: 0
summary: 15 tests passed
EOF

result=$(run_hook)
EXIT_CODE=$(echo "$result" | grep -o "exit:[0-9]*" | cut -d: -f2)
if [[ "$EXIT_CODE" == "0" ]]; then
  pass "structured evidence with exit_code: accepted"
else
  fail "structured evidence should be accepted (exit: $EXIT_CODE)"
fi

# --- Test 3: structured evidence with summary: only → DONE accepted ---
cat > "${STATE_DIR}/loop.json" <<EOF
{"active":true,"iteration":2,"max_iterations":50,"issue_id":"${ISSUE_ID}","phase":"execute","stories":[{"id":"S2","title":"story2","acceptance":"test","passes":true}]}
EOF
echo "summary: all checks green" > "${EVIDENCE_DIR}/S2.txt"

result=$(run_hook)
EXIT_CODE=$(echo "$result" | grep -o "exit:[0-9]*" | cut -d: -f2)
if [[ "$EXIT_CODE" == "0" ]]; then
  pass "evidence with summary: field accepted"
else
  fail "evidence with summary: should be accepted (exit: $EXIT_CODE)"
fi

# --- Test 4: empty evidence → still rejected ---
cat > "${STATE_DIR}/loop.json" <<EOF
{"active":true,"iteration":3,"max_iterations":50,"issue_id":"${ISSUE_ID}","phase":"execute","stories":[{"id":"S3","title":"story3","acceptance":"test","passes":true}]}
EOF
touch "${EVIDENCE_DIR}/S3.txt"

result=$(run_hook)
EXIT_CODE=$(echo "$result" | grep -o "exit:[0-9]*" | cut -d: -f2)
if [[ "$EXIT_CODE" != "0" ]]; then
  pass "empty evidence still rejected"
else
  fail "empty evidence should still be rejected"
fi

rm -f "$DONE_FILE"
echo "  ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
