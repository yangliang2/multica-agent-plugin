#!/usr/bin/env bash
# test-static-analysis.sh — static pattern checks on hook source files
# Catches classes of bugs that shellcheck misses:
#   - python3 -c with shell variables interpolated into string literals
#   - trap EXIT registered more than once in the same file
#   - git add without a path argument
set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOKS=("${PLUGIN_ROOT}/hooks/stop.sh" "${PLUGIN_ROOT}/hooks/session-start.sh" "${PLUGIN_ROOT}/hooks/pre-tool.sh")
TESTS=("${PLUGIN_ROOT}/tests/smoke"/test-*.sh)

PASS=0; FAIL=0
pass() { echo "  PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*"; FAIL=$((FAIL+1)); }

# --- Check 1: python3 -c with shell variable directly in string literal ---
# Pattern: python3 -c "...${VAR}..." or python3 -c '...' followed by "$VAR" inside the string
# Safe form uses sys.argv[] or passes via env. Unsafe form: python3 -c "...${VAR}..."
for f in "${HOOKS[@]}"; do
  # Match: python3 -c "...${...}..." (variable inside double-quoted python string)
  if grep -nP 'python3\s+-c\s+"[^"]*\$\{[A-Za-z_][A-Za-z0-9_]*\}' "$f" 2>/dev/null | grep -qv '^\s*#'; then
    hits=$(grep -nP 'python3\s+-c\s+"[^"]*\$\{[A-Za-z_][A-Za-z0-9_]*\}' "$f" | grep -v '^\s*#')
    fail "$(basename "$f"): python3 -c with shell var in string literal (injection risk):"$'\n'"$hits"
  else
    pass "$(basename "$f"): no python3 -c shell-var injection"
  fi
done

# --- Check 2: trap EXIT registered more than once in the same file ---
# Exclude test-static-analysis.sh itself (it scans other files, not itself)
for f in "${TESTS[@]}"; do
  [[ "$(basename "$f")" == "test-static-analysis.sh" ]] && continue
  count=$(grep -c "trap.*EXIT" "$f" 2>/dev/null || true)
  count=${count:-0}
  if [[ "$count" -gt 1 ]]; then
    fail "$(basename "$f"): trap EXIT registered ${count} times (second registration silently replaces first)"
  else
    pass "$(basename "$f"): trap EXIT registered at most once"
  fi
done

# --- Check 3: git add without path argument in hooks ---
for f in "${HOOKS[@]}"; do
  # Match bare "git add" with no path: git add followed by end-of-line, comment, or only flags
  if grep -nE '^\s*git add\s*$|^\s*git add\s+(-[A-Za-z]+\s*)+$' "$f" 2>/dev/null | grep -qv '^\s*#'; then
    hits=$(grep -nE '^\s*git add\s*$|^\s*git add\s+(-[A-Za-z]+\s*)+$' "$f" | grep -v '^\s*#')
    fail "$(basename "$f"): bare 'git add' without path (may commit unintended files):"$'\n'"$hits"
  else
    pass "$(basename "$f"): no bare git add"
  fi
done

# --- Check 4: 2>/dev/null without || log_error on critical multica calls ---
for f in "${HOOKS[@]}"; do
  # multica calls that silence stderr without any error logging
  if grep -nE 'multica\s+issue\s+comment' "$f" 2>/dev/null \
      | grep -v 'log_error\|#' \
      | grep -q '2>/dev/null\s*$'; then
    hits=$(grep -nE 'multica\s+issue\s+comment' "$f" | grep '2>/dev/null\s*$' | grep -v '#')
    fail "$(basename "$f"): multica comment call silences stderr with no log_error fallback:"$'\n'"$hits"
  else
    pass "$(basename "$f"): multica comment calls have error logging"
  fi
done

echo "  ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
