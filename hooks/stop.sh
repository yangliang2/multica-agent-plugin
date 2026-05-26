#!/usr/bin/env bash
set -euo pipefail

# Multica session guard: only run in Multica daemon context
if [[ "${DISABLE_MULTICA_PLUGIN:-0}" == "1" ]]; then
  exit 0
fi
_is_multica=false
if [[ -n "${MULTICA_ISSUE_ID:-}" ]] || [[ "${MULTICA_AGENT_SESSION:-1}" == "1" ]]; then
  _is_multica=true
fi
if [[ "$_is_multica" == "false" ]]; then
  exit 0
fi

# Autopilot run-only: no loop.json, no checkpoint comments needed
if [[ -n "${MULTICA_AUTOPILOT_RUN_ID:-}" ]] && [[ -z "${MULTICA_ISSUE_ID:-}" ]]; then
  exit 0
fi

die() { echo "[stop.sh] ERROR: $*" >&2; exit 1; }

atomic_write() {
  local target="$1"
  local content="$2"
  local tmp
  tmp=$(mktemp "${target}.XXXXXX")
  printf '%s' "$content" > "$tmp"
  mv "$tmp" "$target"
}

json_field() {
  local file="$1"
  local field="$2"
  awk -F'"' -v k="$field" '
    $2 == k {
      if ($3 ~ /[[:space:]]*:[[:space:]]*"/) {
        print $4
      } else {
        gsub(/[[:space:]:,}]/, "", $3)
        print $3
      }
    }
  ' "$file" | head -1
}

dedup_hash() {
  local issue_id="$1"
  local iteration="$2"
  local phase="$3"
  printf '%s' "${issue_id}${iteration}${phase}" \
    | sha256sum \
    | cut -c1-8
}

MULTICA_WORKDIR="${MULTICA_WORKDIR:-$(pwd)}"
STATE_ROOT="${MULTICA_WORKDIR}/.multica/state"
HOOK_LOG="${MULTICA_WORKDIR}/.multica/logs/hook-errors.log"

log_error() {
  mkdir -p "$(dirname "$HOOK_LOG")"
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [stop.sh] $*" >> "$HOOK_LOG" 2>/dev/null || true
}

issue_id=""
if [[ -n "${MULTICA_ISSUE_ID:-}" ]]; then
  issue_id="$MULTICA_ISSUE_ID"
elif [[ -f "${MULTICA_WORKDIR}/.multica/current_issue" ]]; then
  issue_id=$(cat "${MULTICA_WORKDIR}/.multica/current_issue")
fi

if [[ -z "$issue_id" ]]; then
  exit 0
fi

ISSUE_STATE_DIR="${STATE_ROOT}/${issue_id}"
LOOP_JSON="${ISSUE_STATE_DIR}/loop.json"

if [[ ! -f "$LOOP_JSON" ]]; then
  exit 0
fi

active=$(json_field "$LOOP_JSON" "active")
iteration=$(json_field "$LOOP_JSON" "iteration")
phase=$(json_field "$LOOP_JSON" "phase")
max_iterations=$(json_field "$LOOP_JSON" "max_iterations")

if [[ "$active" != "true" ]]; then
  exit 0
fi

done_signal=false

if [[ -n "${CLAUDE_TOOL_OUTPUT:-}" ]]; then
  if printf '%s' "$CLAUDE_TOOL_OUTPUT" | grep -qF '<promise>DONE</promise>'; then
    done_signal=true
  fi
fi

if [[ "$done_signal" == "false" && -n "${MULTICA_OUTPUT_FILE:-}" && -f "${MULTICA_OUTPUT_FILE}" ]]; then
  if grep -qF '<promise>DONE</promise>' "$MULTICA_OUTPUT_FILE"; then
    done_signal=true
  fi
fi

if [[ "$done_signal" == "false" ]]; then
  if [[ -n "$(find "$LOOP_JSON" -mmin -1 2>/dev/null)" ]]; then
    exit 2
  fi
fi

squad_leader_audit() {
  local _squad_marker="## Squad Operating Protocol"
  local _claude_md="${MULTICA_WORKDIR}/CLAUDE.md"
  if [[ -f "$_claude_md" ]] && grep -qF "$_squad_marker" "$_claude_md"; then
    if [[ -n "${MULTICA_ISSUE_ID:-}" ]]; then
      local _marker_file="${MULTICA_WORKDIR}/.multica/state/${MULTICA_ISSUE_ID}/squad-activity.marker"
      local _warn_file="${MULTICA_WORKDIR}/.multica/state/squad-audit-warning"
      if [[ ! -f "$_marker_file" ]]; then
        if command -v multica >/dev/null 2>&1; then
          multica squad activity "$MULTICA_ISSUE_ID" failed \
            --reason "activity-not-recorded-by-agent" 2>/dev/null || log_error "failed to call squad activity"
        fi
        mkdir -p "${MULTICA_WORKDIR}/.multica/state"
        echo "Squad activity not recorded for issue ${MULTICA_ISSUE_ID} at $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$_warn_file"
      fi
      rm -f "$_marker_file"
    fi
  fi
}

if [[ "$done_signal" == "true" ]]; then
  # Cross-check: if loop.json exists, verify no stories are still pending
  if [[ -f "$LOOP_JSON" ]]; then
    if grep -qF '"passes": false' "$LOOP_JSON" 2>/dev/null; then
      done_signal=false
    fi
  fi
fi

