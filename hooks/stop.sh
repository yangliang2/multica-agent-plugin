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
  python3 -c "
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    v = d.get(sys.argv[2])
    if v is not None:
        print(str(v).lower() if isinstance(v, bool) else v)
except Exception:
    pass
" "$file" "$field" 2>/dev/null
}

dedup_hash() {
  local issue_id="$1"
  local iteration="$2"
  local phase="$3"
  printf '%s' "${issue_id}${iteration}${phase}" \
    | sha256sum \
    | cut -c1-8
}

prune_notepad() {
  local _notepad="${MULTICA_WORKDIR}/.multica/notepad.md"
  [[ -f "$_notepad" ]] || return 0
  local _cutoff
  _cutoff=$(date -d '7 days ago' +%Y-%m-%dT 2>/dev/null || \
            date -v-7d +%Y-%m-%dT 2>/dev/null || echo "")
  [[ -n "$_cutoff" ]] || return 0
  local _tmp
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

# C1: read stdin if available (Claude Code Stop hook contract: data via stdin JSON,
#     not environment variables). Guard with [[ ! -t 0 ]] so tests without piped
#     stdin don't block. Extract transcript_path for DONE detection.
_hook_stdin=""
if [[ ! -t 0 ]]; then
  _hook_stdin=$(cat 2>/dev/null || true)
fi
_transcript_path=$(printf '%s' "$_hook_stdin" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('transcript_path', ''))
except Exception:
    pass
" 2>/dev/null || echo "")

# Schema validation: reject malformed loop.json before acting on it
_schema_ok=$(python3 -c "
import json, sys, re
ID_RE = re.compile(r'^[A-Za-z0-9._-]{1,64}$')
PHASE_OK = {'setup','execution','execute','deslop','complete','blocked','verification','report',
            'spec','plan','demo','verify','result','done'}
try:
    d = json.load(open(sys.argv[1]))
    iid = d.get('issue_id', '')
    if iid and not ID_RE.match(iid):
        print('bad_issue_id'); sys.exit(0)
    it = d.get('iteration', 0)
    if not isinstance(it, (int, float)) or not (0 <= int(it) <= 1000):
        print('bad_iteration'); sys.exit(0)
    mi = d.get('max_iterations', 50)
    if not isinstance(mi, (int, float)) or not (1 <= int(mi) <= 1000):
        print('bad_max_iterations'); sys.exit(0)
    ph = d.get('phase', '')
    if ph and ph not in PHASE_OK:
        print('bad_phase'); sys.exit(0)
    for s in d.get('stories', []):
        sid = s.get('id', '')
        if sid and not ID_RE.match(sid):
            print('bad_story_id'); sys.exit(0)
    # v2.3.0 optional fields: mode, spec_version, verification_cmd, progress, exit2_triggers_per_session
    mode = d.get('mode', 'execution')
    if not isinstance(mode, str) or len(mode) > 64:
        print('bad_mode'); sys.exit(0)
    sv = d.get('spec_version', 0)
    if not isinstance(sv, (int, float)) or int(sv) < 0:
        print('bad_spec_version'); sys.exit(0)
    vc = d.get('verification_cmd', '')
    if not isinstance(vc, str) or len(vc) > 512:
        print('bad_verification_cmd'); sys.exit(0)
    prog = d.get('progress', {})
    if not isinstance(prog, dict):
        print('bad_progress'); sys.exit(0)
    e2t = d.get('exit2_triggers_per_session', 0)
    if not isinstance(e2t, (int, float)) or int(e2t) < 0:
        print('bad_exit2_triggers'); sys.exit(0)
    # v2.3.0 HITL tracking (REQ-06-01/02): arrays of dicts if present
    for hf in ('open_hitls', 'resolved_hitls'):
        hv = d.get(hf, [])
        if not isinstance(hv, list) or any(not isinstance(x, dict) for x in hv):
            print(f'bad_{hf}'); sys.exit(0)
    # v2.3.0 squad coordination (REQ-04-03/04)
    ci = d.get('child_issues', [])
    if not isinstance(ci, list) or any(not isinstance(x, str) for x in ci):
        print('bad_child_issues'); sys.exit(0)
    st = d.get('squad_stuck_threshold_minutes', 120)
    if not isinstance(st, (int, float)) or not (1 <= int(st) <= 100000):
        print('bad_squad_stuck_threshold'); sys.exit(0)
    print('ok')
except Exception as e:
    print(f'parse_error')
" "$LOOP_JSON" 2>/dev/null || echo "python_error")

if [[ "$_schema_ok" != "ok" ]]; then
  log_error "loop.json schema validation failed (${_schema_ok}): ${LOOP_JSON}"
  exit 0
fi

active=$(json_field "$LOOP_JSON" "active")
iteration=$(json_field "$LOOP_JSON" "iteration")
phase=$(json_field "$LOOP_JSON" "phase")

if [[ "$active" != "true" ]]; then
  exit 0
fi

# H7: per-issue advisory flock to prevent concurrent stop-hook races on shared state files
_LOCK_FILE="${ISSUE_STATE_DIR}/.multica.lock"
mkdir -p "$ISSUE_STATE_DIR" 2>/dev/null || true
if command -v flock >/dev/null 2>&1; then
  exec 9>"$_LOCK_FILE"
  flock -x 9
fi

done_signal=false

# 1. Check stdin content (Claude Code Stop hook contract: agent output in stdin JSON)
if [[ -n "$_hook_stdin" ]]; then
  if printf '%s' "$_hook_stdin" | grep -qE '<promise>DONE(:[A-Za-z0-9]+)?</promise>' 2>/dev/null; then
    done_signal=true
  fi
fi

# 2. Check transcript file (pointed to by transcript_path in stdin JSON)
if [[ "$done_signal" == "false" && -n "$_transcript_path" && -f "$_transcript_path" ]]; then
  if tail -20 "$_transcript_path" | grep -qE '<promise>DONE(:[A-Za-z0-9]+)?</promise>' 2>/dev/null; then
    done_signal=true
  fi
fi

# 3. Daemon override: MULTICA_OUTPUT_FILE (explicit output file written by daemon)
if [[ "$done_signal" == "false" && -n "${MULTICA_OUTPUT_FILE:-}" && -f "${MULTICA_OUTPUT_FILE}" ]]; then
  if grep -qE '<promise>DONE(:[A-Za-z0-9]+)?</promise>' "$MULTICA_OUTPUT_FILE"; then
    done_signal=true
  fi
fi

# H4: nonce verification — if done-nonce.txt exists, require DONE:<nonce> in signal
if [[ "$done_signal" == "true" ]]; then
  _nonce_file="${ISSUE_STATE_DIR}/done-nonce.txt"
  if [[ -f "$_nonce_file" ]]; then
    _expected_nonce=$(cat "$_nonce_file")
    _nonce_found=false
    if [[ -n "$_hook_stdin" ]]; then
      printf '%s' "$_hook_stdin" | grep -qF "<promise>DONE:${_expected_nonce}</promise>" && _nonce_found=true
    fi
    if [[ "$_nonce_found" == "false" && -n "$_transcript_path" && -f "$_transcript_path" ]]; then
      tail -20 "$_transcript_path" | grep -qF "<promise>DONE:${_expected_nonce}</promise>" && _nonce_found=true
    fi
    if [[ "$_nonce_found" == "false" && -n "${MULTICA_OUTPUT_FILE:-}" && -f "${MULTICA_OUTPUT_FILE}" ]]; then
      grep -qF "<promise>DONE:${_expected_nonce}</promise>" "$MULTICA_OUTPUT_FILE" && _nonce_found=true
    fi
    if [[ "$_nonce_found" == "false" ]]; then
      log_error "DONE rejected: nonce mismatch (expected DONE:${_expected_nonce})"
      echo "[stop.sh] DONE rejected — wrong nonce (emit <promise>DONE:${_expected_nonce}</promise>)" >&2
      done_signal=false
    fi
  fi
fi

if [[ "$done_signal" == "false" ]]; then
  # v2.3.0: suppress exit-2 only for phases that use the exit-0 checkpoint model.
  # spec/demo/plan/verify/result/done exit cleanly; execute + all legacy phases (empty,
  # "execution", "setup", etc.) retain exit-2 re-entry behavior for backward compat.
  _exit2_suppressed=false
  case "$phase" in spec|demo|plan|verify|result|done) _exit2_suppressed=true ;; esac
  if [[ "$_exit2_suppressed" == "false" ]] && [[ -n "$(find "$LOOP_JSON" -mmin -1 2>/dev/null)" ]]; then
    echo "[stop.sh] loop active, no DONE signal — blocking session stop" >&2
    # M7: write stdout JSON so Claude Code can relay the block reason to the model
    python3 -c "
import json, sys
print(json.dumps({'hookSpecificOutput': {'additionalContext': sys.argv[1]}}))
" "[multica] Loop still active — emit <promise>DONE</promise> (with nonce if required) to complete the session." 2>/dev/null || true
    # v2.3.0: increment exit2_triggers_per_session counter in loop.json on each re-enter
    if command -v python3 >/dev/null 2>&1 && [[ -f "$LOOP_JSON" ]]; then
      python3 -c "
import json, sys, os
from pathlib import Path
p = Path(sys.argv[1])
try:
    d = json.load(p.open())
    d['exit2_triggers_per_session'] = int(d.get('exit2_triggers_per_session', 0)) + 1
    tmp = str(p) + '.tmp'
    with open(tmp, 'w') as f:
        json.dump(d, f, indent=2)
        f.write('\n')
    os.replace(tmp, str(p))
except Exception:
    sys.exit(0)
" "$LOOP_JSON" 2>/dev/null || true
    fi
    exit 2
  fi
fi

# REQ-04-04: leader children checkpoint. Reads each child issue's status and
# latest comment timestamps; stuck detection compares ONLY server-side
# created_at timestamps against each other (newest seen = reference clock) —
# never the local clock, avoiding clock-skew false positives across machines.
squad_children_checkpoint() {
  command -v multica >/dev/null 2>&1 || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  [[ -f "$LOOP_JSON" ]] || return 0
  local _children
  _children=$(python3 -c "
import json, sys, re
ID_RE = re.compile(r'^[A-Za-z0-9._-]{1,64}\$')
try:
    v = json.load(open(sys.argv[1])).get('child_issues', [])
    if isinstance(v, list):
        print(' '.join(c for c in v if isinstance(c, str) and ID_RE.match(c)))
except Exception:
    pass
" "$LOOP_JSON" 2>/dev/null || true)
  [[ -n "$_children" ]] || return 0

  local _ck_dir
  _ck_dir=$(mktemp -d)
  local _child
  for _child in $_children; do
    multica issue get "$_child" --output json \
      > "${_ck_dir}/${_child}.issue.json" 2>/dev/null || continue
    multica issue comment list "$_child" --recent 5 --output json \
      > "${_ck_dir}/${_child}.comments.json" 2>/dev/null || true
    printf '%s\n' "$_child" >> "${_ck_dir}/manifest.txt"
  done
  if [[ ! -f "${_ck_dir}/manifest.txt" ]]; then
    rm -rf "$_ck_dir"
    return 0
  fi

  local _verdict
  _verdict=$(python3 - "$_ck_dir" "$LOOP_JSON" <<'CHILDREN_PY' || true
import json, sys, os
from datetime import datetime

ck_dir, loop_json = sys.argv[1], sys.argv[2]

def parse_ts(s):
    try:
        return datetime.fromisoformat(str(s).replace('Z', '+00:00'))
    except Exception:
        return None

threshold_min = 120
try:
    t = json.load(open(loop_json)).get('squad_stuck_threshold_minutes', 120)
    if isinstance(t, (int, float)) and 1 <= int(t) <= 100000:
        threshold_min = int(t)
except Exception:
    pass

with open(os.path.join(ck_dir, 'manifest.txt')) as f:
    children = [l.strip() for l in f if l.strip()]

statuses, last_ts, all_ts = {}, {}, []
for c in children:
    try:
        statuses[c] = str(json.load(open(os.path.join(ck_dir, f'{c}.issue.json'))).get('status', ''))
    except Exception:
        statuses[c] = ''
    try:
        raw = json.load(open(os.path.join(ck_dir, f'{c}.comments.json')))
    except Exception:
        raw = []
    if isinstance(raw, dict):
        raw = raw.get('comments') or raw.get('threads') or raw.get('items') or []
    ts_list = [t for t in (parse_ts(cm.get('created_at', ''))
               for cm in raw if isinstance(cm, dict)) if t]
    if ts_list:
        last_ts[c] = max(ts_list)
        all_ts.extend(ts_list)

if children and all(statuses.get(c) == 'done' for c in children):
    print('ALL_DONE')
    raise SystemExit

if not all_ts:
    raise SystemExit  # no server timestamps — cannot judge stuckness
ref = max(all_ts)  # newest server timestamp = reference clock
stuck = []
for c in children:
    if statuses.get(c) == 'done':
        continue
    lt = last_ts.get(c)
    if lt is not None and (ref - lt).total_seconds() / 60.0 > threshold_min:
        stuck.append(c)
if stuck:
    print('STUCK:' + ','.join(stuck))
CHILDREN_PY
)
  rm -rf "$_ck_dir"

  case "$_verdict" in
    ALL_DONE)
      python3 -c "
import json, sys, os
p = sys.argv[1]
try:
    d = json.load(open(p))
    d['phase'] = 'result'
    tmp = p + '.tmp'
    with open(tmp, 'w') as f:
        json.dump(d, f, indent=2)
        f.write('\n')
    os.replace(tmp, p)
except Exception:
    sys.exit(0)
" "$LOOP_JSON" 2>/dev/null || true
      multica issue comment add "$issue_id" \
        --content "[phase] execute→result All child issues done; advancing to result phase." \
        2>/dev/null || log_error "failed to post all-children-done phase comment"
      ;;
    STUCK:*)
      local _stuck="${_verdict#STUCK:}"
      # rate limit: at most one squad-stuck checkpoint per hour
      local _stuck_marker
      _stuck_marker="${ISSUE_STATE_DIR}/squad-stuck-$(date -u +%Y%m%d%H).marker"
      if [[ ! -f "$_stuck_marker" ]]; then
        multica issue comment add "$issue_id" \
          --content "[checkpoint] squad-stuck | no recent activity (>threshold) from: ${_stuck}. Check member issues or reassign." \
          2>/dev/null && touch "$_stuck_marker" \
          || log_error "failed to post squad-stuck checkpoint"
      fi
      ;;
  esac
}

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
    # REQ-04-04: leader-only child progress checkpoint
    squad_children_checkpoint || true
  fi
}

