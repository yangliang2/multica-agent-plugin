#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${MULTICA_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

echo "=== multica-agent-plugin doctor ==="
echo ""

# Dependencies
echo "--- Dependencies ---"
check_dep() {
  local name="$1" cmd="$2" purpose="$3"
  if command -v "$cmd" >/dev/null 2>&1; then
    local ver
    ver=$($cmd --version 2>/dev/null | head -1 || echo "unknown")
    echo "  $name: OK ($ver) — $purpose"
  else
    echo "  $name: MISSING — $purpose"
  fi
}
check_dep "multica" "multica" "required — all CLI calls"
check_dep "python3" "python3" "required — staleness detection, thresholds"
check_dep "git" "git" "required — learnings cross-machine sync"
check_dep "jq" "jq" "optional — model routing (uses defaults if missing)"

echo ""
echo "--- Environment ---"
echo "  MULTICA_PLUGIN_ROOT: ${MULTICA_PLUGIN_ROOT:-(not set, using $PLUGIN_ROOT)}"
echo "  MULTICA_ISSUE_ID: ${MULTICA_ISSUE_ID:-(not set — normal outside daemon)}"
echo "  MULTICA_AGENT_SESSION: ${MULTICA_AGENT_SESSION:-0 (default)}"
echo "  DISABLE_MULTICA_PLUGIN: ${DISABLE_MULTICA_PLUGIN:-0 (default)}"

echo ""
echo "--- Hooks Registration ---"
SETTINGS="${CLAUDE_SETTINGS_PATH:-$HOME/.claude/settings.json}"
if [[ -f "$SETTINGS" ]]; then
  for hook in stop.sh pre-tool.sh session-start.sh; do
    if grep -q "$hook" "$SETTINGS" 2>/dev/null; then
      echo "  $hook: registered ✓"
    else
      echo "  $hook: NOT REGISTERED ✗ — run: npx multica-agent-plugin"
    fi
  done
else
  echo "  settings.json: not found at $SETTINGS"
fi

echo ""
echo "--- Conflict Detection ---"
if [[ -f "$SETTINGS" ]]; then
  for other in "persistent-mode.mjs" "gsd-context-monitor" "gsd-workflow-guard"; do
    if grep -q "$other" "$SETTINGS" 2>/dev/null; then
      echo "  $other: DETECTED — coexistence OK if MULTICA_ISSUE_ID set in daemon env"
    fi
  done
  echo "  Tip: set MULTICA_AGENT_SESSION=0 in local shell to disable multica hooks outside daemon"
fi

echo ""
echo "--- Recent Hook Errors ---"
LOG="${MULTICA_WORKDIR:-.}/.multica/logs/hook-errors.log"
if [[ -f "$LOG" ]] && [[ -s "$LOG" ]]; then
  echo "  Recent errors (last 5):"
  tail -5 "$LOG" | sed 's/^/    /'
else
  echo "  None"
fi

echo ""
echo "--- Smoke Test ---"
echo "  Run: bash tests/smoke/run-claude.sh"
echo ""
echo "=== done ==="
