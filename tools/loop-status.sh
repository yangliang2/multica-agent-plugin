#!/usr/bin/env bash
set -euo pipefail

MULTICA_WORKDIR="${MULTICA_WORKDIR:-$(pwd)}"
ISSUE_ID="${MULTICA_ISSUE_ID:-}"

# If no issue ID, list available
if [[ -z "$ISSUE_ID" ]]; then
  STATE_DIR="${MULTICA_WORKDIR}/.multica/state"
  if [[ ! -d "$STATE_DIR" ]]; then
    echo "No .multica/state directory found at ${MULTICA_WORKDIR}"
    echo "Usage: MULTICA_ISSUE_ID=<id> MULTICA_WORKDIR=<path> bash tools/loop-status.sh"
    exit 0
  fi
  echo "Available issues with state:"
  for d in "$STATE_DIR"/*/; do
    issue=$(basename "$d")
    loop_json="${d}loop.json"
    if [[ -f "$loop_json" ]]; then
      active=$(awk -F'"' '/"active"/{print $4}' "$loop_json" | head -1)
      phase=$(awk -F'"' '/"phase"/{print $4}' "$loop_json" | head -1)
      iter=$(awk -F'"' '/"iteration"/{gsub(/[^0-9]/,"",$3);print $3}' "$loop_json" | head -1)
      echo "  ${issue}: phase=${phase} iteration=${iter} active=${active}"
    fi
  done
  echo ""
  echo "Usage: MULTICA_ISSUE_ID=<id> bash tools/loop-status.sh"
  exit 0
fi

LOOP_JSON="${MULTICA_WORKDIR}/.multica/state/${ISSUE_ID}/loop.json"

if [[ ! -f "$LOOP_JSON" ]]; then
  echo "No active loop for issue: ${ISSUE_ID}"
  exit 0
fi

# Parse with python3 for reliable JSON handling
python3 - "$LOOP_JSON" "$ISSUE_ID" \
  "${MULTICA_WORKDIR}/.multica/state/${ISSUE_ID}/hitl-bounces.json" << 'PYEOF'
import json, sys
from datetime import datetime, timezone
from pathlib import Path

loop_file = sys.argv[1]
issue_id  = sys.argv[2]
bounces_file = sys.argv[3]

data = json.loads(Path(loop_file).read_text())

active        = data.get('active', False)
iteration     = data.get('iteration', 0)
max_iter      = data.get('max_iterations', 50)
phase         = data.get('phase', 'unknown')
mode          = data.get('mode', 'execution')
spec_version  = data.get('spec_version', 0)
stories       = data.get('stories', [])
started_at    = data.get('started_at', '')
last_ckpt     = data.get('last_checkpoint_at', '')

# progress block — prefer explicit progress.pct when set, else derive from stories
progress      = data.get('progress', {})
prog_summary  = progress.get('summary', '')
prog_pct_raw  = progress.get('pct', None)
prog_steps    = progress.get('completed_steps', [])
prog_current  = progress.get('current_step', '')

done    = sum(1 for s in stories if s.get('passes'))
total   = len(stories)
story_pct = int(done / total * 100) if total else 0
# Use explicit progress.pct if non-zero, otherwise fall back to story-derived pct
pct     = int(prog_pct_raw) if prog_pct_raw else story_pct
bar_len = 20
filled  = int(bar_len * pct / 100) if pct else 0
bar     = '█' * filled + '░' * (bar_len - filled)

print(f"Issue:        {issue_id}")
print(f"Status:       {'active' if active else 'inactive'}")
print(f"Mode:         {mode}")
print(f"Spec version: {spec_version}")
print(f"Phase:        {phase}")
print(f"Iteration:    {iteration}/{max_iter}")
print(f"Progress:     [{bar}] {pct}%  ({done}/{total} stories)")
if prog_summary:
    print(f"  Summary:    {prog_summary}")
if prog_current:
    print(f"  Current:    {prog_current}")
if prog_steps:
    print(f"  Completed:  {', '.join(str(s) for s in prog_steps)}")
print()

for s in stories:
    mark = '✓' if s.get('passes') else '○'
    title = s.get('title', s.get('id', '?'))
    print(f"  {mark} {title}")

print()

# HITL status
hitl_pending = []
if Path(bounces_file).exists():
    bounces = json.loads(Path(bounces_file).read_text())
    for qid, v in bounces.items():
        ts = v.get('last_at', '')
        if ts:
            dt = datetime.fromisoformat(ts.replace('Z', '+00:00'))
            hours = (datetime.now(timezone.utc) - dt).total_seconds() / 3600
            hitl_pending.append(f"{qid} ({hours:.1f}h ago, tier={v.get('tier','?')})")

if hitl_pending:
    print(f"HITL:       {len(hitl_pending)} pending")
    for h in hitl_pending:
        print(f"  • {h}")
else:
    print("HITL:       none pending")

if last_ckpt:
    print(f"Last ckpt:  {last_ckpt}")
PYEOF
