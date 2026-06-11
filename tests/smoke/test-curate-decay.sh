#!/usr/bin/env bash
# test-curate-decay.sh — REQ-05-04 confidence decay, prune rule, prune logging
#
# Covers:
#   1. -1/week decay from recorded_at (10 weeks → conf 9 → 1), floor at 1
#   2. prune only when conf < 4 AND recorded_at older than 30 days
#   3. recent entry decays but is NOT pruned (conf < 4 but < 30 days old)
#   4. pruned entries are archived AND logged to curate-memory.log
#   5. last_decayed_at prevents re-decaying the same weeks on a second run
set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CURATE="${PLUGIN_ROOT}/tools/curate-memory.sh"

PASS=0; FAIL=0
pass() { echo "  PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*"; FAIL=$((FAIL+1)); }

WORKDIR=$(mktemp -d)
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

mkdir -p "${WORKDIR}/.multica"
LEARNINGS="${WORKDIR}/.multica/learnings.jsonl"
ARCHIVE="${WORKDIR}/.multica/learnings-archive.jsonl"
LOG="${WORKDIR}/.multica/curate-memory.log"

iso_ago() {
  python3 -c "
from datetime import datetime, timedelta, timezone
print((datetime.now(timezone.utc) - timedelta(days=int('$1'))).strftime('%Y-%m-%dT%H:%M:%SZ'))
"
}

TEN_WEEKS_AGO=$(iso_ago 70)
TWO_WEEKS_AGO=$(iso_ago 14)
ONE_WEEK_AGO=$(iso_ago 7)

cat > "$LEARNINGS" <<EOF
{"ts":"${TEN_WEEKS_AGO}","recorded_at":"${TEN_WEEKS_AGO}","key":"old-pruned","insight":"decays to 1 and gets pruned","confidence":9}
{"ts":"${TWO_WEEKS_AGO}","recorded_at":"${TWO_WEEKS_AGO}","key":"fresh-keeps","insight":"decays to 7 and stays","confidence":9}
{"ts":"${ONE_WEEK_AGO}","recorded_at":"${ONE_WEEK_AGO}","key":"low-but-recent","insight":"conf below 4 but too recent to prune","confidence":4}
EOF

MULTICA_WORKDIR="$WORKDIR" bash "$CURATE" >/dev/null 2>&1

read_field() {
  python3 -c "
import json, sys
try:
    for line in open(sys.argv[1]):
        e = json.loads(line)
        if e.get('key') == sys.argv[2]:
            print(e.get(sys.argv[3], ''))
            break
except FileNotFoundError:
    pass
" "$1" "$2" "$3" 2>/dev/null
}

# --- Test 1: 10-week-old conf=9 entry decayed to floor and pruned ---
if [[ -z "$(read_field "$LEARNINGS" "old-pruned" "key")" ]]; then
  pass "10-week-old entry pruned from active file (conf 9 → 1 < 4, age > 30d)"
else
  fail "10-week-old entry still active (should be pruned)"
fi
_arch_conf=$(read_field "$ARCHIVE" "old-pruned" "confidence")
if [[ "$_arch_conf" == "1" ]]; then
  pass "pruned entry archived with floored confidence=1 (9 - 10 weeks, floor 1)"
else
  fail "archived confidence expected 1, got '${_arch_conf}'"
fi

# --- Test 2: 2-week-old conf=9 entry decayed to 7 and kept ---
_conf=$(read_field "$LEARNINGS" "fresh-keeps" "confidence")
if [[ "$_conf" == "7" ]]; then
  pass "2-week-old entry decayed 9 → 7 and kept"
else
  fail "expected confidence 7 for fresh-keeps, got '${_conf}'"
fi

# --- Test 3: conf < 4 but younger than 30 days → kept ---
_conf=$(read_field "$LEARNINGS" "low-but-recent" "confidence")
if [[ "$_conf" == "3" ]]; then
  pass "1-week-old conf=4 entry decayed to 3 but kept (< 30 days old)"
else
  fail "expected confidence 3 kept for low-but-recent, got '${_conf}'"
fi

# --- Test 4: prune was logged (no silent removal) ---
if [[ -f "$LOG" ]] && grep -qF "[learning-pruned key=old-pruned confidence=1]" "$LOG"; then
  pass "prune logged to curate-memory.log"
else
  fail "missing [learning-pruned key=old-pruned confidence=1] in log"
fi

# --- Test 5: second run does not re-decay the same weeks ---
MULTICA_WORKDIR="$WORKDIR" bash "$CURATE" >/dev/null 2>&1
_conf=$(read_field "$LEARNINGS" "fresh-keeps" "confidence")
if [[ "$_conf" == "7" ]]; then
  pass "second curate run is idempotent (confidence stays 7 via last_decayed_at)"
else
  fail "second run re-decayed: expected 7, got '${_conf}'"
fi

echo "  ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
