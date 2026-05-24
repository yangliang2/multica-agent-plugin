#!/usr/bin/env bash
set -euo pipefail

# session-start.sh — Multica session context injector (Claude Code SessionStart hook)
#
# Reads Priority Context from notepad, recent + high-confidence learnings,
# and current loop state, then outputs them as additionalContext JSON.
#
# Output format (Claude Code SessionStart hook contract):
#   {"hookSpecificOutput": {"additionalContext": "<text>"}}

MULTICA_WORKDIR="${MULTICA_WORKDIR:-$(pwd)}"
NOTEPAD="${MULTICA_WORKDIR}/.multica/notepad.md"
LEARNINGS="${MULTICA_WORKDIR}/.multica/learnings.jsonl"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Escape a string for JSON: escape backslash, double-quote, and control chars
json_escape() {
  local s="$1"
  # Replace \ → \\, " → \", newline → \n, tab → \t
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

context_parts=()

# ---------------------------------------------------------------------------
# 1. Priority Context section from notepad (≤500 chars)
# ---------------------------------------------------------------------------

if [[ -f "$NOTEPAD" ]]; then
  priority_raw=$(awk '
    /^## Priority Context/ { capture=1; next }
    /^## / && capture      { exit }
    capture                { print }
  ' "$NOTEPAD" | head -c 500)

  priority_trimmed="${priority_raw#"${priority_raw%%[![:space:]]*}"}"  # ltrim
  priority_trimmed="${priority_trimmed%"${priority_trimmed##*[![:space:]]}"}"  # rtrim

  if [[ -n "$priority_trimmed" ]]; then
    context_parts+=("## Priority Context"$'\n'"$priority_trimmed")
  fi
fi

# ---------------------------------------------------------------------------
# 2. Learnings: 10 most recent + all with confidence >= 7
# ---------------------------------------------------------------------------

if [[ -f "$LEARNINGS" && -s "$LEARNINGS" ]]; then
  # Most recent 10 lines
  recent=$(tail -n 10 "$LEARNINGS")

  # High-confidence entries (confidence >= 7): parse with awk
  high_conf=$(awk '
    /"confidence":[[:space:]]*([89]|10)/ { print }
    /"confidence":[[:space:]]*7/          { print }
  ' "$LEARNINGS")

  # Merge, deduplicate by line, keep order (recent first)
  learnings_combined=$(printf '%s\n%s\n' "$recent" "$high_conf" \
    | awk '!seen[$0]++' \
    | head -n 20)

  if [[ -n "$learnings_combined" ]]; then
    # Extract insight fields for readable output
    insights=$(printf '%s\n' "$learnings_combined" \
      | awk -F'"' '
          {
            insight=""
            key=""
            conf=""
            for(i=1;i<=NF;i++){
              if($i=="insight")  insight=$(i+2)
              if($i=="key")      key=$(i+2)
              if($i=="confidence"){ gsub(/[^0-9]/,"",$( i+1)); conf=$(i+1) }
            }
            if(insight!="") printf "- [%s] (conf:%s) %s\n", key, conf, insight
          }
        ')

    if [[ -n "$insights" ]]; then
      context_parts+=("## Prior Learnings"$'\n'"$insights")
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 3. Current loop state (if active)
# ---------------------------------------------------------------------------

issue_id=""
if [[ -n "${MULTICA_ISSUE_ID:-}" ]]; then
  issue_id="$MULTICA_ISSUE_ID"
elif [[ -f "${MULTICA_WORKDIR}/.multica/current_issue" ]]; then
  issue_id=$(cat "${MULTICA_WORKDIR}/.multica/current_issue")
fi

if [[ -n "$issue_id" ]]; then
  LOOP_JSON="${MULTICA_WORKDIR}/.multica/state/${issue_id}/loop.json"

  if [[ -f "$LOOP_JSON" ]]; then
    active=$(awk -F'"' '/"active"/{print $4}' "$LOOP_JSON" | head -1)
    # Handle bare true/false (not quoted)
    if [[ -z "$active" ]]; then
      active=$(awk '/"active"/{gsub(/[^a-z]/,"",$2); print $2}' "$LOOP_JSON" | head -1)
    fi

    if [[ "$active" == "true" ]]; then
      iteration=$(awk -F'"' '/"iteration"/{gsub(/[^0-9]/,"",$3); print $3}' "$LOOP_JSON" | head -1)
      phase=$(awk -F'"' '/"phase"/{print $4}' "$LOOP_JSON" | head -1)

      # Find first incomplete story
      next_story=$(awk -F'"' '
        /"passes"/ && /false/ { found=1 }
        /"title"/ && found    { print $4; exit }
      ' "$LOOP_JSON")

      loop_hint="Resuming issue ${issue_id}: iteration ${iteration}, phase=${phase}."
      if [[ -n "$next_story" ]]; then
        loop_hint="${loop_hint} Next story: ${next_story}"
      fi

      context_parts+=("## Loop State"$'\n'"$loop_hint")
    fi
  fi
fi

SQUAD_PROTOCOL_MARKER="## Squad Operating Protocol"
claude_md="${MULTICA_WORKDIR}/CLAUDE.md"

if [[ -f "$claude_md" ]] && grep -qF "$SQUAD_PROTOCOL_MARKER" "$claude_md"; then
  # Extract roster summary (capped at 800 bytes)
  roster_raw=$(awk '/^## Squad Roster/,/^## [^S]/' "$claude_md" | head -c 800)

  audit_warning=""
  warn_file="${MULTICA_WORKDIR}/.multica/state/squad-audit-warning"
  if [[ -f "$warn_file" ]]; then
    audit_warning="WARNING: Previous turn ended without calling multica squad activity. This is MANDATORY. Call it now before doing anything else."
    rm -f "$warn_file"
  fi

  squad_part="Squad Role: LEADER"
  if [[ -n "$audit_warning" ]]; then
    squad_part="${audit_warning}"$'\n'"${squad_part}"
  fi
  if [[ -n "$roster_raw" ]]; then
    squad_part="${squad_part}"$'\n'"Roster (excerpt):"$'\n'"${roster_raw}"
  fi

  bounce_context=""
  if [[ -n "${MULTICA_ISSUE_ID:-}" ]]; then
    bounces_file="${MULTICA_WORKDIR}/.multica/state/${MULTICA_ISSUE_ID}/hitl-bounces.json"
    if [[ -f "$bounces_file" ]]; then
      while IFS= read -r line; do
        bounce_context+="$line"$'\n'
      done < <(awk '
        /"[^"]+": \{/ { key=$0; gsub(/[": {]/, "", key); gsub(/^[[:space:]]+/, "", key) }
        /"count":/ { gsub(/[^0-9]/, "", $2); print "HITL bounce count for " key ": " $2 "/3" }
      ' "$bounces_file")
    fi
  fi
  if [[ -n "$bounce_context" ]]; then
    squad_part="${squad_part}"$'\n'"${bounce_context}"
  fi

  context_parts+=("## Squad Context"$'\n'"$squad_part")
fi

_caps_file="${MULTICA_PLUGIN_ROOT:-$(dirname "${BASH_SOURCE[0]}")/..}/capabilities/claude-code.json"
MULTICA_MODEL_FAST="haiku"
MULTICA_MODEL_STD="sonnet"
MULTICA_MODEL_DEEP="opus"

if [[ -f "$_caps_file" ]] && command -v jq >/dev/null 2>&1; then
  _fast=$(jq -r '.model_routing.fast // empty' "$_caps_file" 2>/dev/null)
  _std=$(jq -r '.model_routing.standard // empty' "$_caps_file" 2>/dev/null)
  _deep=$(jq -r '.model_routing.deep // empty' "$_caps_file" 2>/dev/null)
  [[ -n "$_fast" ]] && MULTICA_MODEL_FAST="$_fast"
  [[ -n "$_std" ]] && MULTICA_MODEL_STD="$_std"
  [[ -n "$_deep" ]] && MULTICA_MODEL_DEEP="$_deep"
fi
export MULTICA_MODEL_FAST MULTICA_MODEL_STD MULTICA_MODEL_DEEP

context_parts+=("## Model Routing"$'\n'"Model routing: fast=${MULTICA_MODEL_FAST} std=${MULTICA_MODEL_STD} deep=${MULTICA_MODEL_DEEP}")

# ---------------------------------------------------------------------------
# Assemble and output JSON
# ---------------------------------------------------------------------------

if [[ ${#context_parts[@]} -eq 0 ]]; then
  # Nothing to inject — output empty additionalContext (valid, no-op)
  printf '{"hookSpecificOutput": {"additionalContext": ""}}\n'
  exit 0
fi

# Join parts with double newline separator
combined=""
for part in "${context_parts[@]}"; do
  if [[ -n "$combined" ]]; then
    combined="${combined}"$'\n\n'"${part}"
  else
    combined="$part"
  fi
done

escaped=$(json_escape "$combined")

printf '{"hookSpecificOutput": {"additionalContext": "%s"}}\n' "$escaped"
