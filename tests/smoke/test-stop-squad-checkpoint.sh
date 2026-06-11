#!/usr/bin/env bash
# test-stop-squad-checkpoint.sh — REQ-04-04 leader children checkpoint
#
# Covers:
#   1. stuck child (last comment > threshold behind newest server ts) → [checkpoint] squad-stuck
#   2. rate limit: second run in same hour does not re-post
#   3. all children done → loop.json.phase=result + [phase] execute→result comment
#   4. no child_issues in loop.json → no checkpoint activity
set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="${PLUGIN_ROOT}/hooks/stop.sh"

PASS=0; FAIL=0
pass() { echo "  PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*"; FAIL=$((FAIL+1)); }

WORKDIR=$(mktemp -d)
BIN=$(mktemp -d)
cleanup() { rm -rf "$WORKDIR" "$BIN"; }
trap cleanup EXIT

ISSUE_ID="SQUAD-CKPT-TEST-001"
STATE_DIR="${WORKDIR}/.multica/state/${ISSUE_ID}"
mkdir -p "$STATE_DIR" "${WORKDIR}/.multica/logs"

# Leader detection: CLAUDE.md with the squad protocol marker
printf '## Squad Operating Protocol\n\n## Squad Roster\n- [@Alice](mention://agent/u1)\n' > "${WORKDIR}/CLAUDE.md"

NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
OLD_ISO=$(python3 -c "
from datetime import datetime, timedelta, timezone
print((datetime.now(timezone.utc) - timedelta(hours=5)).strftime('%Y-%m-%dT%H:%M:%SZ'))
")

CALL_LOG="${WORKDIR}/multica-calls.log"
FIXTURES="${WORKDIR}/fixtures"
mkdir -p "$FIXTURES"

# multica stub: serves issue get / comment list from fixture files keyed by id,
# logs comment add calls, no-ops everything else
cat > "${BIN}/multica" <<EOF
#!/usr/bin/env bash
log="${CALL_LOG}"
fixtures="${FIXTURES}"
if [[ "\${1:-} \${2:-}" == "issue get" ]]; then
  f="\${fixtures}/\${3}.issue.json"
  [[ -f "\$f" ]] && cat "\$f" && exit 0
  echo '{}'; exit 0
fi
if [[ "\${1:-} \${2:-} \${3:-}" == "issue comment list" ]]; then
  f="\${fixtures}/\${4}.comments.json"
  [[ -f "\$f" ]] && cat "\$f" && exit 0
  echo '[]'; exit 0
fi
if [[ "\${1:-} \${2:-} \${3:-}" == "issue comment add" ]]; then
  echo "COMMENT_ADD \$*" >> "\$log"
  exit 0
fi
exit 0
EOF
chmod +x "${BIN}/multica"

write_loop() {
  # $1 = child_issues JSON array
  cat > "${STATE_DIR}/loop.json" <<EOF
{"active":true,"iteration":1,"max_iterations":50,"issue_id":"${ISSUE_ID}","phase":"demo","start_time":"${NOW_ISO}","child_issues":${1},"squad_stuck_threshold_minutes":120}
EOF
}

set_child() {
  # $1=id $2=status $3=last_comment_iso
  printf '{"id":"%s","status":"%s"}\n' "$1" "$2" > "${FIXTURES}/$1.issue.json"
  printf '[{"id":"c-%s","content":"progress","author":{"type":"agent","name":"m"},"created_at":"%s"}]\n' "$1" "$3" > "${FIXTURES}/$1.comments.json"
}

DONE_STDIN='{"stop_hook_active":true,"agent_output":"<promise>DONE</promise>"}'

run_hook() {
  # marker present → audit skips the activity-failed call
  touch "${STATE_DIR}/squad-activity.marker"
  PATH="${BIN}:$PATH" MULTICA_ISSUE_ID="$ISSUE_ID" MULTICA_WORKDIR="$WORKDIR" MULTICA_AGENT_SESSION=1 \
    bash "$HOOK" <<< "$DONE_STDIN" >/dev/null 2>/dev/null || true
}

read_phase() {
  python3 -c "
import json, sys
try: print(json.load(open(sys.argv[1])).get('phase',''))
except Exception: print('')
" "${STATE_DIR}/loop.json" 2>/dev/null
}

# --- Test 1: stuck child detected via server-time comparison ---
write_loop '["CHILD-1","CHILD-2"]'
set_child "CHILD-1" "done" "$NOW_ISO"
set_child "CHILD-2" "in_progress" "$OLD_ISO"
run_hook
if grep -q "COMMENT_ADD.*squad-stuck.*CHILD-2" "$CALL_LOG" 2>/dev/null; then
  pass "stuck child (5h silent vs 2h threshold) reported in [checkpoint] squad-stuck"
else
  fail "no squad-stuck checkpoint posted: $(cat "$CALL_LOG" 2>/dev/null)"
fi

# --- Test 2: rate limit — same hour, no duplicate post ---
: > "$CALL_LOG"
write_loop '["CHILD-1","CHILD-2"]'
run_hook
if ! grep -q "squad-stuck" "$CALL_LOG" 2>/dev/null; then
  pass "second run within the hour suppressed by rate-limit marker"
else
  fail "duplicate squad-stuck checkpoint posted within the hour"
fi

# --- Test 3: all children done → phase=result + [phase] comment ---
: > "$CALL_LOG"
write_loop '["CHILD-1","CHILD-2"]'
set_child "CHILD-1" "done" "$NOW_ISO"
set_child "CHILD-2" "done" "$NOW_ISO"
run_hook
if [[ "$(read_phase)" == "result" ]]; then
  pass "all children done → loop.json.phase advanced to result"
else
  fail "expected phase=result, got '$(read_phase)'"
fi
if grep -q "COMMENT_ADD.*execute→result" "$CALL_LOG" 2>/dev/null; then
  pass "[phase] execute→result comment posted"
else
  fail "phase transition comment missing: $(cat "$CALL_LOG" 2>/dev/null)"
fi

# --- Test 4: no child_issues → no checkpoint activity ---
: > "$CALL_LOG"
cat > "${STATE_DIR}/loop.json" <<EOF
{"active":true,"iteration":1,"max_iterations":50,"issue_id":"${ISSUE_ID}","phase":"demo","start_time":"${NOW_ISO}"}
EOF
run_hook
if ! grep -qE "squad-stuck|execute→result" "$CALL_LOG" 2>/dev/null; then
  pass "no child_issues → no checkpoint comments"
else
  fail "unexpected checkpoint activity without child_issues"
fi

echo "  ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
