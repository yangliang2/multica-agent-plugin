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

HOOK_LOG="${MULTICA_WORKDIR}/.multica/logs/hook-errors.log"
log_error() {
  mkdir -p "$(dirname "$HOOK_LOG")"
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [pre-tool.sh] $*" >> "$HOOK_LOG" 2>/dev/null || true
}

_rate_check_and_record() {
  # M8: rate limit — at most 1 destructive-guard comment per minute per issue
  # Returns 0 (allowed to comment) or 1 (rate limited). Always records the hit.
  if [[ -z "$issue_id" ]]; then return 1; fi
  _rate_dir="${MULTICA_WORKDIR}/.multica/state/${issue_id}"
  _rate_file="${_rate_dir}/pretool-comment-rate.txt"
  _now=$(date -u +%s 2>/dev/null || echo 0)
  _last=$(cat "$_rate_file" 2>/dev/null || echo 0)
  _last=${_last//[^0-9]/}
  _last=${_last:-0}
  mkdir -p "$_rate_dir"
  if [[ $(( _now - _last )) -lt 60 ]]; then
    log_error "rate-limited destructive-guard comment for issue ${issue_id}"
    return 1
  fi
  echo "$_now" > "$_rate_file"
  return 0
}

post_comment() {
  local body="$1"
  if [[ -z "$issue_id" ]] || ! command -v multica >/dev/null 2>&1; then
    return 0
  fi
  multica issue comment add "$issue_id" \
    --content "$body" \
    2>/dev/null || log_error "failed to post destructive-guard comment"
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
    sys.exit(1)
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
    sys.exit(1)
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
    sys.exit(1)
" 2>/dev/null || echo "")
  fi
fi

if [[ -z "$command_str" ]]; then
  exit 0
fi

# Check against deny list (ERE patterns, case-insensitive)
if [[ ! -f "$DENY_LIST" ]]; then
  log_error "deny list not found at ${DENY_LIST} — fail-closed: Bash blocked until deny list is restored"
  exit 1
fi

# M8: truncate command for comment — hash instead of raw string to avoid leaking secrets
_cmd_len=${#command_str}
_cmd_hash=$(printf '%s' "$command_str" | sha256sum | cut -c1-8)
if [[ $_cmd_len -le 80 ]]; then
  _cmd_display="${command_str}"
else
  _cmd_display="${command_str:0:80}… (${_cmd_len} chars, sha256:${_cmd_hash})"
fi

while IFS= read -r pattern; do
  [[ -z "$pattern" || "$pattern" == \#* ]] && continue
  if printf '%s' "$command_str" | grep -qiE "$pattern" 2>/dev/null; then
    if _rate_check_and_record; then
      post_comment "[destructive-guard] Tool call blocked — matched deny pattern: \`${pattern}\`
Command: \`${_cmd_display}\`
To override, run the command manually outside the daemon."
    fi
    exit 1
  fi
done < "$DENY_LIST"

exit 0
