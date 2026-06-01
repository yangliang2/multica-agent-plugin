#!/usr/bin/env bash
# test-pretool-guard.sh — verify pre-tool.sh guard conditions (stdin JSON contract)
set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="${PLUGIN_ROOT}/hooks/pre-tool.sh"

PASS=0
FAIL=0
pass() { echo "  PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*"; FAIL=$((FAIL+1)); }

# Test 1: DISABLE_MULTICA_PLUGIN=1 → exit 0 regardless
echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}' \
  | DISABLE_MULTICA_PLUGIN=1 MULTICA_ISSUE_ID=MUL-1 MULTICA_AGENT_SESSION=1 \
    bash "$HOOK" 2>/dev/null
if [[ $? -eq 0 ]]; then
  pass "DISABLE_MULTICA_PLUGIN=1 exits 0"
else
  fail "DISABLE_MULTICA_PLUGIN=1 should exit 0"
fi

# Test 2: no MULTICA_ISSUE_ID, MULTICA_AGENT_SESSION=0 → not multica session → exit 0
echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}' \
  | DISABLE_MULTICA_PLUGIN=0 MULTICA_AGENT_SESSION=0 \
    bash "$HOOK" 2>/dev/null
if [[ $? -eq 0 ]]; then
  pass "non-daemon session exits 0"
else
  fail "non-daemon session should exit 0"
fi

# Test 3: non-Bash tool name → exit 0 (pass through)
echo '{"tool_name":"Read","tool_input":{"file_path":"/etc/passwd"}}' \
  | MULTICA_ISSUE_ID=MUL-1 MULTICA_AGENT_SESSION=1 \
    MULTICA_PLUGIN_ROOT="$PLUGIN_ROOT" \
    bash "$HOOK" 2>/dev/null
if [[ $? -eq 0 ]]; then
  pass "non-Bash tool exits 0"
else
  fail "non-Bash tool should exit 0"
fi

# Test 4: C6 — missing deny list → fail-closed (exit 1, not exit 0)
_tmp_root=$(mktemp -d)
mkdir -p "${_tmp_root}/tools"   # tools/ dir exists but no safe-exec.deny.list
echo '{"tool_name":"Bash","tool_input":{"command":"ls"}}' \
  | MULTICA_ISSUE_ID=MUL-1 MULTICA_AGENT_SESSION=1 \
    MULTICA_PLUGIN_ROOT="$_tmp_root" \
    bash "$HOOK" 2>/dev/null
_rc=$?
rm -rf "$_tmp_root"
if [[ $_rc -eq 1 ]]; then
  pass "missing deny list blocks Bash (fail-closed)"
else
  fail "missing deny list should block Bash with exit 1 (got exit ${_rc})"
fi

echo "  ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
