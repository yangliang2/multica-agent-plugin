#!/usr/bin/env bash
# test-session-start-verification-discovery.sh — REQ-07-01 verification cmd discovery
#
# Covers:
#   1. [verification] command="..." in issue description → stored in loop.json
#   2. discovered command appears in the Loop State hint
#   3. immutability: existing verification_cmd is never overwritten
#   4. no [verification] line in description → verification_cmd stays empty
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

ISSUE_ID="VCMD-DISCOVERY-TEST-001"
STATE_DIR="${WORKDIR}/.multica/state/${ISSUE_ID}"
mkdir -p "$STATE_DIR" "${WORKDIR}/.multica/logs"

ISSUE_JSON="${WORKDIR}/issue-fixture.json"
cat > "$ISSUE_JSON" <<'EOF'
{"id":"VCMD-DISCOVERY-TEST-001","title":"Add endpoint","description":"Implement the thing.\n\n[verification] command=\"npm run test:fast\"\n"}
EOF

cat > "${BIN}/multica" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-} \${2:-}" == "issue get" ]]; then
  cat "${ISSUE_JSON}"
  exit 0
fi
exit 0
EOF
chmod +x "${BIN}/multica"

write_loop() {
  local _vc="$1"
  if [[ -n "$_vc" ]]; then
    printf '{"active":true,"iteration":1,"max_iterations":50,"issue_id":"%s","phase":"execute","verification_cmd":"%s"}\n' "$ISSUE_ID" "$_vc" > "${STATE_DIR}/loop.json"
  else
    printf '{"active":true,"iteration":1,"max_iterations":50,"issue_id":"%s","phase":"execute"}\n' "$ISSUE_ID" > "${STATE_DIR}/loop.json"
  fi
}

run_hook() {
  PATH="${BIN}:$PATH" MULTICA_ISSUE_ID="$ISSUE_ID" MULTICA_WORKDIR="$WORKDIR" MULTICA_AGENT_SESSION=1 \
    bash "$HOOK" 2>/dev/null
}

read_vc() {
  python3 -c "
import json, sys
try: print(json.load(open(sys.argv[1])).get('verification_cmd',''))
except Exception: print('')
" "${STATE_DIR}/loop.json" 2>/dev/null
}

# --- Test 1: discovery writes verification_cmd ---
write_loop ""
OUT=$(run_hook)
if [[ "$(read_vc)" == "npm run test:fast" ]]; then
  pass "verification_cmd discovered from issue description"
else
  fail "expected 'npm run test:fast' in loop.json, got '$(read_vc)'"
fi

# --- Test 2: discovered command surfaces in Loop State hint ---
if printf '%s' "$OUT" | grep -qF "Verification cmd: npm run test:fast"; then
  pass "discovered command appears in Loop State hint"
else
  fail "Loop State hint missing the discovered command"
fi

# --- Test 3: immutability — existing value never overwritten ---
write_loop "make check"
run_hook >/dev/null
if [[ "$(read_vc)" == "make check" ]]; then
  pass "existing verification_cmd not overwritten (immutable once set)"
else
  fail "verification_cmd was overwritten: '$(read_vc)'"
fi

# --- Test 4: description without [verification] line → stays empty ---
cat > "$ISSUE_JSON" <<'EOF'
{"id":"VCMD-DISCOVERY-TEST-001","title":"Add endpoint","description":"No verification directive here."}
EOF
write_loop ""
run_hook >/dev/null
if [[ -z "$(read_vc)" ]]; then
  pass "no [verification] directive → verification_cmd stays empty"
else
  fail "unexpected verification_cmd: '$(read_vc)'"
fi

echo "  ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
