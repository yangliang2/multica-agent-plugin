#!/usr/bin/env bash
set -euo pipefail

# learning-review.sh — display the project's accumulated learnings for reviewers
# Usage: MULTICA_WORKDIR=/path/to/project bash tools/learning-review.sh

MULTICA_WORKDIR="${MULTICA_WORKDIR:-$(pwd)}"
LEARNINGS="${MULTICA_WORKDIR}/.multica/learnings.jsonl"

if [[ ! -f "$LEARNINGS" ]]; then
  echo "No learnings found at ${LEARNINGS}"
  echo "Run at least one completed Multica task to generate learnings."
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 required for learning-review.sh"
  exit 1
fi

python3 - "$LEARNINGS" "$MULTICA_WORKDIR" <<'PYEOF'
import json, sys
from pathlib import Path
from datetime import datetime, timezone

learnings_file = sys.argv[1]
workdir = sys.argv[2]

entries = {}
with open(learnings_file) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            e = json.loads(line)
        except Exception:
            continue
        key = e.get("key", "")
        if key:
            entries[key] = e  # last-wins dedup

def check_stale(e):
    files = e.get("files", [])
    ts = e.get("ts", "")
    if not files or not ts:
        return False
    try:
        entry_time = datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
        for f in files:
            fp = Path(f) if Path(f).is_absolute() else Path(workdir) / f
            if not fp.exists():
                return True
            if fp.stat().st_mtime > entry_time:
                return True
    except Exception:
        pass
    return False

active = []
stale = []
archived = []

for key, e in entries.items():
    conf = e.get("confidence", 0)
    if conf < 3:
        archived.append(e)
    elif check_stale(e):
        stale.append(e)
    else:
        active.append(e)

active.sort(key=lambda x: x.get("confidence", 0), reverse=True)
stale.sort(key=lambda x: x.get("confidence", 0), reverse=True)

total = len(entries)
print(f"Active learnings ({len(active)} of {total} total):")
if active:
    for e in active:
        conf = e.get("confidence", 0)
        key = e.get("key", "?")
        insight = e.get("insight", "")
        ltype = e.get("type", "")
        print(f"  conf:{conf:<2}  {key:<25} \"{insight}\" [{ltype}]")
else:
    print("  (none)")

if stale:
    print()
    print(f"Possibly stale (source files changed):")
    for e in stale:
        conf = e.get("confidence", 0)
        key = e.get("key", "?")
        insight = e.get("insight", "")
        ltype = e.get("type", "")
        files = e.get("files", [])
        changed = next((Path(f).name for f in files
                        if (Path(f) if Path(f).is_absolute() else Path(workdir)/f).exists()
                        and (Path(f) if Path(f).is_absolute() else Path(workdir)/f).stat().st_mtime >
                        datetime.fromisoformat(e.get("ts","1970-01-01").replace("Z","+00:00")).timestamp()
                        ), "?")
        print(f"  conf:{conf:<2}  {key:<25} \"{insight}\" [{ltype}]  ← {changed} modified")

if archived:
    print()
    print(f"Archived (low confidence, {len(archived)} entries) — not injected into agent context")

PYEOF
