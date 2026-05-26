#!/usr/bin/env bash
# test-pretool-guard.sh — verify pre-tool.sh guard conditions
# These should pass even before C1 is fixed (guard logic is env-based, not stdin-based)
set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="${PLUGIN_ROOT}/hooks/pre-tool.sh"

PASS=0
FAIL=0
pass() { echo "  PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*"; FAIL=$((FAIL+1)); }

# Test 1: DISABLE_MULTICA_PLUGIN=1 → exit 0 regardless
result=$(DISABLE_MULTICA_PLUGIN=1 MULTICA_ISSUE_ID=MUL-1 MULTICA_AGENT_SESSION=1 \
  bash "$HOOK" < /dev/null; echo "exit:$?")
if echo "$result" | grep -q "exit:0"; then
  pass "DISABLE_MULTICA_PLUGIN=1 exits 0"
else
  fail "DISABLE_MULTICA_PLUGIN=1 should exit 0, got: $result"
fi

# Test 2: no MULTICA_ISSUE_ID, MULTICA_AGENT_SESSION=0 → not multica session → exit 0
result=$(DISABLE_MULTICA_PLUGIN=0 MULTICA_AGENT_SESSION=0 \
  bash "$HOOK" < /dev/null 2>/dev/null; echo "exit:$?")
if echo "$result" | grep -q "exit:0"; then
  pass "non-daemon session exits 0"
else
  fail "non-daemon session should exit 0, got: $result"
fi

# Test 3: non-Bash tool name → exit 0 (pass through)
result=$(MULTICA_ISSUE_ID=MUL-1 MULTICA_AGENT_SESSION=1 CLAUDE_TOOL_NAME=Read \
  bash "$HOOK" < /dev/null 2>/dev/null; echo "exit:$?")
if echo "$result" | grep -q "exit:0"; then
  pass "non-Bash tool exits 0"
else
  fail "non-Bash tool should exit 0, got: $result"
fi

echo "  ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
