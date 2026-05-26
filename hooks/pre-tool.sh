#!/usr/bin/env bash
set -euo pipefail

# Multica session guard: only run in Multica daemon context
if [[ "${DISABLE_MULTICA_PLUGIN:-0}" == "1" ]]; then
  exit 0
fi
_is_multica=false
if [[ -n "${MULTICA_ISSUE_ID:-}" ]] || [[ "${MULTICA_AGENT_SESSION:-0}" == "1" ]]; then
  _is_multica=true
fi
if [[ "$_is_multica" == "false" ]]; then
  exit 0
fi

# pre-tool.sh — Multica destructive-guard (Claude Code PreToolUse hook)
#
# Checks the Bash tool command against tools/safe-exec.deny.list.
# Non-Bash tools are allowed through without inspection.
#
# Exit codes:
#   0  — tool call permitted
#   1  — tool call blocked (matched deny pattern)
#   2  — tool call blocked (Claude Code stop-and-retry signal, not used here)

MULTICA_WORKDIR="${MULTICA_WORKDIR:-$(pwd)}"
PLUGIN_ROOT="${MULTICA_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DENY_LIST="${PLUGIN_ROOT}/tools/safe-exec.deny.list"

issue_id=""
if [[ -n "${MULTICA_ISSUE_ID:-}" ]]; then
  issue_id="$MULTICA_ISSUE_ID"
elif [[ -f "${MULTICA_WORKDIR}/.multica/current_issue" ]]; then
  issue_id=$(cat "${MULTICA_WORKDIR}/.multica/current_issue")
fi

post_comment() {
  local body="$1"
  if [[ -n "$issue_id" ]] && command -v multica >/dev/null 2>&1; then
    multica issue comment add "$issue_id" \
      --content "$body" \
      2>/dev/null || true
  fi
}

# Read tool name and input from stdin JSON (Claude Code PreToolUse hook contract).
# Claude Code passes hook data as JSON on stdin, NOT as environment variables.
# Fallback to env vars for backward compatibility with test harnesses.
_hook_input=$(cat)

tool_name=$(printf '%s' "$_hook_input" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('tool_name', ''))
except Exception:
    pass
" 2>/dev/null || echo "${CLAUDE_TOOL_NAME:-}")

if [[ "$tool_name" != "Bash" ]]; then
  exit 0
fi

command_str=$(printf '%s' "$_hook_input" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    inp = d.get('tool_input', d.get('input', {}))
    if isinstance(inp, dict):
        print(inp.get('command', ''))
    else:
        print('')
except Exception:
    pass
" 2>/dev/null || echo "")

# Fallback: if stdin parse gave nothing, try legacy env var path
if [[ -z "$command_str" ]]; then
  _legacy_input="${CLAUDE_TOOL_INPUT:-}"
  if [[ -n "$_legacy_input" ]]; then
    command_str=$(printf '%s' "$_legacy_input" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('command', ''))
except Exception:
    pass
" 2>/dev/null || echo "")
  fi
fi

if [[ -z "$command_str" ]]; then
  exit 0
fi

# Check against deny list
if [[ -f "$DENY_LIST" ]]; then
  while IFS= read -r pattern; do
    # Skip comments and blank lines
    [[ -z "$pattern" || "$pattern" == \#* ]] && continue
    if printf '%s' "$command_str" | grep -qiF "$pattern" 2>/dev/null; then
      post_comment "[destructive-guard] Tool call blocked — matched deny pattern: \`${pattern}\`
Command: \`${command_str:0:200}\`
To override, run the command manually outside the daemon."
      exit 1
    fi
  done < "$DENY_LIST"
fi

exit 0
