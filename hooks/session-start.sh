#!/usr/bin/env bash
set -euo pipefail

MULTICA_WORKDIR="${MULTICA_WORKDIR:-$(pwd)}"
NOTEPAD="${MULTICA_WORKDIR}/.multica/notepad.md"
LEARNINGS="${MULTICA_WORKDIR}/.multica/learnings.jsonl"
HOOK_LOG="${MULTICA_WORKDIR}/.multica/logs/hook-errors.log"

json_escape() {
  local s="$1"
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

  priority_trimmed="${priority_raw#"${priority_raw%%[![:space:]]*}"}"
  priority_trimmed="${priority_trimmed%"${priority_trimmed##*[![:space:]]}"}"

  if [[ -n "$priority_trimmed" ]]; then
    context_parts+=("## Priority Context"$'\n'"$priority_trimmed")
  fi
fi

if [[ -f "$LEARNINGS" && -s "$LEARNINGS" ]]; then
  recent=$(tail -n 10 "$LEARNINGS")

  high_conf=$(awk '
    /"confidence":[[:space:]]*([89]|10)/ { print }
    /"confidence":[[:space:]]*7/          { print }
  ' "$LEARNINGS")

  learnings_combined=$(printf '%s\n%s\n' "$recent" "$high_conf" \
    | awk '!seen[$0]++' \
    | head -n 20)

  if [[ -n "$learnings_combined" ]]; then
    if command -v python3 >/dev/null 2>&1; then
      insights=""
      while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue

        result=$(python3 - "$entry" "$MULTICA_WORKDIR" <<'PYEOF'
import json, sys
from pathlib import Path
from datetime import datetime

entry_str = sys.argv[1]
workdir   = sys.argv[2]

try:
    e = json.loads(entry_str)
except Exception:
    sys.exit(0)

key     = e.get("key", "")
insight = e.get("insight", "")
conf    = e.get("confidence", 0)
ts      = e.get("ts", "")
files   = e.get("files", [])

if not insight:
    sys.exit(0)

stale = False
if files and ts:
    try:
        entry_time = datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
        for f in files:
            fp = Path(f) if Path(f).is_absolute() else Path(workdir) / f
            if not fp.exists():
                stale = True
                break
            if fp.stat().st_mtime > entry_time:
                stale = True
                break
    except Exception:
        pass

prefix = "[possibly stale] " if stale else ""
print(f"- {prefix}[{key}] (conf:{conf}) {insight}")
PYEOF
        )
        [[ -n "$result" ]] && insights="${insights}${result}"$'\n'
      done <<< "$learnings_combined"
    else
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
    fi

    if [[ -n "$insights" ]]; then
      context_parts+=("## Prior Learnings"$'\n'"$insights")
    fi
  fi
fi

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
    if [[ -z "$active" ]]; then
      active=$(awk '/"active"/{gsub(/[^a-z]/,"",$2); print $2}' "$LOOP_JSON" | head -1)
    fi

    if [[ "$active" == "true" ]]; then
      iteration=$(awk -F'"' '/"iteration"/{gsub(/[^0-9]/,"",$3); print $3}' "$LOOP_JSON" | head -1)
      phase=$(awk -F'"' '/"phase"/{print $4}' "$LOOP_JSON" | head -1)

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
else
  if ! command -v jq >/dev/null 2>&1; then
    context_parts+=("## Config Warning"$'\n'"jq not available — model routing using built-in defaults (haiku/sonnet/opus). Install jq to enable custom routing.")
  fi
fi
export MULTICA_MODEL_FAST MULTICA_MODEL_STD MULTICA_MODEL_DEEP

context_parts+=("## Model Routing"$'\n'"Model routing: fast=${MULTICA_MODEL_FAST} std=${MULTICA_MODEL_STD} deep=${MULTICA_MODEL_DEEP}")

# Section 6: Thresholds from capabilities
_caps="${MULTICA_PLUGIN_ROOT:-$(dirname "${BASH_SOURCE[0]}")/..}/capabilities/claude-code.json"
MULTICA_HITL_TIMEOUT_HOURS=24
MULTICA_HITL_STRIKE_LIMIT=3
MULTICA_CONTEXT_CHECKPOINT_PCT=35
MULTICA_CONTEXT_BLOCKED_PCT=25
MULTICA_LOOP_MAX_ITERATIONS=50
if [[ -f "$_caps" ]] && command -v jq >/dev/null 2>&1; then
  _v=$(jq -r '.thresholds.hitl_timeout_hours // empty' "$_caps" 2>/dev/null)
  [[ -n "$_v" ]] && MULTICA_HITL_TIMEOUT_HOURS="$_v"
  _v=$(jq -r '.thresholds.hitl_strike_limit // empty' "$_caps" 2>/dev/null)
  [[ -n "$_v" ]] && MULTICA_HITL_STRIKE_LIMIT="$_v"
  _v=$(jq -r '.thresholds.context_checkpoint_pct // empty' "$_caps" 2>/dev/null)
  [[ -n "$_v" ]] && MULTICA_CONTEXT_CHECKPOINT_PCT="$_v"
  _v=$(jq -r '.thresholds.context_blocked_pct // empty' "$_caps" 2>/dev/null)
  [[ -n "$_v" ]] && MULTICA_CONTEXT_BLOCKED_PCT="$_v"
  _v=$(jq -r '.thresholds.loop_max_iterations // empty' "$_caps" 2>/dev/null)
  [[ -n "$_v" ]] && MULTICA_LOOP_MAX_ITERATIONS="$_v"
fi
export MULTICA_HITL_TIMEOUT_HOURS MULTICA_HITL_STRIKE_LIMIT \
       MULTICA_CONTEXT_CHECKPOINT_PCT MULTICA_CONTEXT_BLOCKED_PCT \
       MULTICA_LOOP_MAX_ITERATIONS
context_parts+=("## Thresholds"$'\n'"HITL timeout: ${MULTICA_HITL_TIMEOUT_HOURS}h | Strike limit: ${MULTICA_HITL_STRIKE_LIMIT} | Context checkpoint: ${MULTICA_CONTEXT_CHECKPOINT_PCT}% | Context blocked: ${MULTICA_CONTEXT_BLOCKED_PCT}% | Max iterations: ${MULTICA_LOOP_MAX_ITERATIONS}")

# Section 7: Consolidation prompt (one-shot)
_consolidation="${MULTICA_WORKDIR}/.multica/state/consolidation-prompt.txt"
if [[ -f "$_consolidation" ]]; then
  _cprompt=$(cat "$_consolidation")
  rm -f "$_consolidation"
  if [[ -n "$_cprompt" ]]; then
    context_parts=("## Memory Consolidation Task"$'\n'"$_cprompt" "${context_parts[@]}")
  fi
fi

# Section 8: HITL timeout detection
if [[ -n "${MULTICA_ISSUE_ID:-}" ]]; then
  _bounces="${MULTICA_WORKDIR}/.multica/state/${MULTICA_ISSUE_ID}/hitl-bounces.json"
  if [[ -f "$_bounces" ]]; then
    _last_hitl=$(python3 -c "
import json, sys
from datetime import datetime, timezone
data = json.load(open(sys.argv[1]))
latest = None
latest_qid = None
for qid, v in data.items():
    ts = v.get('last_at', '')
    if ts and (latest is None or ts > latest):
        latest = ts
        latest_qid = qid
if latest:
    dt = datetime.fromisoformat(latest.replace('Z', '+00:00'))
    hours_waited = (datetime.now(timezone.utc) - dt).total_seconds() / 3600
    print(f'{latest_qid}|{hours_waited:.1f}')
" "$_bounces" 2>/dev/null || echo "")
    if [[ -n "$_last_hitl" ]]; then
      _qid="${_last_hitl%%|*}"
      _hours="${_last_hitl##*|}"
      _threshold="${MULTICA_HITL_TIMEOUT_HOURS}"
      _timed_out=$(python3 -c "print('yes' if float('${_hours}') > float('${_threshold}') else 'no')" 2>/dev/null || echo "no")
      if [[ "$_timed_out" == "yes" ]]; then
        context_parts=("## HITL Timeout Alert"$'\n'"[HITL:timeout] question_id=${_qid} — waited ${_hours}h (threshold: ${_threshold}h).
Proceed with the most conservative available option without waiting for human reply.
Post a comment explaining: 'Waited ${_hours}h without reply, proceeding with most conservative option: <describe your choice>'." "${context_parts[@]}")
      fi
    fi
  fi
fi

if [[ -f "$HOOK_LOG" && -s "$HOOK_LOG" ]]; then
  recent_errors=$(tail -3 "$HOOK_LOG")
  context_parts+=("## Hook Errors (recent)"$'\n'"$recent_errors")
fi

if [[ ${#context_parts[@]} -eq 0 ]]; then
  printf '{"hookSpecificOutput": {"additionalContext": ""}}\n'
  exit 0
fi

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
