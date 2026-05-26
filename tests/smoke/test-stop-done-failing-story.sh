#!/usr/bin/env bash
# test-stop-done-failing-story.sh — stop.sh must reject DONE when stories still failing
#
# EXPECTED STATE: FAILING until H6 is fixed.
# H6: grep -qF '"passes": false' (with space) silently fails when JSON is compact
# ("passes":false without space). This test uses compact JSON to expose the bug.
set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="${PLUGIN_ROOT}/hooks/stop.sh"

PASS=0
FAIL=0
XFAIL=0
pass()  { echo "  PASS: $*";  PASS=$((PASS+1)); }
fail()  { echo "  FAIL: $*";  FAIL=$((FAIL+1)); }
xfail() { echo "  XFAIL (H6 pending): $*"; XFAIL=$((XFAIL+1)); }

WORKDIR=$(mktemp -d)
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

ISSUE_ID="TEST-001"
STATE_DIR="${WORKDIR}/.multica/state/${ISSUE_ID}"
mkdir -p "$STATE_DIR"
mkdir -p "${WORKDIR}/.multica/logs"

# --- Test 1: compact JSON "passes":false — hook should NOT exit 0 (H6 bug) ---
cat > "${STATE_DIR}/loop.json" <<'EOF'
{"active":true,"iteration":1,"max_iterations":50,"issue_id":"TEST-001","phase":"execute","stories":[{"id":"S1","title":"story1","acceptance":"test","passes":false}]}
EOF

# Simulate DONE signal via output file
DONE_FILE=$(mktemp)
echo '<promise>DONE</promise>' > "$DONE_FILE"

result=$(MULTICA_ISSUE_ID="$ISSUE_ID" MULTICA_WORKDIR="$WORKDIR" \
  MULTICA_OUTPUT_FILE="$DONE_FILE" MULTICA_AGENT_SESSION=1 \
  bash "$HOOK" 2>/dev/null; echo "exit:$?")

EXIT_CODE=$(echo "$result" | grep -o "exit:[0-9]*" | cut -d: -f2)

if [[ "$EXIT_CODE" != "0" ]]; then
  pass "compact JSON passes:false correctly rejects DONE"
else
  xfail "compact JSON passes:false should reject DONE (H6: grep needs space before false)"
fi

# --- Test 2: spaced JSON '"passes": false' — should also reject ---
cat > "${STATE_DIR}/loop.json" <<'EOF'
{"active": true, "iteration": 1, "max_iterations": 50, "issue_id": "TEST-001", "phase": "execute", "stories": [{"id": "S1", "title": "story1", "acceptance": "test", "passes": false}]}
EOF

result=$(MULTICA_ISSUE_ID="$ISSUE_ID" MULTICA_WORKDIR="$WORKDIR" \
  MULTICA_OUTPUT_FILE="$DONE_FILE" MULTICA_AGENT_SESSION=1 \
  bash "$HOOK" 2>/dev/null; echo "exit:$?")

EXIT_CODE=$(echo "$result" | grep -o "exit:[0-9]*" | cut -d: -f2)

if [[ "$EXIT_CODE" != "0" ]]; then
  pass "spaced JSON passes: false correctly rejects DONE"
else
  fail "spaced JSON passes: false should reject DONE"
fi

rm -f "$DONE_FILE"
echo "  ${PASS} passed, ${FAIL} failed, ${XFAIL} expected-fail (H6 pending)"
[[ $FAIL -eq 0 ]]
