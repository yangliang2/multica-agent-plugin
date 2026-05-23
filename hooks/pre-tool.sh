#!/usr/bin/env bash
set -euo pipefail

# pre-tool.sh — Multica destructive-guard proxy (Claude Code PreToolUse hook)
#
# Thin proxy: passes tool arguments to `multica safe-exec` for capability gating.
# If `multica safe-exec` is unavailable, fails closed with a [capability=missing]
# comment and exits 1 (blocks the tool call).
#
# Exit codes:
#   0  — tool call permitted
#   1  — tool call blocked (capability missing or denied)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

MULTICA_WORKDIR="${MULTICA_WORKDIR:-$(pwd)}"

# Locate current issue for comment attribution (best-effort; non-fatal if absent)
issue_id=""
if [[ -n "${MULTICA_ISSUE_ID:-}" ]]; then
  issue_id="$MULTICA_ISSUE_ID"
elif [[ -f "${MULTICA_WORKDIR}/.multica/current_issue" ]]; then
  issue_id=$(cat "${MULTICA_WORKDIR}/.multica/current_issue")
fi

post_comment() {
  local body="$1"
  if [[ -n "$issue_id" ]]; then
    multica issue comment add \
      --issue "$issue_id" \
      --body "$body" \
      2>/dev/null || true
  fi
}

# ---------------------------------------------------------------------------
# Check multica safe-exec availability
# ---------------------------------------------------------------------------

if ! command -v multica >/dev/null 2>&1; then
  post_comment "[capability=missing:destructive-guard] multica CLI not found; tool call blocked as fail-closed."
  exit 1
fi

if ! multica safe-exec --help >/dev/null 2>&1; then
  post_comment "[capability=missing:destructive-guard] multica safe-exec subcommand unavailable; tool call blocked as fail-closed."
  exit 1
fi

# ---------------------------------------------------------------------------
# Proxy tool args to multica safe-exec
# ---------------------------------------------------------------------------

# CLAUDE_TOOL_NAME and CLAUDE_TOOL_INPUT are set by Claude Code for PreToolUse hooks.
# Pass them through to multica safe-exec for capability evaluation.

tool_name="${CLAUDE_TOOL_NAME:-}"
tool_input="${CLAUDE_TOOL_INPUT:-}"

exec multica safe-exec \
  --tool-name "$tool_name" \
  --tool-input "$tool_input" \
  --issue "${issue_id:-}"
