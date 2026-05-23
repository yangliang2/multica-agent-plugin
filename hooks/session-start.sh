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
