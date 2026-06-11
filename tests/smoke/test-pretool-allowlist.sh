#!/usr/bin/env bash
# test-pretool-allowlist.sh — REQ-08-01/02 hybrid allowlist + obfuscation detection
#
# Covers:
#   1. non-critical deny match rescued by allowlist → exit 0 + ALLOW_OVERRIDE logged
#   2. critical deny match NOT rescued by a matching allow pattern → exit 1
#   3. clean command → exit 0 + ALLOW logged
#   4. non-critical deny, no allow → exit 1 + DENY logged
#   5. denied command with $() obfuscation → BYPASS_ATTEMPT logged, exit 1
#   6. missing allow list → no overrides, non-critical deny still blocks
set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="${PLUGIN_ROOT}/hooks/pre-tool.sh"

PASS=0; FAIL=0
pass() { echo "  PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*"; FAIL=$((FAIL+1)); }

WORKDIR=$(mktemp -d)
FAKE_ROOT=$(mktemp -d)
cleanup() { rm -rf "$WORKDIR" "$FAKE_ROOT"; }
trap cleanup EXIT

mkdir -p "${FAKE_ROOT}/tools" "${WORKDIR}/.multica/logs"
SAFE_LOG="${WORKDIR}/.multica/safe-exec.log"

cat > "${FAKE_ROOT}/tools/safe-exec.deny.list" <<'EOF'
git\s+reset\s+--hard
rm\s+-[a-z]*r[a-z]*f\s+/
EOF
cat > "${FAKE_ROOT}/tools/safe-exec.critical.list" <<'EOF'
rm\s+-[a-z]*r[a-z]*f\s+/
EOF
cat > "${FAKE_ROOT}/tools/safe-exec.allow.list" <<'EOF'
^git reset --hard origin/
^rm -rf /tmp/build/
EOF

run_hook() {
  local cmd="$1"
  printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$cmd")" \
    | MULTICA_AGENT_SESSION=1 MULTICA_WORKDIR="$WORKDIR" MULTICA_PLUGIN_ROOT="$FAKE_ROOT" \
      bash "$HOOK" >/dev/null 2>&1
}

# --- Test 1: non-critical deny rescued by allowlist ---
: > "$SAFE_LOG"
if run_hook "git reset --hard origin/main"; then
  if grep -q "ALLOW_OVERRIDE" "$SAFE_LOG"; then
    pass "allowlisted 'git reset --hard origin/' rescued (exit 0, ALLOW_OVERRIDE logged)"
  else
    fail "rescued but ALLOW_OVERRIDE not logged"
  fi
else
  fail "allowlisted non-critical command was blocked"
fi

# --- Test 2: critical deny NOT rescued despite matching allow pattern ---
: > "$SAFE_LOG"
if ! run_hook "rm -rf /tmp/build/old"; then
  pass "critical pattern (rm -rf /) blocked even though allowlist matches"
else
  fail "critical pattern was rescued by allowlist (must never happen)"
fi

# --- Test 3: clean command → ALLOW logged ---
: > "$SAFE_LOG"
if run_hook "git status" && grep -q "ALLOW cmd_sha256=" "$SAFE_LOG"; then
  pass "clean command allowed and ALLOW decision logged"
else
  fail "clean command not allowed or ALLOW not logged"
fi

# --- Test 4: non-critical deny without allow match → DENY logged ---
: > "$SAFE_LOG"
if ! run_hook "git reset --hard HEAD~3" && grep -q "DENY pattern=" "$SAFE_LOG"; then
  pass "non-allowlisted 'git reset --hard HEAD~3' blocked with DENY logged"
else
  fail "non-critical deny without allow match not handled correctly"
fi

# --- Test 5: obfuscated denied command → BYPASS_ATTEMPT ---
: > "$SAFE_LOG"
if ! run_hook 'echo $(rm -rf /) done' && grep -q "BYPASS_ATTEMPT" "$SAFE_LOG"; then
  pass "denied pattern inside \$() tagged BYPASS_ATTEMPT and blocked"
else
  fail "bypass attempt not detected: $(cat "$SAFE_LOG" 2>/dev/null)"
fi

# --- Test 6: missing allow list → no overrides ---
rm -f "${FAKE_ROOT}/tools/safe-exec.allow.list"
if ! run_hook "git reset --hard origin/main"; then
  pass "missing allow list → previously rescued command now blocked"
else
  fail "missing allow list should mean no overrides"
fi

echo "  ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