# REQ-05-01: capture user correction signals ([wrong: ...] / [revise: ...]) from
# recent issue comments as high-confidence repo-scoped learnings, without the
# agent generating them. Dedup key = first 16 hex chars of sha256(insight[:200]).
# A re-seen key is reinforced: confidence reset to 9, recorded_at refreshed
# (REQ-05-04 recurrence reinforcement).
capture_correction_learnings() {
  command -v multica >/dev/null 2>&1 || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  local _cl_file="${MULTICA_WORKDIR}/.multica/learnings.jsonl"
  local _cl_comments_tmp
  _cl_comments_tmp=$(mktemp)
  if ! multica issue comment list "$issue_id" --recent 20 --output json \
      > "$_cl_comments_tmp" 2>/dev/null; then
    rm -f "$_cl_comments_tmp"
    return 0
  fi
  local _cl_repo
  _cl_repo=$(git -C "$MULTICA_WORKDIR" remote get-url origin 2>/dev/null || true)
  mkdir -p "$(dirname "$_cl_file")"
  python3 - "$_cl_comments_tmp" "$_cl_file" "$LOOP_JSON" "$_cl_repo" "$issue_id" <<'CAPTURE_PY' \
    || log_error "correction-signal capture failed (non-blocking)"
import json, sys, os, re, hashlib, fcntl
from datetime import datetime, timedelta, timezone

comments_file, learnings_file, loop_json, repo_url, issue_id = sys.argv[1:6]

SIGNAL_RE = re.compile(r'^\[(wrong|revise):\s*(.*)\]\s*$')

def parse_ts(s):
    try:
        return datetime.fromisoformat(s.replace('Z', '+00:00'))
    except Exception:
        return None

# 7-day window anchored to loop.json.start_time (REQ-05-01); fallback: now.
anchor = None
try:
    anchor = parse_ts(json.load(open(loop_json)).get('start_time', ''))
except Exception:
    pass
if anchor is None:
    anchor = datetime.now(timezone.utc)
window_start = anchor - timedelta(days=7)

try:
    raw = json.load(open(comments_file))
except Exception:
    sys.exit(0)
if isinstance(raw, dict):
    raw = raw.get('comments') or raw.get('threads') or raw.get('items') or []
if not isinstance(raw, list):
    sys.exit(0)

signals = []
for c in raw:
    if not isinstance(c, dict):
        continue
    author = c.get('author') or {}
    if author.get('type') == 'agent':
        continue  # only human-authored corrections become learnings
    ts = parse_ts(c.get('created_at', '') or '')
    if ts is None or ts < window_start:
        continue
    for line in str(c.get('content', '')).splitlines():
        m = SIGNAL_RE.match(line.strip())
        if m:
            insight = ' '.join(m.group(2).split())[:500]
            if insight:
                signals.append((ts, m.group(1), insight))

if not signals:
    sys.exit(0)
signals.sort(key=lambda s: s[0])
signals = signals[-10:]

now_iso = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
lock_path = learnings_file + '.lock'
with open(lock_path, 'w') as lk:
    fcntl.flock(lk, fcntl.LOCK_EX)
    entries = []
    if os.path.exists(learnings_file):
        with open(learnings_file) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    entries.append(json.loads(line))
                except Exception:
                    continue
    by_key = {e.get('key'): e for e in entries if e.get('key')}
    changed = False
    for ts, sig_type, insight in signals:
        key = hashlib.sha256(insight[:200].encode('utf-8')).hexdigest()[:16]
        if key in by_key:
            e = by_key[key]
            e['confidence'] = 9
            e['recorded_at'] = now_iso
            e['ts'] = now_iso
        else:
            e = {
                'ts': now_iso, 'recorded_at': now_iso,
                'scope': 'repo' if repo_url else 'issue', 'repo': repo_url,
                'skill': 'correction-capture', 'type': 'fix',
                'key': key, 'insight': insight, 'confidence': 9,
                'source': issue_id, 'branch': '', 'commit': '', 'files': [],
            }
            entries.append(e)
            by_key[key] = e
        changed = True
    if changed:
        tmp = learnings_file + '.tmp'
        with open(tmp, 'w') as f:
            for e in entries:
                f.write(json.dumps(e) + '\n')
        os.replace(tmp, learnings_file)
CAPTURE_PY
  rm -f "$_cl_comments_tmp"
}

