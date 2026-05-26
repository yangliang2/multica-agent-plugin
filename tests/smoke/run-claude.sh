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
# Update loop.json to have all stories passing (cross-check requirement)
cat > "$LOOP_JSON" <<LOOP
{
  "active": true,
  "iteration": 1,
  "max_iterations": 50,
  "issue_id": "$ISSUE_ID",
  "phase": "execution",
  "stories": [
    {"id": "S1", "title": "story one", "acceptance": "criterion", "passes": true}
  ]
}
LOOP
touch -t 200001010000 "$LOOP_JSON"

# Evidence file required by stop.sh evidence gate
mkdir -p "${ISSUE_STATE_DIR}/evidence"
cat > "${ISSUE_STATE_DIR}/evidence/S1.txt" <<'EV'
command: pytest tests/
exit_code: 0
output_hash: abc12345
summary: 1 passed in 0.12s
EV

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

output=$(MULTICA_AGENT_SESSION=1 MULTICA_WORKDIR="$TMPDIR_SESSION" bash "${PLUGIN_ROOT}/hooks/session-start.sh" 2>/dev/null)

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
  if command -v sha256sum >/dev/null 2>&1; then
    actual_hash=$(sha256sum "${PLUGIN_ROOT}/docs/cli-reference.md" | awk '{print $1}')
  elif command -v shasum >/dev/null 2>&1; then
    actual_hash=$(shasum -a 256 "${PLUGIN_ROOT}/docs/cli-reference.md" | awk '{print $1}')
  else
    actual_hash=""
  fi
  if [[ "$lock_hash" == "$actual_hash" ]]; then
    pass "docs/cli-reference.lock sha256 matches docs/cli-reference.md"
  else
    fail "docs/cli-reference.lock sha256 mismatch (lock=${lock_hash} actual=${actual_hash})"
  fi
fi

# ---------------------------------------------------------------------------
# Scenario 5 — Leader routing detection
# ---------------------------------------------------------------------------
echo ""
echo "=== Scenario 5: Squad Leader Detection ==="

tmpdir_s5=$(mktemp -d)
trap 'rm -rf "$tmpdir_s5"' EXIT

cat > "$tmpdir_s5/CLAUDE.md" <<'EOF'
## Agent Identity

You are a squad leader.

## Squad Operating Protocol

Your job is to coordinate.

## Squad Roster

Leader (you):
- TestLeader — agent — `[@TestLeader](mention://agent/aaaaaaaa-0000-0000-0000-000000000001)`

Members:
- Worker1 — agent — `[@Worker1](mention://agent/bbbbbbbb-0000-0000-0000-000000000002)`
EOF

output_s5=$(MULTICA_AGENT_SESSION=1 MULTICA_WORKDIR="$tmpdir_s5" bash "${PLUGIN_ROOT}/hooks/session-start.sh" 2>/dev/null)

if printf '%s' "$output_s5" | grep -q "Squad Role: LEADER"; then
  pass "session-start detects squad leader role"
else
  fail "session-start did not detect squad leader role"
fi

if printf '%s' "$output_s5" | grep -q "mention://agent/"; then
  pass "roster mention links present in additionalContext"
else
  fail "roster mention links not found in additionalContext"
fi

if grep -qF "## Squad Operating Protocol" "${PLUGIN_ROOT}/AGENTS.md" 2>/dev/null; then
  fail "literal marker found in AGENTS.md (drift guard violation)"
else
  pass "no literal marker in AGENTS.md"
fi

if grep -qF "## Squad Operating Protocol" "${PLUGIN_ROOT}/skills/core/squad-leader-workflow.md" 2>/dev/null; then
  fail "literal marker found in squad-leader-workflow.md (drift guard violation)"
else
  pass "no literal marker in squad-leader-workflow.md"
fi

# ---------------------------------------------------------------------------
# Scenario 6 — Member HITL 3-strike escalation
# ---------------------------------------------------------------------------
echo ""
echo "=== Scenario 6: Member HITL 3-strike Rule ==="

if grep -q "3-strike\|3 strike\|third.*bounce\|question_id" "${PLUGIN_ROOT}/skills/core/squad-member-workflow.md" 2>/dev/null; then
  pass "squad-member-workflow.md contains 3-strike rule"
else
  fail "squad-member-workflow.md missing 3-strike rule"
fi

if grep -q "\[HITL:leader\]" "${PLUGIN_ROOT}/skills/core/squad-member-workflow.md" 2>/dev/null; then
  pass "squad-member-workflow.md contains [HITL:leader] tier"
else
  fail "[HITL:leader] tier missing in squad-member-workflow.md"
fi

if grep -q "\[HITL:human\]" "${PLUGIN_ROOT}/skills/core/squad-member-workflow.md" 2>/dev/null; then
  pass "squad-member-workflow.md contains [HITL:human] escalation"
