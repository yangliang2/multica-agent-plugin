#!/usr/bin/env bash
set -euo pipefail

# stop.sh — Multica persistence loop enforcer (Claude Code Stop hook)
#
# Exit codes:
#   0  — loop complete or no active loop; allow Stop
#   2  — loop active and not done; block Stop (Claude Code re-prompts)
#
# This script is idempotent: running it multiple times in the same state
# produces the same comment (dedup via hash) and the same exit code.

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

die() { echo "[stop.sh] ERROR: $*" >&2; exit 1; }

# Atomic write: write to tmp then rename
atomic_write() {
  local target="$1"
  local content="$2"
  local tmp
  tmp=$(mktemp "${target}.XXXXXX")
  printf '%s' "$content" > "$tmp"
  mv "$tmp" "$target"
}

# Read a field from loop.json using only shell+awk (no jq dependency)
json_field() {
  local file="$1"
  local field="$2"
  awk -F'"' -v k="$field" '
    $2 == k {
      # value is either a quoted string or a bare token (true/false/number)
      if ($3 ~ /[[:space:]]*:[[:space:]]*"/) {
        print $4
      } else {
        gsub(/[[:space:]:,}]/, "", $3)
        print $3
      }
    }
  ' "$file" | head -1
}

# Compute dedup hash: sha256(issue_id + iteration + phase), first 8 hex chars
dedup_hash() {
  local issue_id="$1"
  local iteration="$2"
  local phase="$3"
  printf '%s' "${issue_id}${iteration}${phase}" \
    | sha256sum \
    | cut -c1-8
}

# ---------------------------------------------------------------------------
# Locate issue_id
# ---------------------------------------------------------------------------

MULTICA_WORKDIR="${MULTICA_WORKDIR:-$(pwd)}"
STATE_ROOT="${MULTICA_WORKDIR}/.multica/state"

issue_id=""
if [[ -n "${MULTICA_ISSUE_ID:-}" ]]; then
  issue_id="$MULTICA_ISSUE_ID"
elif [[ -f "${MULTICA_WORKDIR}/.multica/current_issue" ]]; then
  issue_id=$(cat "${MULTICA_WORKDIR}/.multica/current_issue")
fi

# No active issue → nothing to enforce, allow Stop
if [[ -z "$issue_id" ]]; then
  exit 0
fi

ISSUE_STATE_DIR="${STATE_ROOT}/${issue_id}"
LOOP_JSON="${ISSUE_STATE_DIR}/loop.json"

# No loop.json → no active loop, allow Stop
if [[ ! -f "$LOOP_JSON" ]]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# Read loop state
# ---------------------------------------------------------------------------

active=$(json_field "$LOOP_JSON" "active")
iteration=$(json_field "$LOOP_JSON" "iteration")
phase=$(json_field "$LOOP_JSON" "phase")
max_iterations=$(json_field "$LOOP_JSON" "max_iterations")

# Loop not active → allow Stop
if [[ "$active" != "true" ]]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# Throttle: skip if state file was modified in the last 60 seconds
# ---------------------------------------------------------------------------

if [[ -n "$(find "$LOOP_JSON" -mmin -1 2>/dev/null)" ]]; then
  # State written within last 60s — too soon to re-checkpoint, block quietly
  exit 2
fi

# ---------------------------------------------------------------------------
# Check for completion signal <promise>DONE</promise>
# ---------------------------------------------------------------------------

done_signal=false

# Check CLAUDE_TOOL_OUTPUT env var (Claude Code injects last tool output here)
if [[ -n "${CLAUDE_TOOL_OUTPUT:-}" ]]; then
  if printf '%s' "$CLAUDE_TOOL_OUTPUT" | grep -qF '<promise>DONE</promise>'; then
    done_signal=true
  fi
fi

# Fallback: check a tmp capture file if set
if [[ "$done_signal" == "false" && -n "${MULTICA_OUTPUT_FILE:-}" && -f "${MULTICA_OUTPUT_FILE}" ]]; then
  if grep -qF '<promise>DONE</promise>' "$MULTICA_OUTPUT_FILE"; then
    done_signal=true
  fi
fi

# ── Squad leader activity audit ───────────────────────────────────────────
# Check if squad-activity.marker was written this turn; set warning if not.
squad_leader_audit() {
  local _squad_marker="## Squad Operating Protocol"
  local _claude_md="${MULTICA_WORKDIR}/CLAUDE.md"
  if [[ -f "$_claude_md" ]] && grep -qF "$_squad_marker" "$_claude_md"; then
    if [[ -n "${MULTICA_ISSUE_ID:-}" ]]; then
      local _marker_file="${MULTICA_WORKDIR}/.multica/state/${MULTICA_ISSUE_ID}/squad-activity.marker"
      local _warn_file="${MULTICA_WORKDIR}/.multica/state/squad-audit-warning"
      if [[ ! -f "$_marker_file" ]]; then
        mkdir -p "${MULTICA_WORKDIR}/.multica/state"
        echo "Squad activity not recorded for issue ${MULTICA_ISSUE_ID} at $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$_warn_file"
      fi
      # Clean up marker for next turn
      rm -f "$_marker_file"
    fi
  fi
}

# ---------------------------------------------------------------------------
# Branch: DONE signal detected
# ---------------------------------------------------------------------------

if [[ "$done_signal" == "true" ]]; then
  # Write [loop-complete] comment
  multica issue comment add \
    --issue "$issue_id" \
    --body "[loop-complete] All stories verified. Loop finished at iteration ${iteration}." \
    2>/dev/null || true

  # Mark loop inactive atomically
  updated_json=$(cat "$LOOP_JSON" \
    | sed 's/"active":[[:space:]]*true/"active": false/' \
    | sed "s/\"phase\":[[:space:]]*\"[^\"]*\"/\"phase\": \"complete\"/")
  atomic_write "$LOOP_JSON" "$updated_json"

  squad_leader_audit
  exit 0
fi

# ---------------------------------------------------------------------------
# Not done: write checkpoint comment (with dedup) and block Stop
# ---------------------------------------------------------------------------

hash=$(dedup_hash "$issue_id" "$iteration" "$phase")

# Check if a comment with this dedup hash already exists
existing=$(multica issue comment list --issue "$issue_id" 2>/dev/null \
  | grep -F "[checkpoint:${hash}]" || true)

if [[ -z "$existing" ]]; then
  multica issue comment add \
    --issue "$issue_id" \
    --body "[checkpoint:${hash}] Loop active at iteration ${iteration}, phase=${phase}. Continuing." \
    2>/dev/null || true
fi

squad_leader_audit

# Block Stop — Claude Code interprets exit 2 as "do not stop"
exit 2
