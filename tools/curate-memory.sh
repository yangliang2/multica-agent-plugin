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
from datetime import datetime, timedelta, timezone
from pathlib import Path


def parse_iso(ts):
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except (ValueError, OSError, AttributeError):
        return None


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

    # REQ-05-04: decay -1 per week since recorded_at, floor at 1. The decay is
    # persisted, so last_decayed_at tracks how far decay has already been
    # applied — repeated curate runs must not re-decay the same weeks.
    log_path = str(Path(learnings_path).parent / "curate-memory.log")
    active = []
    to_archive = []
    for e in deduped:
        conf = int(e.get("confidence", 5))

        anchor = parse_iso(
            e.get("last_decayed_at") or e.get("recorded_at") or e.get("ts") or ""
        )
        if anchor is not None:
            weeks = int(max(0.0, now_epoch - anchor.timestamp()) // (7 * 86400))
            if weeks > 0:
                conf = max(1, conf - weeks)
                e["last_decayed_at"] = (anchor + timedelta(weeks=weeks)).strftime(
                    "%Y-%m-%dT%H:%M:%SZ"
                )
        e["confidence"] = conf

        # Prune only when confidence < 4 AND no correction signal (recurrence
        # resets recorded_at to now) has been seen in the last 30 days.
        recorded = parse_iso(e.get("recorded_at") or e.get("ts") or "")
        recorded_age_days = (
            (now_epoch - recorded.timestamp()) / 86400 if recorded is not None else 0
        )
        if conf < 4 and recorded_age_days > 30:
            to_archive.append(e)
        else:
            active.append(e)

    if to_archive:
        with open(archive_path, "a", encoding="utf-8") as f:
            for e in to_archive:
                f.write(json.dumps(e) + "\n")
        # No silent removal: every pruned entry is logged (REQ-05-04)
        with open(log_path, "a", encoding="utf-8") as f:
            for e in to_archive:
                f.write(
                    f"[learning-pruned key={e.get('key', '')} confidence={e['confidence']}]\n"
                )

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
