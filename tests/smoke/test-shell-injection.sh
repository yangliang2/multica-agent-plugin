#!/usr/bin/env bash
# test-shell-injection.sh — verify hooks don't inject shell metacharacters
# Tests all python3 -c calls in hooks with adversarial path/id values.
set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

PASS=0; FAIL=0
pass() { echo "  PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*"; FAIL=$((FAIL+1)); }

# Adversarial values that would break unquoted shell interpolation
EVIL_PATHS=(
  "/tmp/work dir with spaces"
  "/tmp/work'quote"
  '/tmp/work"dquote'
  "/tmp/work\$dollar"
  "/tmp/work|pipe"
  "/tmp/work;semi"
)
EVIL_IDS=(
  "ISSUE-001'; rm -rf /tmp/evil #"
  'ISSUE-002" && echo pwned'
  "ISSUE-003\$(touch /tmp/injected)"
  "ISSUE-004|cat /etc/passwd"
)

# --- Test 1: session-start.sh with adversarial MULTICA_WORKDIR ---
for evil in "${EVIL_PATHS[@]}"; do
  mkdir -p "${evil}/.multica/logs" 2>/dev/null || true
  output=$(MULTICA_AGENT_SESSION=1 MULTICA_WORKDIR="$evil" \
    MULTICA_PLUGIN_ROOT="$PLUGIN_ROOT" \
    bash "${PLUGIN_ROOT}/hooks/session-start.sh" 2>/dev/null; echo "exit:$?")
  exit_code=$(echo "$output" | grep -o "exit:[0-9]*" | cut -d: -f2)
  if [[ "$exit_code" == "0" ]] || [[ "$exit_code" == "1" ]]; then
    pass "session-start: safe with WORKDIR='${evil}'"
  else
    fail "session-start: unexpected exit $exit_code with WORKDIR='${evil}'"
  fi
  rm -rf "$evil" 2>/dev/null || true
done

# --- Test 2: session-start.sh with adversarial MULTICA_ISSUE_ID ---
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
mkdir -p "${WORKDIR}/.multica/logs"
for evil_id in "${EVIL_IDS[@]}"; do
  output=$(MULTICA_AGENT_SESSION=1 MULTICA_WORKDIR="$WORKDIR" \
    MULTICA_ISSUE_ID="$evil_id" \
    MULTICA_PLUGIN_ROOT="$PLUGIN_ROOT" \
    bash "${PLUGIN_ROOT}/hooks/session-start.sh" 2>/dev/null; echo "exit:$?")
  exit_code=$(echo "$output" | grep -o "exit:[0-9]*" | cut -d: -f2)
  if [[ "$exit_code" == "0" ]] || [[ "$exit_code" == "1" ]]; then
    pass "session-start: safe with ISSUE_ID='${evil_id}'"
  else
    fail "session-start: unexpected exit $exit_code with ISSUE_ID='${evil_id}'"
  fi
done

# --- Test 3: pre-tool.sh with adversarial MULTICA_WORKDIR ---
input=$(python3 -c "import json; print(json.dumps({'tool_name':'Bash','tool_input':{'command':'ls -la'}}))")
for evil in "${EVIL_PATHS[@]}"; do
  mkdir -p "${evil}/.multica/logs" 2>/dev/null || true
  output=$(printf '%s' "$input" | \
    MULTICA_AGENT_SESSION=1 MULTICA_WORKDIR="$evil" \
    MULTICA_PLUGIN_ROOT="$PLUGIN_ROOT" \
    bash "${PLUGIN_ROOT}/hooks/pre-tool.sh" 2>/dev/null; echo "exit:$?")
  exit_code=$(echo "$output" | grep -o "exit:[0-9]*" | cut -d: -f2)
  if [[ "$exit_code" == "0" ]]; then
    pass "pre-tool: safe with WORKDIR='${evil}'"
  else
    fail "pre-tool: unexpected exit $exit_code with WORKDIR='${evil}'"
  fi
  rm -rf "$evil" 2>/dev/null || true
done

# --- Test 4: no files created outside WORKDIR during adversarial runs ---
if [[ ! -f /tmp/injected ]]; then
  pass "no injection artifacts created in /tmp"
else
  fail "injection artifact /tmp/injected was created"
  rm -f /tmp/injected
fi

echo "  ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
