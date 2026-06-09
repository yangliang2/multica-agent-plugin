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
  printf '{"hookSpecificOutput": {"additionalContext": ""}}\n'
  exit 0
fi

MULTICA_WORKDIR="${MULTICA_WORKDIR:-$(pwd)}"
NOTEPAD="${MULTICA_WORKDIR}/.multica/notepad.md"
LEARNINGS="${MULTICA_WORKDIR}/.multica/learnings.jsonl"
HOOK_LOG="${MULTICA_WORKDIR}/.multica/logs/hook-errors.log"

log_error() {
  mkdir -p "$(dirname "$HOOK_LOG")"
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [session-start.sh] $*" >> "$HOOK_LOG" 2>/dev/null || true
}

# H9: runtime check — multica CLI >= 0.4.0 required
_MULTICA_MIN_VERSION="0.4.0"
if command -v multica >/dev/null 2>&1; then
  _multica_ver=$(multica --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "")
  if [[ -n "$_multica_ver" ]]; then
    _ver_ok=$(python3 -c "
import sys
def vt(v): return tuple(int(x) for x in v.split('.'))
try:
    print('ok' if vt(sys.argv[1]) >= vt(sys.argv[2]) else 'old')
except Exception:
    print('ok')  # unparseable — don't block
" "$_multica_ver" "$_MULTICA_MIN_VERSION" 2>/dev/null || echo "ok")
    if [[ "$_ver_ok" == "old" ]]; then
      log_error "multica CLI ${_multica_ver} < ${_MULTICA_MIN_VERSION} — upgrade with: npm install -g @multica/cli"
      context_parts+=("## CLI Version Warning"$'\n'"multica CLI ${_multica_ver} is below the required minimum ${_MULTICA_MIN_VERSION}. Some features may not work. Upgrade: npm install -g @multica/cli")
    fi
  fi
fi

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
# Section 0: Autopilot run-only mode detection
# ---------------------------------------------------------------------------
if [[ -n "${MULTICA_AUTOPILOT_RUN_ID:-}" ]] && [[ -z "${MULTICA_ISSUE_ID:-}" ]]; then
  # Autopilot run-only: no issue context, output is captured as run result
  context_parts+=("## Autopilot Mode"$'\n'"Autopilot run ID: ${MULTICA_AUTOPILOT_RUN_ID}
This is a run-only autopilot task. Rules:
- Do NOT call multica issue get/comment/status — there is no issue
- Write your result to stdout only; the platform captures it automatically
- Use multica autopilot get ${MULTICA_AUTOPILOT_RUN_ID} --output json if you need configuration
- Persistence loop (loop.json) and HITL protocols do not apply in this mode")
fi

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

_stale_keys_arr=()
if [[ -f "$LEARNINGS" && -s "$LEARNINGS" ]]; then
  # M10: guard against oversized learnings file (max 1MB / 1000 lines)
  _learnings_size=$(wc -c < "$LEARNINGS" 2>/dev/null || echo "0")
  _learnings_lines=$(wc -l < "$LEARNINGS" 2>/dev/null || echo "0")
  _learnings_size=${_learnings_size//[^0-9]/}
  _learnings_lines=${_learnings_lines//[^0-9]/}
  _learnings_size=${_learnings_size:-0}
  _learnings_lines=${_learnings_lines:-0}
  if [[ $_learnings_size -gt 1048576 ]] || [[ $_learnings_lines -gt 1000 ]]; then
    log_error "learnings.jsonl too large (${_learnings_size} bytes, ${_learnings_lines} lines) — skipping to avoid SessionStart freeze. Trim with: python3 -c \"import sys; lines=open(sys.argv[1]).readlines(); open(sys.argv[1],'w').writelines(lines[-100:])\" .multica/learnings.jsonl"
    context_parts+=("## Knowledge Warning"$'\n'"learnings.jsonl exceeds size limit (${_learnings_lines} lines, ${_learnings_size} bytes). Prior learnings skipped this session. Trim the file to restore learning injection.")
  elif command -v python3 >/dev/null 2>&1; then
    # Pass the raw learnings file directly to python3 which handles:
    # - confidence>=7 filtering (replaces awk ERE/BRE-ambiguous high_conf)
    # - recent-10 + dedup logic
    # - C5: key validation, path traversal rejection, insight sanitization
    _learnings_tmp=$(mktemp)
    cp "$LEARNINGS" "$_learnings_tmp"
    _py_result=$(python3 - "$MULTICA_WORKDIR" "$_learnings_tmp" <<'PYEOF'
import json, sys, re
from pathlib import Path
from datetime import datetime

workdir = sys.argv[1]
entries_file = sys.argv[2]

# Load all entries, dedup by key (last-wins), keep recent 10 + confidence>=7
all_entries = []
with open(entries_file) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            e = json.loads(line)
            all_entries.append(e)
        except Exception:
            continue

seen_keys = {}
for e in all_entries:
    k = e.get("key", "")
    if k:
        seen_keys[k] = e

recent_keys = [e.get("key","") for e in all_entries[-10:] if e.get("key","")]
high_conf_keys = [k for k, e in seen_keys.items() if e.get("confidence", 0) >= 7]
candidate_keys = list(dict.fromkeys(recent_keys + high_conf_keys))[:20]
candidates = [seen_keys[k] for k in candidate_keys if k in seen_keys]
KEY_RE = re.compile(r'^[A-Za-z0-9._-]{1,64}$')
UNSAFE_CHARS_RE = re.compile(r'[`\\\[\]<>{}|]')
lines = []
stale_keys = []

for e in candidates:
        key     = e.get("key", "")
        insight = e.get("insight", "")
        conf    = e.get("confidence", 0)
        ts      = e.get("ts", "")
        files   = e.get("files", [])

        # C5: validate key format
        if not key or not KEY_RE.match(key):
            continue
        if not insight:
            continue

        # C5: sanitize insight — reject control chars (incl. newlines), strip structural chars, cap length
        if any(ord(c) < 0x20 for c in insight):
            continue  # reject entries with embedded newlines/control chars
        if len(insight) > 280:
            insight = insight[:280]
        insight = UNSAFE_CHARS_RE.sub('', insight).strip()
        if not insight:
            continue

        # C5: check files[] for path traversal (reject absolute paths and ..)
        safe_files = []
        for f in files:
            if not isinstance(f, str):
                continue
            if Path(f).is_absolute() or '..' in Path(f).parts:
                continue
            safe_files.append(f)

        # Staleness check using only safe relative files
        stale = False
        if safe_files and ts:
            try:
                entry_time = datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
                for f in safe_files:
                    fp = Path(workdir) / f
                    if not fp.exists():
                        stale = True
                        break
                    if fp.stat().st_mtime > entry_time:
                        stale = True
                        break
            except Exception:
                pass

        prefix = "[possibly stale] " if stale else ""
        lines.append(f"- {prefix}[{key}] (conf:{conf}) {insight}")
        if stale:
            stale_keys.append(f"STALE_KEY:{key}")

for l in lines:
    print(l)
for s in stale_keys:
    print(s)
PYEOF
      )
      rm -f "$_learnings_tmp"
      insights=""
      while IFS= read -r _rline; do
        if [[ "$_rline" == STALE_KEY:* ]]; then
          _stale_keys_arr+=("${_rline#STALE_KEY:}")
        else
          insights="${insights}${_rline}"$'\n'
        fi
      done <<< "$_py_result"
    if [[ -n "$insights" ]]; then
      context_parts+=("## Prior Learnings"$'\n'"$insights")
    fi

    # Post [knowledge-warning] issue comment for stale learnings — batched into one comment,
    # with a per-session marker to avoid re-posting on every resume
    if [[ ${#_stale_keys_arr[@]} -gt 0 ]] && [[ -n "${MULTICA_ISSUE_ID:-}" ]] && command -v multica >/dev/null 2>&1; then
      _stale_marker="${MULTICA_WORKDIR}/.multica/state/${MULTICA_ISSUE_ID}/stale-warning-$(date -u +%Y%m%d).marker"
      if [[ ! -f "$_stale_marker" ]]; then
        _stale_list=$(printf '"%s" ' "${_stale_keys_arr[@]}")
        multica issue comment add "$MULTICA_ISSUE_ID" \
          --content "[knowledge-warning] ${#_stale_keys_arr[@]} prior learning(s) may be stale (source files modified): ${_stale_list%. }. Agent will proceed with caution." \
          2>/dev/null && touch "$_stale_marker" || log_error "failed to post knowledge-warning"
      fi
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
    # H6: replace awk JSON parsing with python3 for correctness on all platforms
    _loop_fields=$(python3 -c "
import json, sys
PHASE_OK = {'setup','execution','execute','deslop','complete','blocked','verification','report',
            'spec','plan','demo','verify','result','done'}
try:
    d = json.load(open(sys.argv[1]))
    active = str(d.get('active', False)).lower()
    iteration = str(d.get('iteration', 0))
    raw_phase = d.get('phase', '')
    phase = raw_phase if raw_phase in PHASE_OK else ''
    mode = d.get('mode', 'execution')
    spec_version = str(d.get('spec_version', 0))
    verification_cmd = d.get('verification_cmd', '')
    next_story = ''
    for s in d.get('stories', []):
        if not s.get('passes', True):
            next_story = s.get('title', '')
            break
    print(f'{active}|{iteration}|{phase}|{next_story}|{mode}|{spec_version}|{verification_cmd}')
except Exception:
    print('false||||execution|0|')
" "$LOOP_JSON" 2>/dev/null || echo "false||||execution|0|")
    active="${_loop_fields%%|*}"
    _rest="${_loop_fields#*|}"
    iteration="${_rest%%|*}"
    _rest="${_rest#*|}"
    phase="${_rest%%|*}"
    _rest="${_rest#*|}"
    next_story="${_rest%%|*}"
    _rest="${_rest#*|}"
    loop_mode="${_rest%%|*}"
    _rest="${_rest#*|}"
    loop_spec_version="${_rest%%|*}"
    loop_verification_cmd="${_rest#*|}"

    if [[ "$active" == "true" ]]; then
      # H4: generate/refresh nonce for DONE signal binding
      _nonce_file="${MULTICA_WORKDIR}/.multica/state/${issue_id}/done-nonce.txt"
      _nonce=$(cat "$_nonce_file" 2>/dev/null || true)
      if [[ -z "$_nonce" ]]; then
        _nonce=$(printf '%s%s' "$issue_id" "$(date -u +%s%N 2>/dev/null || date -u +%s)" \
          | sha256sum | cut -c1-12)
        mkdir -p "$(dirname "$_nonce_file")"
        printf '%s' "$_nonce" > "$_nonce_file"
      fi

      loop_hint="Resuming issue ${issue_id}: iteration ${iteration}, phase=${phase}, mode=${loop_mode:-execution}, spec_version=${loop_spec_version:-0}."
      if [[ -n "$next_story" ]]; then
        loop_hint="${loop_hint} Next story: ${next_story}"
      fi
      if [[ -n "${loop_verification_cmd:-}" ]]; then
        loop_hint="${loop_hint} Verification cmd: ${loop_verification_cmd}"
      fi
      loop_hint="${loop_hint} Emit <promise>DONE:${_nonce}</promise> when complete."

      context_parts+=("## Loop State"$'\n'"$loop_hint")

      # v2.3.0: inject phase-specific action guidance
      _phase_guidance=""
      case "$phase" in
        spec)
          _phase_guidance="You are resuming the spec phase. Fetch issue comments (<<cli:issue.comment.list>>). If you find [proceed] in comments: set loop.json phase='plan' and advance. If you find [revise: <feedback>]: incorporate feedback, regenerate spec, post new [spec:vN] comment, then emit DONE."
          ;;
        plan)
          _phase_guidance="You are in the plan phase. Read the spec from the most recent [spec:vN] comment. Decompose into ordered sub-steps; store them in loop.json progress fields. Post [phase] spec→plan comment. Set loop.json phase='plan'. Emit DONE to auto-advance to demo."
          ;;
        demo)
          _phase_guidance="You are resuming the demo phase. Fetch issue comments (<<cli:issue.comment.list>>). If you find [looks-right]: set loop.json phase='execute' and advance. If you find [wrong: <feedback>]: rebuild demo with feedback, post new [demo:vN] comment, then emit DONE."
          ;;
        execute)
          # existing loop hint is sufficient for execute phase
          ;;
        verify)
          _phase_guidance="You are in the verify phase. Run the verification_cmd from loop.json (or detect from ecosystem). Post [verification] comment with exit_code, command, output_hash. If verification passes: set loop.json phase='verify' and emit DONE (auto-advances to result). If it fails after 3 attempts: post [verify-failed] and emit DONE."
          ;;
        result)
          _phase_guidance="You are in the result phase. Synthesize a final summary of what was done. Post [result] comment with summary and any caveats. Set issue status done (<<cli:issue.status>>). Emit DONE."
          ;;
      esac
      if [[ -n "$_phase_guidance" ]]; then
        context_parts+=("## Phase Guidance"$'\n'"$_phase_guidance")
      fi
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
      bounce_context=$(python3 -c "
import json, sys
try:
    data = json.load(open(sys.argv[1]))
    for qid, v in data.items():
        count = v.get('count', 0)
        print(f'HITL bounce count for {qid}: {count}/3')
except Exception:
    pass
" "$bounces_file" 2>/dev/null || true)
    fi
  fi
  if [[ -n "$bounce_context" ]]; then
    squad_part="${squad_part}"$'\n'"${bounce_context}"
  fi

  context_parts+=("## Squad Context"$'\n'"$squad_part")
fi

# HITL pending guard: warn if issue is blocked with unanswered HITL
if [[ -n "${MULTICA_ISSUE_ID:-}" ]]; then
  _bounces="${MULTICA_WORKDIR}/.multica/state/${MULTICA_ISSUE_ID}/hitl-bounces.json"
  if [[ -f "$_bounces" ]]; then
    _pending=$(python3 -c "
import json, sys
from datetime import datetime, timezone
data = json.load(open(sys.argv[1]))
timeout_h = float(sys.argv[2])
pending = []
for qid, v in data.items():
    ts = v.get('last_at', '')
    tier = v.get('tier', 'leader')
    if ts:
        dt = datetime.fromisoformat(ts.replace('Z', '+00:00'))
        hours = (datetime.now(timezone.utc) - dt).total_seconds() / 3600
        if hours < timeout_h:
            pending.append(f'{qid}:{tier}')
print(','.join(pending))
" "$_bounces" "${MULTICA_HITL_TIMEOUT_HOURS:-24}" 2>/dev/null || echo "")
    if [[ -n "$_pending" ]]; then
      context_parts=("## ⚠️ HITL Pending — Read Before Acting"$'\n'"This issue has unanswered HITL questions: ${_pending}.
BEFORE doing any new work:
1. Run <<cli:issue.comment.list>> to find the human reply
2. If reply found: proceed with the answer, clear blocked_reason metadata
3. If no reply yet: re-post the HITL question and set blocked again — do NOT proceed" "${context_parts[@]}")
    fi
  fi
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
      _timed_out=$(python3 -c "
import sys
try:
    print('yes' if float(sys.argv[1]) > float(sys.argv[2]) else 'no')
except Exception:
    print('no')
" "$_hours" "$_threshold" 2>/dev/null || echo "no")
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
