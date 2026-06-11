#!/usr/bin/env bash
# test-stop-correction-capture.sh — REQ-05-01 correction signal → learning capture
#
# Covers:
#   1. [wrong: ...] from a human author within 7 days → learning entry (confidence=9)
#   2. agent-authored [wrong: ...] is NOT captured
#   3. signal older than the 7-day window is NOT captured
#   4. re-run dedups: same key stays a single entry (recurrence reinforcement)
#   5. workdir-is-checkout: repo-scoped entry survives the routing pass
#      (regression guard for the append-to-self / L3-rewrite wipe)
set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="${PLUGIN_ROOT}/hooks/stop.sh"

PASS=0; FAIL=0
pass() { echo "  PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*"; FAIL=$((FAIL+1)); }

WORKDIR=$(mktemp -d)
BIN=$(mktemp -d)
WORKDIR2=""
cleanup() {
  rm -rf "$WORKDIR" "$BIN"
  [[ -n "$WORKDIR2" ]] && rm -rf "$WORKDIR2"
  return 0
}
trap cleanup EXIT

ISSUE_ID="CAPTURE-TEST-001"
STATE_DIR="${WORKDIR}/.multica/state/${ISSUE_ID}"
mkdir -p "$STATE_DIR" "${WORKDIR}/.multica/logs"

NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
OLD_ISO=$(python3 -c "
from datetime import datetime, timedelta, timezone
print((datetime.now(timezone.utc) - timedelta(days=30)).strftime('%Y-%m-%dT%H:%M:%SZ'))
")

write_loop() {
  cat > "${STATE_DIR}/loop.json" <<EOF
{"active":true,"iteration":1,"max_iterations":50,"issue_id":"${ISSUE_ID}","phase":"demo","start_time":"${NOW_ISO}"}
EOF
}

COMMENTS_JSON="${WORKDIR}/comments-fixture.json"
cat > "$COMMENTS_JSON" <<EOF
[
  {"id":"c1","content":"[wrong: tests must run with --runInBand]","author":{"type":"member","name":"peter"},"created_at":"${NOW_ISO}"},
  {"id":"c2","content":"[wrong: agent-echo-should-be-ignored]","author":{"type":"agent","name":"bot"},"created_at":"${NOW_ISO}"},
  {"id":"c3","content":"[revise: too-old-to-capture]","author":{"type":"member","name":"peter"},"created_at":"${OLD_ISO}"}
]
EOF

# multica stub: `issue comment list` returns the fixture; everything else no-ops
cat > "${BIN}/multica" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-} \${2:-} \${3:-}" == "issue comment list" ]]; then
  cat "${COMMENTS_JSON}"
  exit 0
fi
exit 0
EOF
chmod +x "${BIN}/multica"

DONE_STDIN='{"stop_hook_active":true,"agent_output":"<promise>DONE</promise>"}'

run_hook() {
  PATH="${BIN}:$PATH" MULTICA_ISSUE_ID="$ISSUE_ID" MULTICA_WORKDIR="$WORKDIR" MULTICA_AGENT_SESSION=1 \
    bash "$HOOK" <<< "$DONE_STDIN" >/dev/null 2>/dev/null || true
}

EXPECTED_KEY=$(python3 -c "
import hashlib
print(hashlib.sha256('tests must run with --runInBand'[:200].encode()).hexdigest()[:16])
")
LEARNINGS="${WORKDIR}/.multica/learnings.jsonl"

count_key() {
  python3 -c "
import json, sys
n = 0
try:
    for line in open(sys.argv[1]):
        if line.strip() and json.loads(line).get('key') == sys.argv[2]:
            n += 1
except FileNotFoundError:
    pass
print(n)
" "$1" "$2" 2>/dev/null
}

# --- Test 1: human [wrong:] within window is captured with confidence=9 ---
write_loop
run_hook
if [[ "$(count_key "$LEARNINGS" "$EXPECTED_KEY")" == "1" ]]; then
  pass "human [wrong:] signal captured with expected sha256-derived key"
else
  fail "expected key ${EXPECTED_KEY} not found in learnings.jsonl"
fi

_conf=$(python3 -c "
import json, sys
for line in open(sys.argv[1]):
    e = json.loads(line)
    if e.get('key') == sys.argv[2]:
        print(e.get('confidence'), e.get('skill'), e.get('type'))
" "$LEARNINGS" "$EXPECTED_KEY" 2>/dev/null)
if [[ "$_conf" == "9 correction-capture fix" ]]; then
  pass "captured entry has confidence=9, skill=correction-capture, type=fix"
else
  fail "captured entry fields wrong: '${_conf}'"
fi

# --- Test 2: agent-authored signal is NOT captured ---
if grep -qF "agent-echo-should-be-ignored" "$LEARNINGS" 2>/dev/null; then
  fail "agent-authored [wrong:] was captured (should be ignored)"
else
  pass "agent-authored [wrong:] ignored"
fi

# --- Test 3: signal outside the 7-day window is NOT captured ---
if grep -qF "too-old-to-capture" "$LEARNINGS" 2>/dev/null; then
  fail "30-day-old signal was captured (outside 7-day window)"
else
  pass "signal older than 7 days ignored"
fi

# --- Test 4: re-run dedups to a single entry (recurrence reinforcement) ---
write_loop
run_hook
_count=$(count_key "$LEARNINGS" "$EXPECTED_KEY")
if [[ "$_count" == "1" ]]; then
  pass "second run reinforced existing entry instead of duplicating (count=1)"
else
  fail "expected 1 entry for key after re-run, got '${_count}'"
fi

# --- Test 5: workdir-is-checkout — repo-scoped entry survives routing ---
WORKDIR2=$(mktemp -d)
STATE_DIR2="${WORKDIR2}/.multica/state/${ISSUE_ID}"
mkdir -p "$STATE_DIR2" "${WORKDIR2}/.multica/logs"
git -C "$WORKDIR2" init -q 2>/dev/null
git -C "$WORKDIR2" remote add origin "https://example.com/proj.git" 2>/dev/null
cat > "${STATE_DIR2}/loop.json" <<EOF
{"active":true,"iteration":1,"max_iterations":50,"issue_id":"${ISSUE_ID}","phase":"demo","start_time":"${NOW_ISO}"}
EOF
PATH="${BIN}:$PATH" MULTICA_ISSUE_ID="$ISSUE_ID" MULTICA_WORKDIR="$WORKDIR2" MULTICA_AGENT_SESSION=1 \
  bash "$HOOK" <<< "$DONE_STDIN" >/dev/null 2>/dev/null
LEARNINGS2="${WORKDIR2}/.multica/learnings.jsonl"
_entry2=$(python3 -c "
import json, sys
for line in open(sys.argv[1]):
    e = json.loads(line)
    if e.get('key') == sys.argv[2]:
        print(e.get('scope'), e.get('repo'))
" "$LEARNINGS2" "$EXPECTED_KEY" 2>/dev/null)
if [[ "$_entry2" == "repo https://example.com/proj.git" ]]; then
  pass "repo-scoped entry survives routing when workdir is its own checkout"
else
  fail "repo-scoped entry lost or mangled after routing: '${_entry2}'"
fi

echo "  ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
