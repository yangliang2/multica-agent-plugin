#!/usr/bin/env bash
# test-pretool-rate-limit.sh — destructive-guard comment rate-limit
# Two rapid deny-list hits on the same issue should only post one comment.
set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="${PLUGIN_ROOT}/hooks/pre-tool.sh"

PASS=0; FAIL=0
pass() { echo "  PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*"; FAIL=$((FAIL+1)); }

WORKDIR=$(mktemp -d)
WORKDIR2=$(mktemp -d)
cleanup() { rm -rf "$WORKDIR" "$WORKDIR2"; }
trap cleanup EXIT

ISSUE_ID="TEST-RATE-001"
mkdir -p "${WORKDIR}/.multica/state/${ISSUE_ID}" "${WORKDIR}/.multica/logs"

# Build a fake hook input for a blocked command
make_input() {
  python3 -c "import json,sys; print(json.dumps({'tool_name':'Bash','tool_input':{'command':sys.argv[1]}}))" "$1"
}

# Test 1: first blocked call — rate file should be created
input=$(make_input "rm -rf /")
printf '%s' "$input" | MULTICA_AGENT_SESSION=1 MULTICA_WORKDIR="$WORKDIR" \
  MULTICA_ISSUE_ID="$ISSUE_ID" MULTICA_PLUGIN_ROOT="$PLUGIN_ROOT" \
  bash "$HOOK" 2>/dev/null
if [[ -f "${WORKDIR}/.multica/state/${ISSUE_ID}/pretool-comment-rate.txt" ]]; then
  pass "rate file created after first blocked call"
else
  fail "rate file should be created after first blocked call"
fi

# Test 2: second blocked call within 60s — rate file timestamp should be same (not updated)
_ts_before=$(cat "${WORKDIR}/.multica/state/${ISSUE_ID}/pretool-comment-rate.txt" 2>/dev/null || echo 0)
printf '%s' "$input" | MULTICA_AGENT_SESSION=1 MULTICA_WORKDIR="$WORKDIR" \
  MULTICA_ISSUE_ID="$ISSUE_ID" MULTICA_PLUGIN_ROOT="$PLUGIN_ROOT" \
  bash "$HOOK" 2>/dev/null
_ts_after=$(cat "${WORKDIR}/.multica/state/${ISSUE_ID}/pretool-comment-rate.txt" 2>/dev/null || echo 0)
if [[ "$_ts_before" == "$_ts_after" ]]; then
  pass "rate file not updated on second call within 60s (rate limited)"
else
  fail "rate file should not be updated within 60s window"
fi

# Test 3: non-daemon session — no rate file should be created
mkdir -p "${WORKDIR2}/.multica/state/TEST-RATE-002"
printf '%s' "$input" | MULTICA_AGENT_SESSION=0 MULTICA_WORKDIR="$WORKDIR2" \
  MULTICA_PLUGIN_ROOT="$PLUGIN_ROOT" \
  bash "$HOOK" 2>/dev/null
if [[ ! -f "${WORKDIR2}/.multica/state/TEST-RATE-002/pretool-comment-rate.txt" ]]; then
  pass "no rate file in non-daemon session"
else
  fail "rate file should not be created in non-daemon session"
fi

echo "  ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