# v2.3.0 phase dispatch: checkpoint phases (spec, demo) and auto-advance phases (plan, verify)
# skip the stories/evidence gate and go directly to learning routing + exit 0
_v050_phase_exit=false
_v050_skip_gate=false
case "$phase" in
  spec|demo|plan|verify)
    _v050_skip_gate=true
    ;;
esac

if [[ "$_v050_skip_gate" == "true" ]] && [[ "$done_signal" == "true" ]]; then
  # Auto-advance phase: update loop.json.phase to next phase
  _next_phase=""
  case "$phase" in
    plan)   _next_phase="demo" ;;
    verify) _next_phase="result" ;;
    # spec and demo: next phase is set by agent on next session based on user signal
  esac
  if [[ -n "$_next_phase" ]] && command -v python3 >/dev/null 2>&1 && [[ -f "$LOOP_JSON" ]]; then
    python3 -c "
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
try:
    d = json.load(p.open())
    d['phase'] = sys.argv[2]
    tmp = str(p) + '.tmp'
    with open(tmp, 'w') as f:
        json.dump(d, f, indent=2)
        f.write('\n')
    import os; os.replace(tmp, str(p))
except Exception as e:
    sys.exit(0)
" "$LOOP_JSON" "$_next_phase" 2>/dev/null || true
  fi
  # Run learning routing (always beneficial) then exit cleanly
  # Fall through to the learnings block below by jumping past the gate
  done_signal=false  # prevent the evidence gate from firing
  # But mark that we want to run learnings and exit, not loop
  _v050_phase_exit=true