if [[ "$done_signal" == "true" ]]; then
  # Count committed learnings if possible
  _learnings_count=0
  _new_learning_keys=""
  _learnings="${MULTICA_WORKDIR}/.multica/learnings.jsonl"
  if [[ -f "$_learnings" ]]; then
    _learnings_count=$(wc -l < "$_learnings" 2>/dev/null || echo 0)

    # Stage learnings now so we can inspect new keys before committing
    if git -C "$MULTICA_WORKDIR" rev-parse --git-dir >/dev/null 2>&1; then
      git -C "$MULTICA_WORKDIR" add "$_learnings" 2>/dev/null || true
      if ! git -C "$MULTICA_WORKDIR" diff --cached --quiet -- "$_learnings" 2>/dev/null; then
        _new_learning_keys=$(git -C "$MULTICA_WORKDIR" diff --cached -- "$_learnings" 2>/dev/null \
          | grep '^+' | grep -v '^+++' \
          | awk -F'"' '/"key"/{print $4}' \
          | tr '\n' ',' | sed 's/,$//')
      fi
    fi
  fi

  _loop_complete_msg="[loop-complete] Done at iteration ${iteration}. Knowledge: ${_learnings_count} learnings on record."
  if [[ -n "$_new_learning_keys" ]]; then
    _loop_complete_msg="${_loop_complete_msg}
New this run: ${_new_learning_keys}
(Review or correct via: multica issue metadata list ${issue_id})"
  fi

  multica issue comment add "$issue_id" \
    --content "$_loop_complete_msg" \
    2>/dev/null || log_error "failed to post loop-complete comment"

  updated_json=$(cat "$LOOP_JSON" \
    | sed 's/"active":[[:space:]]*true/"active": false/' \
    | sed "s/\"phase\":[[:space:]]*\"[^\"]*\"/\"phase\": \"complete\"/")
  atomic_write "$LOOP_JSON" "$updated_json"

  if [[ -f "$_learnings" ]]; then
    if git -C "$MULTICA_WORKDIR" rev-parse --git-dir >/dev/null 2>&1; then
      if ! git -C "$MULTICA_WORKDIR" diff --cached --quiet 2>/dev/null; then
        git -C "$MULTICA_WORKDIR" commit -m "chore(knowledge): update learnings [skip ci]" \
          2>/dev/null || log_error "failed to git commit learnings"
      fi
    fi
  fi

  _notepad="${MULTICA_WORKDIR}/.multica/notepad.md"
  if [[ -f "$_notepad" ]]; then
    _cutoff=$(date -d '7 days ago' +%Y-%m-%dT 2>/dev/null || \
              date -v-7d +%Y-%m-%dT 2>/dev/null || echo "")
    if [[ -n "$_cutoff" ]]; then
      _tmp=$(mktemp "${_notepad}.XXXXXX")
      awk -v cutoff="$_cutoff" '
        /^## Working Memory/ { in_wm=1 }
        /^## / && !/^## Working Memory/ { in_wm=0 }
        in_wm && /^\[20[0-9][0-9]-/ {
          ts=substr($0, 2, 19)
          if (ts < cutoff) next
        }
        { print }
      ' "$_notepad" > "$_tmp" && mv "$_tmp" "$_notepad" || rm -f "$_tmp"
    fi
  fi

  squad_leader_audit

  if [[ -n "${MULTICA_ISSUE_ID:-}" ]]; then
    _prompt_file="${MULTICA_WORKDIR}/.multica/state/consolidation-prompt.txt"
    mkdir -p "$(dirname "$_prompt_file")"
    cat > "$_prompt_file" << 'PROMPT_EOF'
You are a knowledge curator. Your task:

1. Read recent comments on issue ${MULTICA_ISSUE_ID} via:
   multica issue comment list ${MULTICA_ISSUE_ID} --recent 5 --output json

2. Extract HIGH-VALUE learnings (only confidence >= 7):
   - Constraints discovered (e.g. "tests require --single-thread flag")
   - Patterns that work well
   - Pitfalls to avoid
   - Skip: obvious facts, temporary workarounds, issue-specific details

3. Append each learning to .multica/learnings.jsonl (one JSON per line):
   {"ts":"<ISO8601>","skill":"<skill-id>","type":"<pattern|fix|constraint|observation>","key":"<short-unique-key>","insight":"<text>","confidence":<7-10>,"source":"<issue-id>","branch":"<git-branch-or-empty>","commit":"<sha-or-empty>","files":["<path>"]}

4. If no valuable learnings found, do nothing (do not write empty entries).
PROMPT_EOF
    python3 -c "
import sys
content = open(sys.argv[1]).read()
content = content.replace('\${MULTICA_ISSUE_ID}', sys.argv[2])
open(sys.argv[1], 'w').write(content)
" "$_prompt_file" "${MULTICA_ISSUE_ID}" 2>/dev/null || true
  fi

  exit 0
fi

hash=$(dedup_hash "$issue_id" "$iteration" "$phase")

existing=$(multica issue comment list "$issue_id" 2>/dev/null \
  | grep -F "[checkpoint:${hash}]" || true)

if [[ -z "$existing" ]]; then
  multica issue comment add "$issue_id" \
    --content "[checkpoint:${hash}] Loop active at iteration ${iteration}, phase=${phase}. Continuing." \
    2>/dev/null || log_error "failed to post loop-complete comment"
fi

squad_leader_audit

exit 2
