#!/usr/bin/env bash
# test-run-verification.sh — REQ-07-01/02/03 verification runner
#
# Covers:
#   1. passing command → exit 0, [verification] line with exit_code=0 + output_hash
#   2. failing command with import error → category=import, non-zero exit
#   3. flaky detection: same output_hash, different exit codes → flaky_suspect=true
#   4. command resolution from loop.json.verification_cmd when no arg given
#   5. attempt records appended to verify-attempts.jsonl
set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOL="${PLUGIN_ROOT}/tools/run-verification.sh"

PASS=0; FAIL=0
pass() { echo "  PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*"; FAIL=$((FAIL+1)); }

WORKDIR=$(mktemp -d)
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

ISSUE_ID="VERIFY-RUNNER-TEST-001"
STATE_DIR="${WORKDIR}/.multica/state/${ISSUE_ID}"
mkdir -p "$STATE_DIR"

run_tool() {
  MULTICA_WORKDIR="$WORKDIR" bash "$TOOL" "$ISSUE_ID" "$@" 2>/dev/null
}

# --- Test 1: passing command ---
OUT=$(run_tool "echo all-good")
rc=$?
if [[ $rc -eq 0 ]] && printf '%s' "$OUT" | grep -qE '^\[verification\] exit_code=0 command="echo all-good" output_hash=[0-9a-f]{8}$' ; then
  pass "passing command: exit 0 + well-formed [verification] line"
else
  fail "passing command output wrong (rc=$rc): $(printf '%s' "$OUT" | head -1)"
fi

# --- Test 2: failing command with import error → category=import ---
OUT=$(run_tool "echo 'ModuleNotFoundError: No module named foo'; exit 1")
rc=$?
if [[ $rc -eq 1 ]] && printf '%s' "$OUT" | head -1 | grep -qF "category=import"; then
  pass "import failure categorized as category=import, exit code propagated"
else
  fail "import categorization wrong (rc=$rc): $(printf '%s' "$OUT" | head -1)"
fi

# --- Test 3: flaky detection (same output, different exit codes) ---
FLAG="${WORKDIR}/flagfile"
echo 1 > "$FLAG"
run_tool "echo same-deterministic-output; exit \$(cat ${FLAG})" >/dev/null
echo 0 > "$FLAG"
OUT=$(run_tool "echo same-deterministic-output; exit \$(cat ${FLAG})")
if printf '%s' "$OUT" | head -1 | grep -qF "flaky_suspect=true"; then
  pass "same output_hash with different exit codes flagged flaky_suspect=true"
else
  fail "flaky detection missed: $(printf '%s' "$OUT" | head -1)"
fi

# --- Test 4: command resolved from loop.json.verification_cmd ---
cat > "${STATE_DIR}/loop.json" <<EOF
{"active":true,"issue_id":"${ISSUE_ID}","verification_cmd":"echo from-loop-json"}
EOF
OUT=$(run_tool)
if printf '%s' "$OUT" | head -1 | grep -qF 'command="echo from-loop-json"' \
   && printf '%s' "$OUT" | grep -qF "from-loop-json"; then
  pass "command resolved from loop.json.verification_cmd"
else
  fail "loop.json command resolution wrong: $(printf '%s' "$OUT" | head -1)"
fi

# --- Test 5: attempts appended to verify-attempts.jsonl ---
_attempts=$(python3 -c "
import json, sys
n = 0
for line in open(sys.argv[1]):
    if line.strip():
        json.loads(line)
        n += 1
print(n)
" "${STATE_DIR}/verify-attempts.jsonl" 2>/dev/null)
if [[ "$_attempts" == "5" ]]; then
  pass "5 attempt records appended as valid JSONL"
else
  fail "expected 5 attempt records, got '${_attempts}'"
fi

echo "  ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
