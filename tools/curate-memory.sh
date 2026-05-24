#!/usr/bin/env bash
set -euo pipefail

MULTICA_WORKDIR="${MULTICA_WORKDIR:-$(pwd)}"
LEARNINGS="${MULTICA_WORKDIR}/.multica/learnings.jsonl"
ARCHIVE="${MULTICA_WORKDIR}/.multica/learnings-archive.jsonl"
NOW_EPOCH=$(date +%s)

[[ -f "$LEARNINGS" ]] || exit 0

python3 - "$LEARNINGS" "$ARCHIVE" "$NOW_EPOCH" << 'PYEOF'
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path


def curate(learnings_path, archive_path, now_epoch):
    text = Path(learnings_path).read_text()
    lines = text.strip().splitlines() if text.strip() else []

    entries = []
    for line in lines:
        line = line.strip()
        if line:
            try:
                entries.append(json.loads(line))
            except json.JSONDecodeError:
                pass

    seen = {}
    keyless = []
    for e in entries:
        key = e.get("key", "")
        if key:
            seen[key] = e
        else:
            keyless.append(e)

    deduped = list(seen.values()) + keyless

    active = []
    to_archive = []
    for e in deduped:
        ts = e.get("ts", "")
        age_days = 0
        if ts:
            try:
                dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
                age_days = (now_epoch - dt.timestamp()) / 86400
            except (ValueError, OSError):
                age_days = 0

        conf = int(e.get("confidence", 5))
        if age_days > 180:
            conf -= 4
        elif age_days > 90:
            conf -= 2

        e["confidence"] = max(0, conf)

        if e["confidence"] < 3:
            to_archive.append(e)
        else:
            active.append(e)

    if to_archive:
        with open(archive_path, "a", encoding="utf-8") as f:
            for e in to_archive:
                f.write(json.dumps(e) + "\n")

    tmp = learnings_path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        for e in active:
            f.write(json.dumps(e) + "\n")
    os.replace(tmp, learnings_path)

    print(
        f"Curated: {len(deduped)} unique, {len(active)} active, {len(to_archive)} archived"
    )


if __name__ == "__main__":
    learnings_path = sys.argv[1]
    archive_path = sys.argv[2]
    now_epoch = float(sys.argv[3])
    curate(learnings_path, archive_path, now_epoch)
PYEOF
