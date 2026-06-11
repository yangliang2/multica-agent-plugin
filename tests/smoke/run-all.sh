#!/usr/bin/env bash
# run-all.sh — unified smoke test runner
# Usage: bash tests/smoke/run-all.sh
# Exit:  0 all pass, 1 any fail

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0
SKIP=0

run_test() {
  local name="$1"
  local script="${SCRIPT_DIR}/$1"
  if [[ ! -f "$script" ]]; then
    echo "SKIP: $name (not found)"
    SKIP=$((SKIP + 1))
    return
  fi
  if bash "$script"; then
    echo "PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name"
    FAIL=$((FAIL + 1))
  fi
}

# Existing tests
run_test "run-claude.sh"

# New targeted tests
run_test "test-pretool-guard.sh"
run_test "test-deny-list.sh"
run_test "test-stop-done-failing-story.sh"
run_test "test-session-start-log-error.sh"

run_test "test-stop-evidence.sh"
run_test "test-stop-evidence-structure.sh"
run_test "test-pretool-rate-limit.sh"
run_test "test-session-start-size-limit.sh"
run_test "test-static-analysis.sh"
run_test "test-shell-injection.sh"
run_test "test-autofix-guards.sh"
run_test "test-stop-stdin.sh"
run_test "test-stop-phase-dispatch.sh"
run_test "test-stop-correction-capture.sh"
run_test "test-curate-decay.sh"
run_test "test-session-start-corrections.sh"
run_test "test-session-start-hitl-replay.sh"
run_test "test-run-verification.sh"
run_test "test-session-start-verification-discovery.sh"
run_test "test-session-start-planning-mode.sh"
run_test "test-stop-squad-checkpoint.sh"
run_test "test-session-start-progress-resume.sh"

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"

[[ $FAIL -eq 0 ]]
