# Concurrency Model

Multica agents may run concurrently on the same host, each assigned to a different issue.
This document specifies the isolation strategy, locking protocol, retry policy, and atomicity
guarantees that prevent state corruption and deadlocks.

---

## Per-Issue Isolation

All mutable state for a single issue is contained in its own subdirectory:

```
$MULTICA_WORKDIR/.multica/state/<issue_id>/
  loop.json          # persistence loop state
  .lock              # advisory flock file
  last-checkpoint    # ISO8601 timestamp of last successful checkpoint
```

No agent writes outside its own `<issue_id>/` directory during normal execution.
The only exception is `.multica/learnings.jsonl`, which is append-only and requires
no lock (appends are atomic on POSIX filesystems for writes < PIPE_BUF).

---

## Advisory Locking

Before any read-modify-write operation on `loop.json`, the agent acquires an advisory lock:

```bash
flock -n "$MULTICA_WORKDIR/.multica/state/<issue_id>/.lock" <command>
```

The lock is **advisory**: it coordinates well-behaved agents but does not prevent
a crashed process's lock from blocking forward progress indefinitely.

### Stale Lock Recovery

A lock file is considered stale when its `mtime` is older than 15 minutes:

```
mtime < now - 900s  →  stale
```

When a stale lock is detected:
1. Write a `[lock-recovered]` comment via `multica issue comment add`
2. Remove the stale lock file: `rm -f .lock`
3. Re-attempt the flock acquire (counts as the first retry attempt)

---

## Retry Policy

Lock acquisition failures follow exponential backoff:

| Attempt | Wait before retry |
|---------|------------------|
| 1       | 100 ms           |
| 2       | 500 ms           |
| 3       | 2 000 ms (2 s)   |

After 3 failed attempts without acquiring the lock (and the lock is not stale):
1. Write a `[lock-contention]` comment via `multica issue comment add`
2. Set issue status to `blocked`
3. Exit — the daemon reactivates on `on_comment`

Retry counter resets after a successful lock acquisition.

---

## Atomic Write Protocol

All writes to state files MUST be atomic to prevent partial reads by concurrent agents:

```bash
# Canonical pattern — used in all hook scripts
tmp=$(mktemp "${state_file}.XXXXXX")
# ... write complete content to $tmp ...
mv "$tmp" "$state_file"
```

`mv` on the same filesystem is atomic on POSIX. Never write directly to the target path.
Never use `tee`, `>>`, or in-place editors (`sed -i`, `jq` redirect) on state files.

---

## Filesystem Layout Reference

```
$MULTICA_WORKDIR/
└── .multica/
    ├── notepad.md               # Three-section notepad (Priority/Working/Manual)
    ├── learnings.jsonl          # Append-only learning entries
    ├── current_issue            # Plain text: current issue_id (single line)
    └── state/
        └── <issue_id>/
            ├── loop.json        # Persistence loop state
            ├── .lock            # Advisory flock target
            └── last-checkpoint  # ISO8601 of last checkpoint write
```

---

## Concurrency Invariants

1. **No cross-issue state reads.** An agent working on issue A never reads `state/B/loop.json`.
2. **Lock-before-modify.** Every mutation of `loop.json` is guarded by flock.
3. **Atomic writes only.** mktemp + rename is the only permitted write pattern for state files.
4. **Learnings are append-only.** No agent rewrites `learnings.jsonl`; deduplication is read-time.
5. **Lock files are never committed to source control.**
