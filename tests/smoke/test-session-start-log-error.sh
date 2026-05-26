#!/usr/bin/env bash
# test-session-start-log-error.sh — session-start.sh must output valid JSON
# even when multica CLI is absent (exercises the log_error call path).
# C2 fixed: log_error is now defined in session-start.sh.
set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="${PLUGIN_ROOT}/hooks/session-start.sh"

PASS=0
FAIL=0
pass()  { echo "  PASS: $*";  PASS=$((PASS+1)); }
fail()  { echo "  FAIL: $*";  FAIL=$((FAIL+1)); }

WORKDIR=$(mktemp -d)
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

mkdir -p "${WORKDIR}/.multica/logs"

# Create a learning with a stale file reference to trigger the log_error path.
# Use a path that definitely doesn't exist to trigger stale detection.
LEARNINGS="${WORKDIR}/.multica/learnings.jsonl"
TS="2020-01-01T00:00:00Z"
cat > "$LEARNINGS" <<EOF
{"ts":"${TS}","skill":"test","type":"constraint","key":"stale-key","insight":"test insight","confidence":9,"source":"TEST-001","branch":"main","commit":"","files":["${WORKDIR}/nonexistent-file.txt"]}
EOF

# Run hook without MULTICA_ISSUE_ID so multica comment is never called
# (avoids stdout pollution from multica CLI response)
output=$(MULTICA_AGENT_SESSION=1 MULTICA_WORKDIR="$WORKDIR" \
  MULTICA_PLUGIN_ROOT="$PLUGIN_ROOT" \
  bash "$HOOK" 2>/dev/null)
exit_code=$?

# Check 1: hook must exit 0
if [[ $exit_code -eq 0 ]]; then
  pass "hook exits 0"
else
  fail "hook should exit 0 (log_error undefined would cause abort)"
fi

# Check 2: output must be valid JSON
if echo "$output" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  pass "output is valid JSON"
else
  fail "output must be valid JSON — got: ${output:0:100}"
fi

# Check 3: output must contain hookSpecificOutput key
if echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'hookSpecificOutput' in d" 2>/dev/null; then
  pass "output contains hookSpecificOutput"
else
  fail "output must contain hookSpecificOutput"
fi

# Check 4: stale learning should appear in context
if echo "$output" | python3 -c "
import json,sys
d=json.load(sys.stdin)
ctx=d.get('hookSpecificOutput',{}).get('additionalContext','')
assert 'stale-key' in ctx or 'possibly stale' in ctx, 'stale key not in context'
" 2>/dev/null; then
  pass "stale learning appears in context"
else
  fail "stale learning should appear in context"
fi

echo "  ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
