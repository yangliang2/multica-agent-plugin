#!/usr/bin/env bash
# test-session-start-planning-mode.sh — REQ-04-01 planning mode detection
#
# Covers:
#   1. epic keyword in title → loop.json.mode=planning + Planning Mode context
#   2. plain title → mode=execution, no Planning Mode context
#   3. existing mode never overwritten (epic title, mode already execution)
#   4. detection runs exactly once (no issue re-fetch after mode is set)
#   5. output remains valid JSON
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

ISSUE_ID="PLANNING-MODE-TEST-001"
STATE_DIR="${WORKDIR}/.multica/state/${ISSUE_ID}"
mkdir -p "$STATE_DIR" "${WORKDIR}/.multica/logs"

ISSUE_JSON="${WORKDIR}/issue-fixture.json"
GET_COUNT="${WORKDIR}/issue-get-count"

set_title() {
  printf '{"id":"%s","title":"%s","description":"macro task"}\n' "$ISSUE_ID" "$1" > "$ISSUE_JSON"
}

cat > "${BIN}/multica" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-} \${2:-}" == "issue get" ]]; then
  echo x >> "${GET_COUNT}"
  cat "${ISSUE_JSON}"
  exit 0
fi
exit 0
EOF
chmod +x "${BIN}/multica"

write_loop() {
  # $1 = optional explicit mode field (JSON fragment like ',"mode":"execution"')
  printf '{"active":true,"iteration":1,"max_iterations":50,"issue_id":"%s","phase":"spec","verification_cmd":"true"%s}\n' "$ISSUE_ID" "${1:-}" > "${STATE_DIR}/loop.json"
}

run_hook() {
  PATH="${BIN}:$PATH" MULTICA_ISSUE_ID="$ISSUE_ID" MULTICA_WORKDIR="$WORKDIR" MULTICA_AGENT_SESSION=1 \
    bash "$HOOK" 2>/dev/null
}

read_mode() {
  python3 -c "
import json, sys
try: print(json.load(open(sys.argv[1])).get('mode',''))
except Exception: print('')
" "${STATE_DIR}/loop.json" 2>/dev/null
}

# --- Test 1: epic keyword → planning mode + context ---
set_title "Epic: rebuild the auth subsystem"
write_loop ""
OUT=$(run_hook)
if [[ "$(read_mode)" == "planning" ]] && printf '%s' "$OUT" | grep -qF "Planning Mode"; then
  pass "epic title → mode=planning + Planning Mode context injected"
else
  fail "expected planning mode, got mode='$(read_mode)'"
fi
if printf '%s' "$OUT" | grep -qF "breakdown:vN"; then
  pass "planning context references [breakdown:vN] protocol"
else
  fail "planning context missing breakdown protocol reference"
fi

# --- Test 2: plain title → execution mode, no planning context ---
rm -f "$GET_COUNT"
set_title "Fix the login button color"
write_loop ""
OUT=$(run_hook)
if [[ "$(read_mode)" == "execution" ]] && ! printf '%s' "$OUT" | grep -qF "Planning Mode"; then
  pass "plain title → mode=execution, no Planning Mode context"
else
  fail "expected execution mode without planning context, got mode='$(read_mode)'"
fi

# --- Test 3: existing mode never overwritten ---
set_title "Epic: another big initiative"
write_loop ',"mode":"execution"'
run_hook >/dev/null
if [[ "$(read_mode)" == "execution" ]]; then
  pass "existing mode=execution not overwritten despite epic title"
else
  fail "mode was overwritten to '$(read_mode)'"
fi

# --- Test 4: detection runs once (no re-fetch once mode is set) ---
rm -f "$GET_COUNT"
set_title "Epic: detect once"
write_loop ""
run_hook >/dev/null
run_hook >/dev/null
_fetches=$(wc -l < "$GET_COUNT" 2>/dev/null | tr -d ' ')
if [[ "${_fetches:-0}" == "1" ]]; then
  pass "issue fetched exactly once across two session starts"
else
  fail "expected 1 issue-get fetch, got '${_fetches:-0}'"
fi

# --- Test 5: output is valid JSON ---
if printf '%s' "$OUT" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  pass "hook output is valid JSON"
else
  fail "hook output is not valid JSON"
fi

echo "  ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
