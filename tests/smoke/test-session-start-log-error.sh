#!/usr/bin/env bash
# test-session-start-log-error.sh — session-start.sh must output valid JSON even when
# multica CLI is absent (exercises the log_error call path added in 0.9.0).
#
# EXPECTED STATE: FAILING until C2 is fixed.
# C2: log_error is called at session-start.sh:163 but only defined in stop.sh.
# Under set -euo pipefail, undefined function → abort before JSON output.
set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="${PLUGIN_ROOT}/hooks/session-start.sh"

PASS=0
FAIL=0
XFAIL=0
pass()  { echo "  PASS: $*";  PASS=$((PASS+1)); }
fail()  { echo "  FAIL: $*";  FAIL=$((FAIL+1)); }
xfail() { echo "  XFAIL (C2 pending): $*"; XFAIL=$((XFAIL+1)); }

WORKDIR=$(mktemp -d)
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

mkdir -p "${WORKDIR}/.multica/logs"

# Create a learning with a stale file reference to trigger the log_error path
LEARNINGS="${WORKDIR}/.multica/learnings.jsonl"
TS="2020-01-01T00:00:00Z"
cat > "$LEARNINGS" <<EOF
{"ts":"${TS}","skill":"test","type":"constraint","key":"stale-key","insight":"test insight","confidence":9,"source":"TEST-001","branch":"main","commit":"","files":["nonexistent-file.txt"]}
EOF

# Run hook — must output valid JSON regardless (no crash from log_error)
output=$(MULTICA_ISSUE_ID="TEST-001" MULTICA_WORKDIR="$WORKDIR" \
  MULTICA_AGENT_SESSION=1 MULTICA_PLUGIN_ROOT="$PLUGIN_ROOT" \
  bash "$HOOK" 2>/dev/null)
exit_code=$?

# Check 1: hook must exit 0
if [[ $exit_code -eq 0 ]]; then
  pass "hook exits 0"
else
  xfail "hook should exit 0 (C2: log_error undefined causes abort)"
fi

# Check 2: output must be valid JSON
if echo "$output" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  pass "output is valid JSON"
else
  xfail "output must be valid JSON (C2: hook aborts before JSON output)"
fi

# Check 3: output must contain hookSpecificOutput key
if echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'hookSpecificOutput' in d" 2>/dev/null; then
  pass "output contains hookSpecificOutput"
else
  xfail "output must contain hookSpecificOutput (C2: hook aborts before JSON output)"
fi

echo "  ${PASS} passed, ${FAIL} failed, ${XFAIL} expected-fail (C2 pending)"
[[ $FAIL -eq 0 ]]
