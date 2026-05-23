#!/usr/bin/env bash
# Smoke acceptance script for multica-agent-plugin (Claude Code MVP).
# Validates file structure, hook logic, and CLI anchors without requiring
# a live multica daemon or claude session.
#
# Usage: bash tests/smoke/run-claude.sh
# Exit:  0 if all scenarios PASS, 1 if any FAIL.

set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

PASS=0
FAIL=0

pass() { echo "PASS: $*"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $*"; FAIL=$((FAIL + 1)); }

check_file() {
  local f="$1"
  if [[ -f "$f" ]]; then
    pass "file exists: $f"
  else
    fail "file missing: $f"
  fi
}

check_contains() {
  local file="$1"
  local keyword="$2"
  if grep -qF "$keyword" "$file" 2>/dev/null; then
    pass "$file contains: $keyword"
  else
    fail "$file missing keyword: $keyword"
  fi
}

# ---------------------------------------------------------------------------
# Scenario 1 — File structure validation
# ---------------------------------------------------------------------------
echo ""
echo "=== Scenario 1: File Structure ==="

check_file "${PLUGIN_ROOT}/AGENTS.md"
check_file "${PLUGIN_ROOT}/CLAUDE.md"
check_file "${PLUGIN_ROOT}/skills/core/multica-workflow.md"
check_file "${PLUGIN_ROOT}/skills/core/hitl-protocol.md"
check_file "${PLUGIN_ROOT}/skills/core/verification.md"
check_file "${PLUGIN_ROOT}/skills/core/systematic-debug.md"
check_file "${PLUGIN_ROOT}/skills/advanced/persistence-loop.md"
check_file "${PLUGIN_ROOT}/skills/advanced/parallel-exec.md"
check_file "${PLUGIN_ROOT}/hooks/stop.sh"
check_file "${PLUGIN_ROOT}/hooks/pre-tool.sh"
check_file "${PLUGIN_ROOT}/hooks/session-start.sh"
check_file "${PLUGIN_ROOT}/hooks/hooks.json"
check_file "${PLUGIN_ROOT}/docs/cli-reference.md"
check_file "${PLUGIN_ROOT}/docs/abi/cli-outward.md"
check_file "${PLUGIN_ROOT}/capabilities/claude-code.json"

# AGENTS.md line count <= 150
agents_lines=$(wc -l < "${PLUGIN_ROOT}/AGENTS.md")
if [[ "$agents_lines" -le 150 ]]; then
  pass "AGENTS.md line count ${agents_lines} <= 150"
else
  fail "AGENTS.md line count ${agents_lines} exceeds 150"
fi

# verification.md keywords
check_contains "${PLUGIN_ROOT}/skills/core/verification.md" "Iron Law"
check_contains "${PLUGIN_ROOT}/skills/core/verification.md" "Gate Function"
check_contains "${PLUGIN_ROOT}/skills/core/verification.md" "Daemon-Safe Notes"

# systematic-debug.md keywords
check_contains "${PLUGIN_ROOT}/skills/core/systematic-debug.md" "≥3"
check_contains "${PLUGIN_ROOT}/skills/core/systematic-debug.md" "HITL"
check_contains "${PLUGIN_ROOT}/skills/core/systematic-debug.md" "Daemon-Safe Notes"

# persistence-loop.md keywords
check_contains "${PLUGIN_ROOT}/skills/advanced/persistence-loop.md" "<promise>DONE</promise>"
check_contains "${PLUGIN_ROOT}/skills/advanced/persistence-loop.md" "loop.json"
check_contains "${PLUGIN_ROOT}/skills/advanced/persistence-loop.md" "deslop"

# parallel-exec.md keywords
check_contains "${PLUGIN_ROOT}/skills/advanced/parallel-exec.md" "spec compliance"
check_contains "${PLUGIN_ROOT}/skills/advanced/parallel-exec.md" "code quality"

# ---------------------------------------------------------------------------
# Scenario 2 — Stop hook logic validation
# ---------------------------------------------------------------------------
echo ""
echo "=== Scenario 2: Stop Hook Logic ==="

TMPDIR_SMOKE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_SMOKE"' EXIT

ISSUE_ID="test-issue-smoke-$$"
ISSUE_STATE_DIR="${TMPDIR_SMOKE}/.multica/state/${ISSUE_ID}"
mkdir -p "$ISSUE_STATE_DIR"

LOOP_JSON="${ISSUE_STATE_DIR}/loop.json"

# Write an active loop.json with an incomplete story
cat > "$LOOP_JSON" <<'LOOP'
{
  "active": true,
  "iteration": 1,
  "max_iterations": 50,
  "issue_id": "test-issue-smoke",
  "phase": "execution",
  "stories": [
    {"id": "S1", "title": "story one", "acceptance": "criterion", "passes": false}
  ]
}
LOOP

# Force mtime old enough to bypass 60-second throttle
touch -t 200001010000 "$LOOP_JSON"

# Run stop.sh with the temp workdir, redirecting multica calls to /dev/null
MULTICA_WORKDIR="$TMPDIR_SMOKE" \
MULTICA_ISSUE_ID="$ISSUE_ID" \
  bash "${PLUGIN_ROOT}/hooks/stop.sh" > /dev/null 2>&1
exit_code=$?

if [[ "$exit_code" -eq 2 ]]; then
  pass "stop.sh exits 2 (block) when loop active and no DONE signal"
else
  fail "stop.sh exit code was ${exit_code}, expected 2"
fi

# Now set DONE signal and re-run — expect exit 0
# Reset mtime again so throttle does not fire
touch -t 200001010000 "$LOOP_JSON"

MULTICA_WORKDIR="$TMPDIR_SMOKE" \
MULTICA_ISSUE_ID="$ISSUE_ID" \
CLAUDE_TOOL_OUTPUT="$(printf '<promise>DONE</promise>')" \
  bash "${PLUGIN_ROOT}/hooks/stop.sh" > /dev/null 2>&1
exit_code=$?

if [[ "$exit_code" -eq 0 ]]; then
  pass "stop.sh exits 0 when DONE signal present"
else
  fail "stop.sh exit code was ${exit_code}, expected 0 with DONE signal"
fi

# ---------------------------------------------------------------------------
# Scenario 3 — Session-start hook validation
# ---------------------------------------------------------------------------
echo ""
echo "=== Scenario 3: Session-Start Hook ==="

TMPDIR_SESSION=$(mktemp -d)
mkdir -p "${TMPDIR_SESSION}/.multica"

cat > "${TMPDIR_SESSION}/.multica/notepad.md" <<'NOTEPAD'
## Priority Context
This is the priority context for smoke testing.

## Working Memory
[2026-01-01T00:00:00Z] Some working memory entry.

## Manual Notes
Permanent note here.
NOTEPAD

output=$(MULTICA_WORKDIR="$TMPDIR_SESSION" bash "${PLUGIN_ROOT}/hooks/session-start.sh" 2>/dev/null)

# Validate it is parseable JSON (use python3 if available, else basic check)
if command -v python3 >/dev/null 2>&1; then
  if printf '%s' "$output" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    pass "session-start.sh output is valid JSON"
  else
    fail "session-start.sh output is not valid JSON: $output"
  fi
else
  if printf '%s' "$output" | grep -q '^{'; then
    pass "session-start.sh output looks like JSON (python3 not available for deep check)"
  else
    fail "session-start.sh output does not look like JSON: $output"
  fi
fi

if printf '%s' "$output" | grep -q 'additionalContext'; then
  pass "session-start.sh output contains additionalContext"
else
  fail "session-start.sh output missing additionalContext"
fi

rm -rf "$TMPDIR_SESSION"

# ---------------------------------------------------------------------------
# Scenario 4 — CLI anchor validation
# ---------------------------------------------------------------------------
echo ""
echo "=== Scenario 4: CLI Anchor Validation ==="

# AGENTS.md must not contain raw multica command literals (everything via <<cli:*>>)
# We check that known CLI calls appear in anchor form, not as bare `multica issue ...`
if grep -E '^\s*multica ' "${PLUGIN_ROOT}/AGENTS.md" 2>/dev/null | grep -qvE '<<cli:'; then
  fail "AGENTS.md contains raw multica command literals (should use <<cli:*>> anchors)"
else
  pass "AGENTS.md uses <<cli:*>> anchor form for CLI calls"
fi

# docs/cli-reference.lock must exist
check_file "${PLUGIN_ROOT}/docs/cli-reference.lock"

# Lock file sha256 must match docs/cli-reference.md
if [[ -f "${PLUGIN_ROOT}/docs/cli-reference.lock" && -f "${PLUGIN_ROOT}/docs/cli-reference.md" ]]; then
  lock_hash=$(awk '{print $1}' "${PLUGIN_ROOT}/docs/cli-reference.lock")
  actual_hash=$(sha256sum "${PLUGIN_ROOT}/docs/cli-reference.md" | awk '{print $1}')
  if [[ "$lock_hash" == "$actual_hash" ]]; then
    pass "docs/cli-reference.lock sha256 matches docs/cli-reference.md"
  else
    fail "docs/cli-reference.lock sha256 mismatch (lock=${lock_hash} actual=${actual_hash})"
  fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=== Summary ==="
echo "PASS: ${PASS}  FAIL: ${FAIL}"

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