else
  fail "[HITL:human] escalation missing in squad-member-workflow.md"
fi

# ---------------------------------------------------------------------------
# Scenario 7 — Leader activity-skip audit enforcement
# ---------------------------------------------------------------------------
echo ""
echo "=== Scenario 7: Squad Activity Audit ==="

tmpdir_s7=$(mktemp -d)
trap 'rm -rf "$tmpdir_s7"' EXIT

cat > "$tmpdir_s7/CLAUDE.md" <<'EOF'
## Squad Operating Protocol
test
EOF

mkdir -p "$tmpdir_s7/.multica/state/test-issue-123"

# Create an active loop.json with all stories passing and old mtime
cat > "$tmpdir_s7/.multica/state/test-issue-123/loop.json" <<LOOP
{
  "active": true,
  "iteration": 1,
  "max_iterations": 50,
  "issue_id": "test-issue-123",
  "phase": "execution",
  "stories": [
    {"id": "S1", "title": "story one", "acceptance": "criterion", "passes": true}
  ]
}
LOOP
touch -t 200001010000 "$tmpdir_s7/.multica/state/test-issue-123/loop.json"

# Evidence file required by stop.sh evidence gate
mkdir -p "$tmpdir_s7/.multica/state/test-issue-123/evidence"
cat > "$tmpdir_s7/.multica/state/test-issue-123/evidence/S1.txt" <<'EV'
command: pytest tests/
exit_code: 0
output_hash: abc12345
summary: 1 passed in 0.12s
EV

# Trigger DONE branch so stop.sh exits 0 and squad_leader_audit runs;
# no squad-activity.marker present — audit warning should be written.
MULTICA_WORKDIR="$tmpdir_s7" \
MULTICA_ISSUE_ID="test-issue-123" \
CLAUDE_TOOL_OUTPUT="$(printf '<promise>DONE</promise>')" \
  bash "${PLUGIN_ROOT}/hooks/stop.sh" > /dev/null 2>&1
stop_exit=$?

if [[ $stop_exit -eq 0 ]]; then
  pass "stop.sh exits 0 even when squad activity was skipped"
else
  fail "stop.sh exited $stop_exit (should always be 0)"
fi

if [[ -f "$tmpdir_s7/.multica/state/squad-audit-warning" ]]; then
  pass "squad-audit-warning written when activity marker absent"
else
  fail "squad-audit-warning not written"
fi

# Verify no warning written when marker is present
touch "$tmpdir_s7/.multica/state/test-issue-123/squad-activity.marker"
rm -f "$tmpdir_s7/.multica/state/squad-audit-warning"

# Restore active loop.json with all stories passing for second run
cat > "$tmpdir_s7/.multica/state/test-issue-123/loop.json" <<LOOP
{
  "active": true,
  "iteration": 1,
  "max_iterations": 50,
  "issue_id": "test-issue-123",
  "phase": "execution",
  "stories": [
    {"id": "S1", "title": "story one", "acceptance": "criterion", "passes": true}
  ]
}
LOOP
touch -t 200001010000 "$tmpdir_s7/.multica/state/test-issue-123/loop.json"

# Evidence file required by stop.sh evidence gate
mkdir -p "$tmpdir_s7/.multica/state/test-issue-123/evidence"
cat > "$tmpdir_s7/.multica/state/test-issue-123/evidence/S1.txt" <<'EV'
command: pytest tests/
exit_code: 0
output_hash: abc12345
summary: 1 passed in 0.12s
EV

MULTICA_WORKDIR="$tmpdir_s7" \
MULTICA_ISSUE_ID="test-issue-123" \
CLAUDE_TOOL_OUTPUT="$(printf '<promise>DONE</promise>')" \
  bash "${PLUGIN_ROOT}/hooks/stop.sh" > /dev/null 2>&1

if [[ ! -f "$tmpdir_s7/.multica/state/squad-audit-warning" ]]; then
  pass "no warning written when activity marker present"
else
  fail "spurious warning written when activity marker was present"
fi

# ---------------------------------------------------------------------------
# Scenario 8 — curate-memory.sh dedup test
# ---------------------------------------------------------------------------
echo ""
echo "=== Scenario 8: curate-memory.sh deduplication ==="

tmpdir_s8=$(mktemp -d)
trap 'rm -rf "$tmpdir_s8"' EXIT

mkdir -p "$tmpdir_s8/.multica"
# Write two entries with same key (old one first, new one second)
cat > "$tmpdir_s8/.multica/learnings.jsonl" << 'EOF'
{"ts":"2020-01-01T00:00:00Z","key":"test-config","insight":"old insight","confidence":8,"files":[]}
{"ts":"2026-01-01T00:00:00Z","key":"test-config","insight":"new insight","confidence":9,"files":[]}
{"ts":"2026-01-01T00:00:00Z","key":"other-key","insight":"other insight","confidence":7,"files":[]}
EOF

