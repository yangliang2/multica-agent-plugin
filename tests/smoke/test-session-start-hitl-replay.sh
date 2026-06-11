#!/usr/bin/env bash
# test-session-start-hitl-replay.sh — REQ-06-02 HITL replay detection on resume
#
# Covers:
#   1. thread reply (parent_id → agent's [HITL] comment) matched and injected
#   2. direct question_id mention in a human comment matched
#   3. unanswered question stays in open_hitls
#   4. answered questions moved to resolved_hitls with answer text
#   5. second run does not duplicate resolved entries
#   6. output remains valid JSON
set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="${PLUGIN_ROOT}/hooks/session-start.sh"

PASS=0; FAIL=0
pass() { echo "  PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*"; FAIL=$((FAIL+1)); }

WORKDIR=$(mktemp -d)
BIN=$(mktemp -d)
cleanup() { rm -rf "$WORKDIR" "$BIN"; }
trap cleanup EXIT

ISSUE_ID="HITL-REPLAY-TEST-001"
STATE_DIR="${WORKDIR}/.multica/state/${ISSUE_ID}"
mkdir -p "$STATE_DIR" "${WORKDIR}/.multica/logs"

NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)

cat > "${STATE_DIR}/loop.json" <<EOF
{"active":true,"iteration":1,"max_iterations":50,"issue_id":"${ISSUE_ID}","phase":"execute",
 "open_hitls":[
   {"question_id":"q-aaa-111","asked_at":"${NOW_ISO}","tier":"human"},
   {"question_id":"q-bbb-222","asked_at":"${NOW_ISO}","tier":"leader"},
   {"question_id":"q-ccc-333","asked_at":"${NOW_ISO}","tier":"human"}
 ]}
EOF

COMMENTS_JSON="${WORKDIR}/comments-fixture.json"
cat > "$COMMENTS_JSON" <<EOF
[
  {"id":"h1","parent_id":null,"content":"[HITL] phase=execute question_id=q-aaa-111\n\n**Question:** Redis or Postgres?","author":{"type":"agent","name":"bot"},"created_at":"${NOW_ISO}"},
  {"id":"r1","parent_id":"h1","content":"Use Postgres please","author":{"type":"member","name":"peter"},"created_at":"${NOW_ISO}"},
  {"id":"r2","parent_id":null,"content":"re question_id=q-bbb-222: go with option B","author":{"type":"member","name":"peter"},"created_at":"${NOW_ISO}"}
]
EOF

cat > "${BIN}/multica" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-} \${2:-} \${3:-}" == "issue comment list" ]]; then
  cat "${COMMENTS_JSON}"
  exit 0
fi
exit 0
EOF
chmod +x "${BIN}/multica"

run_hook() {
  PATH="${BIN}:$PATH" MULTICA_ISSUE_ID="$ISSUE_ID" MULTICA_WORKDIR="$WORKDIR" MULTICA_AGENT_SESSION=1 \
    bash "$HOOK" 2>/dev/null
}

OUT=$(run_hook)

loop_field() {
  python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
v = d.get(sys.argv[2], [])
print(json.dumps(v))
" "${STATE_DIR}/loop.json" "$1" 2>/dev/null
}

# --- Test 1: thread reply matched and injected ---
if printf '%s' "$OUT" | grep -qF "HITL Replies Detected" \
   && printf '%s' "$OUT" | grep -qF "q-aaa-111: Use Postgres please"; then
  pass "thread reply matched via parent_id and injected into context"
else
  fail "thread-reply answer for q-aaa-111 missing from context"
fi

# --- Test 2: direct question_id mention matched ---
if printf '%s' "$OUT" | grep -qF "q-bbb-222" \
   && printf '%s' "$OUT" | grep -qF "option B"; then
  pass "direct question_id mention matched and injected"
else
  fail "direct-mention answer for q-bbb-222 missing from context"
fi

# --- Test 3: unanswered question stays open ---
_open=$(loop_field "open_hitls")
if printf '%s' "$_open" | grep -qF "q-ccc-333" \
   && ! printf '%s' "$_open" | grep -qF "q-aaa-111"; then
  pass "unanswered q-ccc-333 stays open; answered q-aaa-111 removed from open"
else
  fail "open_hitls wrong after replay: ${_open}"
fi

# --- Test 4: answered questions moved to resolved with answer ---
_resolved=$(loop_field "resolved_hitls")
if printf '%s' "$_resolved" | grep -qF "Use Postgres please" \
   && printf '%s' "$_resolved" | grep -qF "q-bbb-222"; then
  pass "resolved_hitls carries both answers"
else
  fail "resolved_hitls missing answers: ${_resolved}"
fi

# --- Test 5: second run does not duplicate resolved entries ---
run_hook >/dev/null
_resolved_count=$(python3 -c "
import json, sys
print(len(json.load(open(sys.argv[1])).get('resolved_hitls', [])))
" "${STATE_DIR}/loop.json" 2>/dev/null)
if [[ "$_resolved_count" == "2" ]]; then
  pass "second run idempotent (resolved_hitls count stays 2)"
else
  fail "expected 2 resolved entries after re-run, got '${_resolved_count}'"
fi

# --- Test 6: output is valid JSON ---
if printf '%s' "$OUT" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  pass "hook output is valid JSON"
else
  fail "hook output is not valid JSON"
fi

echo "  ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
