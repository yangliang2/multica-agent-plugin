#!/usr/bin/env bash
# test-session-start-size-limit.sh — M10 learnings.jsonl size guard
# Oversized file should be skipped with a warning in additionalContext.
set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="${PLUGIN_ROOT}/hooks/session-start.sh"

PASS=0; FAIL=0
pass() { echo "  PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*"; FAIL=$((FAIL+1)); }

WORKDIR=$(mktemp -d)
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT
mkdir -p "${WORKDIR}/.multica/logs"

LEARNINGS="${WORKDIR}/.multica/learnings.jsonl"

run_hook() {
  MULTICA_AGENT_SESSION=1 MULTICA_WORKDIR="$WORKDIR" \
    MULTICA_PLUGIN_ROOT="$PLUGIN_ROOT" \
    bash "$HOOK" 2>/dev/null
}

# --- Test 1: normal-sized file → learnings injected ---
cat > "$LEARNINGS" <<'EOF'
{"ts":"2026-01-01T00:00:00Z","skill":"test","type":"pattern","key":"test-key","insight":"test insight","confidence":9,"source":"TEST-001","branch":"main","commit":"","files":[]}
EOF

output=$(run_hook)
if echo "$output" | python3 -c "
import json,sys
d=json.load(sys.stdin)
ctx=d.get('hookSpecificOutput',{}).get('additionalContext','')
assert 'test-key' in ctx or 'test insight' in ctx, 'learning not injected'
" 2>/dev/null; then
  pass "normal-sized learnings injected into context"
else
  fail "normal-sized learnings should be injected"
fi

# --- Test 2: file exceeding 1000 lines → skipped with warning ---
python3 -c "
import json
entry = {'ts':'2026-01-01T00:00:00Z','skill':'test','type':'pattern','key':'k','insight':'x','confidence':9,'source':'T','branch':'','commit':'','files':[]}
with open('$LEARNINGS', 'w') as f:
    for i in range(1001):
        entry['key'] = f'key-{i}'
        f.write(json.dumps(entry) + '\n')
"

output=$(run_hook)
if echo "$output" | python3 -c "
import json,sys
d=json.load(sys.stdin)
ctx=d.get('hookSpecificOutput',{}).get('additionalContext','')
assert 'Knowledge Warning' in ctx or 'exceeds size limit' in ctx or 'size limit' in ctx.lower(), 'no warning found'
" 2>/dev/null; then
  pass "oversized learnings (>1000 lines) skipped with warning"
else
  fail "oversized learnings should produce a warning in context"
fi

# --- Test 3: output is still valid JSON when file is oversized ---
if echo "$output" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  pass "output is valid JSON even when learnings skipped"
else
  fail "output must be valid JSON"
fi

echo "  ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
