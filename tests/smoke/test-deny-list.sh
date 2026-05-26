#!/usr/bin/env bash
# test-deny-list.sh — verify deny list blocks destructive commands via stdin JSON
# (Claude Code PreToolUse hook contract: data arrives on stdin as JSON)
set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="${PLUGIN_ROOT}/hooks/pre-tool.sh"

PASS=0
FAIL=0
pass()  { echo "  PASS: $*";  PASS=$((PASS+1)); }
fail()  { echo "  FAIL: $*";  FAIL=$((FAIL+1)); }

run_hook_with_stdin() {
  local json="$1"
  echo "$json" | MULTICA_ISSUE_ID=MUL-1 MULTICA_AGENT_SESSION=1 \
    MULTICA_PLUGIN_ROOT="$PLUGIN_ROOT" \
    bash "$HOOK" 2>/dev/null
  return $?
}

# --- Tests that should BLOCK (exit 1) ---

DENY_JSON='{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}'
if ! run_hook_with_stdin "$DENY_JSON"; then
  pass "rm -rf / blocked"
else
  fail "rm -rf / should be blocked"
fi

DENY_JSON='{"tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}'
if ! run_hook_with_stdin "$DENY_JSON"; then
  pass "git push --force blocked"
else
  fail "git push --force should be blocked"
fi

DENY_JSON='{"tool_name":"Bash","tool_input":{"command":"git reset --hard HEAD~5"}}'
if ! run_hook_with_stdin "$DENY_JSON"; then
  pass "git reset --hard blocked"
else
  fail "git reset --hard should be blocked"
fi

# --- Tests that should ALLOW (exit 0) ---

ALLOW_JSON='{"tool_name":"Bash","tool_input":{"command":"git status"}}'
if run_hook_with_stdin "$ALLOW_JSON"; then
  pass "git status allowed"
else
  fail "git status should be allowed"
fi

ALLOW_JSON='{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
if run_hook_with_stdin "$ALLOW_JSON"; then
  pass "ls -la allowed"
else
  fail "ls -la should be allowed"
fi

# --- Non-Bash tool should pass through ---
ALLOW_JSON='{"tool_name":"Read","tool_input":{"file_path":"/etc/passwd"}}'
if run_hook_with_stdin "$ALLOW_JSON"; then
  pass "non-Bash tool (Read) allowed"
else
  fail "non-Bash tool should be allowed"
fi

echo "  ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