fi

if [[ "$done_signal" == "true" ]]; then
  # Cross-check: if loop.json exists, verify no stories are still pending
  if [[ -f "$LOOP_JSON" ]]; then
    _has_failing=$(python3 -c "
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    stories = d.get('stories', [])
    print('yes' if any(not s.get('passes', False) for s in stories) else 'no')
except Exception:
    print('no')
" "$LOOP_JSON" 2>/dev/null || echo "no")
    if [[ "$_has_failing" == "yes" ]]; then
      done_signal=false
    fi
  fi
fi

if [[ "$done_signal" == "true" ]]; then
  # Evidence gate: every passes=true story must have a non-empty evidence file
  # C7: issue_id and story_id are validated against a strict format and path is
  #     resolved to prevent path traversal. Python exits 1 on any error (fail-closed).
  if [[ -f "$LOOP_JSON" ]]; then
    _missing_evidence=$(python3 -c "
import json, sys, re
from pathlib import Path

ID_RE = re.compile(r'^[A-Za-z0-9._-]{1,64}$')

try:
    d = json.load(open(sys.argv[1]))
    workdir = sys.argv[2]

    issue_id = d.get('issue_id', '')
    if not issue_id or not ID_RE.match(issue_id):
        print('INVALID_ISSUE_ID')
        sys.exit(0)

    state_root = (Path(workdir) / '.multica' / 'state').resolve()
    issue_dir = (state_root / issue_id).resolve()
    # Reject if issue_id escapes state dir
    if state_root not in issue_dir.parents and issue_dir != state_root:
        print('INVALID_ISSUE_ID')
        sys.exit(0)

    stories = d.get('stories', [])
    if not stories:
        print('NO_STORIES')
        sys.exit(0)

    missing = []
    for s in stories:
        if not s.get('passes', False):
            continue
        sid = s.get('id', '')
        if not sid or not ID_RE.match(sid):
            missing.append(sid or 'INVALID_SID')
            continue
        ev = (issue_dir / 'evidence' / f'{sid}.txt').resolve()
        # Reject if sid escapes issue dir
        if issue_dir not in ev.parents:
            missing.append(sid)
            continue
        if not ev.exists() or ev.stat().st_size == 0:
            missing.append(sid)
            continue
        # H3: evidence must prove an actual command ran with a passing exit
        # code. For a story marked passes=true we require:
        #   - a `command:` line (records WHAT was run)
        #   - an `exit_code:` line parseable as an integer, equal to 0
        # A bare prose `summary:` is NOT sufficient — that is self-assessment,
        # not machine-checkable proof. The exit_code==0 cross-check rejects the
        # dishonest case where passes=true but the evidence shows a failure.
        ev_text = ev.read_text(errors='replace')
        has_command = bool(re.search(r'^\s*command:\s*\S', ev_text, re.MULTILINE))
        m_exit = re.search(r'^\s*exit_code:\s*(-?\d+)\s*$', ev_text, re.MULTILINE)
        if not has_command:
            missing.append(f'{sid}(no-command)')
        elif m_exit is None:
            missing.append(f'{sid}(no-exit-code)')
        elif int(m_exit.group(1)) != 0:
            missing.append(f'{sid}(exit-code={m_exit.group(1)})')
    print(','.join(missing))
except Exception as e:
    print(f'ERROR:{e}', file=sys.stderr)
    sys.exit(1)
" "$LOOP_JSON" "$MULTICA_WORKDIR" 2>/dev/null)
    _ev_exit=$?
    # fail-closed: python error → treat as missing evidence
    if [[ $_ev_exit -ne 0 ]] || [[ -n "$_missing_evidence" ]]; then
      echo "[stop.sh] DONE rejected — missing evidence files for stories: ${_missing_evidence:-python-error}" >&2
      done_signal=false
    fi
  fi
fi

if [[ "$done_signal" == "true" ]] || [[ "${_v050_phase_exit:-false}" == "true" ]]; then
  # REQ-05-01: harvest user correction signals first so newly captured learnings
  # are dispatched by the routing pass below in this same session exit
  capture_correction_learnings || true

  # ---------------------------------------------------------------------------
  # Learnings routing: dispatch by scope to correct storage path
  # L1 (workspace) → multica workspace context field
  # L2 (repo)      → {checkout_dir}/.multica/learnings.jsonl (git committed)
  # L3 (issue)     → $MULTICA_WORKDIR/.multica/learnings.jsonl (current behavior)
  # ---------------------------------------------------------------------------
  _learnings="${MULTICA_WORKDIR}/.multica/learnings.jsonl"
  _learnings_count=0
  _new_learning_keys=""

  if [[ -f "$_learnings" ]] && command -v python3 >/dev/null 2>&1; then
    _learnings_count=$(awk 'END{print NR}' "$_learnings" 2>/dev/null || echo 0)

    # Find checked-out repo directories (immediate subdirs with .git or .multica)
    _repo_dirs=()
    while IFS= read -r -d '' _d; do
      _repo_dirs+=("$_d")
    done < <(find "$MULTICA_WORKDIR" -maxdepth 2 -name ".git" -type d -print0 2>/dev/null               | sed -z 's|/.git||')

    # Route learnings by scope.
    # FIX (REQ-05-03): previously SCOPE_PY ran without command substitution so its
    # stdout was discarded, and the parser loop read from a dead SCOPE_PY2 heredoc
    # that emitted nothing.  Collapsed into one invocation via process substitution
    # so the parser loop reads directly from SCOPE_PY's stdout.
    _workspace_learnings=()
    _repo_learnings_dirs=()
    while IFS= read -r _sline; do
      case "$_sline" in
        WORKSPACE_LEARNING:*)
          _workspace_learnings+=("${_sline#WORKSPACE_LEARNING:}")
          ;;
        REPO_LEARNINGS_DIR:*)
          _repo_learnings_dirs+=("${_sline#REPO_LEARNINGS_DIR:}")
          ;;
      esac
    done < <(python3 - "$_learnings" "$MULTICA_WORKDIR" "${_repo_dirs[@]+"${_repo_dirs[@]}"}" <<'SCOPE_PY'
import json, sys, os, re
from pathlib import Path

learnings_file = sys.argv[1]
workdir = sys.argv[2]
repo_dirs = sys.argv[3:]

KEY_RE = re.compile(r'^[A-Za-z0-9._-]{1,64}$')
VALID_SCOPES = {'workspace', 'repo', 'issue'}

workspace_entries = []
repo_entries = {}   # repo_url -> [entries]
issue_entries = []  # default (no scope or scope=issue)

with open(learnings_file) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            e = json.loads(line)
        except Exception:
            continue
        scope = e.get('scope', 'issue')
        if scope not in VALID_SCOPES:
            scope = 'issue'
        if scope == 'workspace':
            workspace_entries.append(e)
        elif scope == 'repo':
            repo = e.get('repo', '')
            if repo:
                repo_entries.setdefault(repo, []).append(e)
        else:
            issue_entries.append(e)

# L1: emit workspace learnings as [learning:*] lines to stdout for bash to capture
for e in workspace_entries:
    key = e.get('key', '')
    insight = e.get('insight', '')
    conf = e.get('confidence', 0)
    if key and insight and KEY_RE.match(key):
        print(f"WORKSPACE_LEARNING:{key}:{conf}:{insight}")

# L2: write repo-scoped learnings to repo checkout dirs
for repo_url, entries in repo_entries.items():
    # Find matching repo dir by checking remote URL
    target_dir = None
    for rd in repo_dirs:
        try:
            import subprocess
            result = subprocess.run(
                ['git', '-C', rd, 'remote', 'get-url', 'origin'],
                capture_output=True, text=True, timeout=5)
            if result.returncode == 0 and result.stdout.strip() == repo_url:
                target_dir = rd
                break
        except Exception:
            continue
    if not target_dir:
        # No matching checkout found — keep in issue-level file
        issue_entries.extend(entries)
        continue
    if os.path.realpath(target_dir) == os.path.realpath(workdir):
        # The workdir itself is the matching checkout: the entries already live
        # in its learnings file. Moving them would append-to-self and then be
        # wiped by the L3 rewrite below. Keep them in place; the L3 git commit
        # already propagates this file through the repo.
        issue_entries.extend(entries)
        continue
    repo_learnings = Path(target_dir) / '.multica' / 'learnings.jsonl'
    repo_learnings.parent.mkdir(parents=True, exist_ok=True)
    with open(repo_learnings, 'a') as f:
        for e in entries:
            f.write(json.dumps(e) + '
')
    print(f"REPO_LEARNINGS_DIR:{target_dir}")

# L3: rewrite issue-scoped learnings back (remove workspace/repo entries)
if len(issue_entries) != sum(1 for _ in open(learnings_file) if _.strip()):
    tmp = learnings_file + '.tmp'
    with open(tmp, 'w') as f:
        for e in issue_entries:
            f.write(json.dumps(e) + '
')
    os.replace(tmp, learnings_file)
    print("REWRITTEN_ISSUE_LEARNINGS")
SCOPE_PY
    )

    # L1: append workspace learnings to multica workspace context
    if [[ ${#_workspace_learnings[@]} -gt 0 ]] && command -v multica >/dev/null 2>&1; then
      _ws_context=$(multica workspace get --output json 2>/dev/null | python3 -c "
import json,sys
try: print(json.load(sys.stdin).get('context',''))
except: print('')
" 2>/dev/null || echo "")
      _new_ws_lines=""
      for _wl in "${_workspace_learnings[@]}"; do
        _wl_key="${_wl%%:*}"
        _wl_rest="${_wl#*:}"
        _wl_conf="${_wl_rest%%:*}"
        _wl_insight="${_wl_rest#*:}"
        if ! echo "$_ws_context" | grep -qF "[learning:${_wl_key}]"; then
          _new_ws_lines="${_new_ws_lines}[learning:${_wl_key}] (conf:${_wl_conf}) ${_wl_insight}"$'
'
        fi
      done
      if [[ -n "$_new_ws_lines" ]]; then
        printf '%s
%s' "$_ws_context" "$_new_ws_lines"           | multica workspace update --context-stdin           2>/dev/null || log_error "failed to update workspace context with learnings"
      fi
    fi

    # L2: git commit repo-level learnings in each repo dir
    for _rdir in "${_repo_learnings_dirs[@]+"${_repo_learnings_dirs[@]}"}"; do
      _rl="${_rdir}/.multica/learnings.jsonl"
      if [[ -f "$_rl" ]] && git -C "$_rdir" rev-parse --git-dir >/dev/null 2>&1; then
        git -C "$_rdir" add "$_rl" 2>/dev/null || true
        if ! git -C "$_rdir" diff --cached --quiet -- "$_rl" 2>/dev/null; then
          git -C "$_rdir" commit -- "$_rl"             -m "chore(knowledge): update repo learnings [skip ci]"             2>/dev/null || log_error "failed to git commit repo learnings in ${_rdir}"
        fi
      fi
    done

    # L3: git commit issue-level learnings (existing behavior)
    if git -C "$MULTICA_WORKDIR" rev-parse --git-dir >/dev/null 2>&1; then
      git -C "$MULTICA_WORKDIR" add "$_learnings" 2>/dev/null || true
      if ! git -C "$MULTICA_WORKDIR" diff --cached --quiet -- "$_learnings" 2>/dev/null; then
        _new_learning_keys=$(git -C "$MULTICA_WORKDIR" diff --cached -- "$_learnings" 2>/dev/null           | grep '^+' | grep -v '^+++'           | python3 -c "
import json, sys
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        e = json.loads(line)
        k = e.get('key','')
        if k: print(k)
    except: pass
" 2>/dev/null | tr '
' ',' | sed 's/,$//')
      fi
    fi
  fi

  # v2.3.0: checkpoint/auto-advance phase — exit cleanly after learnings
  if [[ "${_v050_phase_exit:-false}" == "true" ]]; then
    squad_leader_audit
    exit 0
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

  updated_json=$(python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
d['active'] = False
d['phase'] = 'complete'
print(json.dumps(d))
" "$LOOP_JSON" 2>/dev/null || cat "$LOOP_JSON" \
    | sed 's/"active":[[:space:]]*true/"active": false/' \
    | sed "s/\"phase\":[[:space:]]*\"[^\"]*\"/\"phase\": \"complete\"/")
  atomic_write "$LOOP_JSON" "$updated_json"
  rm -f "${ISSUE_STATE_DIR}/done-nonce.txt"

  if [[ -f "$_learnings" ]]; then
    if git -C "$MULTICA_WORKDIR" rev-parse --git-dir >/dev/null 2>&1; then
      if ! git -C "$MULTICA_WORKDIR" diff --cached --quiet -- "$_learnings" 2>/dev/null; then
        git -C "$MULTICA_WORKDIR" commit -- "$_learnings" \
          -m "chore(knowledge): update learnings [skip ci]" \
          2>/dev/null || log_error "failed to git commit learnings"
      fi
    fi
  fi

  prune_notepad

  # Auto-run curate-memory if available (dedup + decay learnings on DONE)
  _curate="${MULTICA_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/tools/curate-memory.sh"
  if [[ -f "$_curate" ]] && [[ -f "${MULTICA_WORKDIR}/.multica/learnings.jsonl" ]]; then
    MULTICA_WORKDIR="$MULTICA_WORKDIR" bash "$_curate" \
      2>/dev/null || log_error "curate-memory.sh failed (non-blocking)"
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

prune_notepad

squad_leader_audit

# M7: write stdout JSON so Claude Code can relay the block reason to the model.
# Whitelist-validate iteration and phase before use to prevent any injection.
_m7_iter="$iteration"; [[ "$_m7_iter" =~ ^[0-9]{1,4}$ ]] || _m7_iter="?"
_m7_phase="$phase";    [[ "$_m7_phase" =~ ^[a-z]{1,20}$ ]] || _m7_phase="?"
python3 -c "
import json, sys
it, ph = sys.argv[1], sys.argv[2]
msg = f'[multica] Loop active at iteration {it}, phase={ph}. Continuing — emit <promise>DONE</promise> to complete.'
print(json.dumps({'hookSpecificOutput': {'additionalContext': msg}}))
" "$_m7_iter" "$_m7_phase" 2>/dev/null || true

exit 2