MULTICA_WORKDIR="$tmpdir_s8" bash "${PLUGIN_ROOT}/tools/curate-memory.sh" >/dev/null 2>&1

# Verify: only 2 unique keys remain (latest per key)
count=$(wc -l < "$tmpdir_s8/.multica/learnings.jsonl")
if [[ "$count" -eq 2 ]]; then
  pass "curate-memory dedup: 3 entries → 2 unique keys"
else
  fail "curate-memory dedup: expected 2 entries, got $count"
fi

# Verify: surviving test-config entry has new insight
if grep -q "new insight" "$tmpdir_s8/.multica/learnings.jsonl"; then
  pass "curate-memory dedup: latest entry preserved"
else
  fail "curate-memory dedup: latest entry not preserved"
fi

# ---------------------------------------------------------------------------
# Scenario 9 — staleness detection
# ---------------------------------------------------------------------------
echo ""
echo "=== Scenario 9: Session-Start Staleness Detection ==="

tmpdir_s9=$(mktemp -d)
trap 'rm -rf "$tmpdir_s9"' EXIT

mkdir -p "$tmpdir_s9/.multica"
# Create a learning that references a non-existent file
cat > "$tmpdir_s9/.multica/learnings.jsonl" << EOF
{"ts":"2026-01-01T00:00:00Z","key":"stale-learning","insight":"uses deleted file","confidence":8,"files":["nonexistent.py"]}
{"ts":"2026-01-01T00:00:00Z","key":"fresh-learning","insight":"no files referenced","confidence":7,"files":[]}
EOF

output=$(MULTICA_AGENT_SESSION=1 MULTICA_WORKDIR="$tmpdir_s9" bash "${PLUGIN_ROOT}/hooks/session-start.sh" 2>/dev/null)

if echo "$output" | grep -q "possibly stale"; then
  pass "session-start marks missing-file learning as stale"
else
  fail "session-start did not mark missing-file learning as stale"
fi

# Extract the additionalContext text and check fresh-learning line individually
fresh_line=$(echo "$output" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['hookSpecificOutput']['additionalContext'])" 2>/dev/null \
  | grep "fresh-learning")
if echo "$fresh_line" | grep -qv "possibly stale"; then
  pass "session-start does not mark no-files learning as stale"
else
  fail "session-start incorrectly marked no-files learning as stale"
fi

# ---------------------------------------------------------------------------
# Scenario 10 — notepad Working Memory prune
# ---------------------------------------------------------------------------
echo ""
echo "=== Scenario 10: Notepad Working Memory Prune ==="

tmpdir_s10=$(mktemp -d)
trap 'rm -rf "$tmpdir_s10"' EXIT

# Create notepad with old Working Memory entry
old_ts=$(date -d '8 days ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
         date -v-8d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "2020-01-01T00:00:00Z")
new_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

mkdir -p "$tmpdir_s10/.multica"
cat > "$tmpdir_s10/.multica/notepad.md" << EOF
## Priority Context
Important context here.

## Working Memory
[${old_ts}] This is old, should be pruned.
[${new_ts}] This is new, should be kept.

## Manual Notes
Permanent note.
EOF

# Create loop.json to trigger DONE path; backdate mtime so throttle check passes
mkdir -p "$tmpdir_s10/.multica/state/test-prune-issue"
cat > "$tmpdir_s10/.multica/state/test-prune-issue/loop.json" << 'EOF'
{"active": true, "iteration": 1, "phase": "execution", "max_iterations": 50, "issue_id": "test-prune-issue", "stories": [{"id": "S1", "passes": true}]}
EOF
touch -t 200001010000 "$tmpdir_s10/.multica/state/test-prune-issue/loop.json"

# Evidence file required by stop.sh evidence gate
mkdir -p "$tmpdir_s10/.multica/state/test-prune-issue/evidence"
cat > "$tmpdir_s10/.multica/state/test-prune-issue/evidence/S1.txt" << 'EV'
command: echo test
exit_code: 0
output_hash: abc12345
summary: ok
EV

# Run stop.sh with DONE signal
MULTICA_WORKDIR="$tmpdir_s10" MULTICA_ISSUE_ID="test-prune-issue" \
  CLAUDE_TOOL_OUTPUT="<promise>DONE</promise>" bash "${PLUGIN_ROOT}/hooks/stop.sh" 2>/dev/null || true

if grep -q "This is new" "$tmpdir_s10/.multica/notepad.md" && \
   ! grep -q "This is old" "$tmpdir_s10/.multica/notepad.md"; then
  pass "notepad prune removed old Working Memory entry, kept new one"
else
  fail "notepad prune did not work correctly"
fi

if grep -q "Permanent note" "$tmpdir_s10/.multica/notepad.md"; then
  pass "notepad prune preserved Manual Notes"
else
  fail "notepad prune removed Manual Notes"
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
