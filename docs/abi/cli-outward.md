# cli-outward.md — Multica CLI Outward ABI

Defines the minimum CLI subset that Multica agent plugin skills depend on.
Agents must use these commands exclusively through their `<<cli:*>>` anchors.
Raw command literals must not appear in skill files.

**Version contract:** This ABI requires `multica >= 0.3.4`.
Verify with: `multica version` (expected output: `multica 0.3.4` or higher).

---

## Anchor Index

| Anchor | Resolved command |
|--------|-----------------|
| `<<cli:issue.get>>` | `multica issue get <id> --output json` |
| `<<cli:issue.comment.add>>` | `multica issue comment add <issue-id> --content "..."` |
| `<<cli:issue.comment.list>>` | `multica issue comment list <issue-id>` |
| `<<cli:issue.comment.list.thread>>` | `multica issue comment list <issue-id> --thread <comment-id> --tail 30 --output json` |
| `<<cli:issue.status>>` | `multica issue status <id> <status>` |
| `<<cli:issue.create>>` | `multica issue create --title "..." --assignee "..."` |
| `<<cli:issue.create.child>>` | `multica issue create --title "..." --status todo --assignee-id <uuid>` |
| `<<cli:issue.metadata.list>>` | `multica issue metadata list <issue-id> --output json` |
| `<<cli:issue.metadata.set>>` | `multica issue metadata set <issue-id> --key <k> --value <v>` |
| `<<cli:issue.metadata.delete>>` | `multica issue metadata delete <issue-id> --key <key>` |
| `<<cli:squad.activity>>` | `multica squad activity <issue-id> <outcome> --reason "..."` |
| `<<cli:autopilot.get>>` | `multica autopilot get <autopilot-id> --output json` |

---

## Command Reference

### issue get

Fetch full issue details as JSON.

**Anchor:** `<<cli:issue.get>>`

**Synopsis:**
```
multica issue get <id> [--output json]
```

**Arguments:**
- `<id>` — issue key (e.g. `MUL-123`) or full UUID.

**Flags:**
- `--output json` — required for machine-readable output (default is `json`).

**Minimal JSON response schema:**
```json
{
  "id": "string (UUID)",
  "key": "string (e.g. MUL-123)",
  "title": "string",
  "description": "string | null",
  "status": "string (backlog|todo|in_progress|in_review|done|blocked|cancelled)",
  "assignee": {
    "id": "string (UUID)",
    "name": "string",
    "type": "string (member|agent)"
  } | null,
  "metadata": {
    "<key>": "<value>"
  }
}
```

**Error behaviour:** Non-zero exit on not-found or auth failure. Check exit code before parsing.

---

### issue comment add

Post a comment to an issue. Primary output channel for agent communication.

**Anchor:** `<<cli:issue.comment.add>>`

**Synopsis:**
```
multica issue comment add <issue-id> --content "..." [--parent <comment-id>] [--content-stdin]
```

**Arguments:**
- `<issue-id>` — issue key or UUID.

**Key flags:**
- `--content "..."` — comment body. Decodes `\n`, `\t`, `\\`.
- `--content-stdin` — read body from stdin; preserves multi-line content verbatim (preferred for HITL comments and final reports).
- `--content-file <path>` — read body from a UTF-8 file.
- `--parent <comment-id>` — reply to a specific comment thread.
- `--output json` — structured response (default `json`).

**Minimal JSON response schema:**
```json
{
  "id": "string (UUID)",
  "issue_id": "string (UUID)",
  "content": "string",
  "created_at": "string (RFC3339)",
  "parent_id": "string (UUID) | null"
}
```

**Usage notes:**
- For HITL comments, prefer `--content-stdin` to preserve formatting.
- The `id` field in the response is the comment's UUID; store in metadata if a later reply needs to reference it via `--parent`.
- No `--idempotency-key` flag exists; use a dedup hash in the comment body for client-side deduplication.

---

### issue comment list

Fetch comments on an issue. Use to read prior agent and human communication.

**Anchor:** `<<cli:issue.comment.list>>`

**Synopsis:**
```
multica issue comment list <issue-id> [--recent N] [--thread <comment-id> [--tail N]]
```

**Arguments:**
- `<issue-id>` — issue key or UUID.

**Key flags:**
- `--recent N` — return the N most recently active threads (recommended for discover phase).
- `--thread <comment-id>` — return a single thread (root + descendants).
- `--tail N` — cap replies within a thread to the N most recent.
- `--since <RFC3339>` — incremental polling; filters replies older than the timestamp.

**Minimal JSON response schema (per comment entry):**
```json
{
  "id": "string (UUID)",
  "parent_id": "string (UUID) | null",
  "content": "string",
  "author": {
    "id": "string (UUID)",
    "name": "string",
    "type": "string (member|agent)"
  },
  "created_at": "string (RFC3339)"
}
```

**Usage notes:**
- Hard cap of 2000 rows on flat reads. Use `--recent 20` on long-running issues.
- Pagination cursor emitted on stderr as `Next thread cursor` or `Next reply cursor`.

**Thread variant anchor:** `<<cli:issue.comment.list.thread>>`
```
multica issue comment list <issue-id> --thread <comment-id> --tail 30 --output json
```

---

### issue status

Change the status of an issue. Used at every phase transition.

**Anchor:** `<<cli:issue.status>>`

**Synopsis:**
```
multica issue status <id> <status>
```

**Arguments:**
- `<id>` — issue key or UUID.
- `<status>` — one of the valid values below.

**Valid status values:**

| Value | Meaning for agent workflow |
|-------|---------------------------|
| `in_progress` | Agent is actively executing (set at plan→execute) |
| `blocked` | HITL required; agent has exited (set at report when blocked) |
| `done` | Task complete; agent has exited (set at report on success) |
| `backlog` | Pre-assignment; agent should not set this |
| `todo` | Queued; agent should not set this |
| `in_review` | Human review stage; agent may set if task is a PR/review |
| `cancelled` | Withdrawn; agent should not set this unilaterally |

**Minimal JSON response schema (with `--output json`):**
```json
{
  "id": "string (UUID)",
  "status": "string"
}
```

---

### issue create

Create a new issue, optionally assigning it to an agent or squad member.

**Anchor:** `<<cli:issue.create>>`

**Synopsis:**
```
multica issue create --title "..." [--description "..."] [--assignee <name>] [--assignee-id <uuid>] [--status <status>] [--priority <priority>]
```

**Key flags:**
- `--title "..."` — required.
- `--description "..."` — markdown body.
- `--assignee <name>` — assign by display name.
- `--assignee-id <uuid>` — assign by UUID (preferred in squad context to avoid name ambiguity).
- `--status <status>` — initial status (default `todo`).
- `--priority <priority>` — one of `urgent`, `high`, `medium`, `low`.
- `--output json` — structured response.

**Child issue variant anchor:** `<<cli:issue.create.child>>`

For squad Strategy A (true parallel delegation), create a child issue and assign to a specific member:
```
multica issue create --title "..." --status todo --assignee-id <member-uuid>
```
Multica daemon auto-notifies the parent issue when the child transitions to `done`
(`issue_child_done.go`). The leader does NOT need to manually backlink or poll.

---

### issue metadata set / list / delete

Persist and retrieve durable key-value pairs on an issue for cross-run state.

**Anchors:**
- `<<cli:issue.metadata.set>>` — write a value
- `<<cli:issue.metadata.list>>` — read all values
- `<<cli:issue.metadata.delete>>` — remove a key

**Synopsis:**
```
multica issue metadata set <issue-id> --key <key> --value <value> [--type string|number|bool]
multica issue metadata list <issue-id> [--output json]
multica issue metadata delete <issue-id> --key <key>
```

**Usage notes:**
- Write only materially important, cross-run values: PR URL, deploy URL, pipeline status, blocked_reason.
- Do not write: runtime bookkeeping, investigation notes, secrets, or comment copies.
- Values are auto-typed unless `--type` is specified.
- Max 50 keys per issue; blob capped at 8KB.

---

### squad activity

Record the squad leader's evaluation decision after each trigger. **Mandatory** — must be called at every turn end when running as squad leader.

**Anchor:** `<<cli:squad.activity>>`

**Synopsis:**
```
multica squad activity <issue-id> <outcome> [--reason "..."] [--output json]
```

**Arguments:**
- `<issue-id>` — issue key or UUID.
- `<outcome>` — one of: `action`, `no_action`, `failed`.

**Outcome semantics:**

| Outcome | When to use |
|---------|-------------|
| `action` | Leader delegated work or took direct action |
| `no_action` | Leader evaluated and decided no action needed (silent exit — do NOT post a comment) |
| `failed` | Leader encountered an error it could not recover from |

**Flags:**
- `--reason "..."` — short explanation of the decision (recommended for `action` and `failed`).
- `--output json` — structured response.

**Usage notes:**
- Call this at every turn end, no exceptions.
- For `no_action`: call this command and exit immediately. Do NOT post any comment — the daemon treats a comment in this case as spurious noise.
- `hooks/stop.sh` will call `multica squad activity failed` automatically if the leader exits without calling this command.

---

### autopilot get

Fetch autopilot details including trigger configuration. Used in autopilot run-only mode.

**Anchor:** `<<cli:autopilot.get>>`

**Synopsis:**
```
multica autopilot get <id> [--output json]
```

**Arguments:**
- `<id>` — autopilot UUID or key.

**Flags:**
- `--output json` — default for machine-readable output.

---

## Version Compatibility Declaration

This ABI is validated against `multica 0.3.4` (commit `cf000d1e`, built `2026-05-20`).
Updated: 2026-05-26 (v1.0.0 — added squad.activity, metadata.list/delete, issue.create, autopilot.get; confirmed no --idempotency-key flag on comment add).

Minimum required version: **multica >= 0.3.4**

Commands used:
- `issue get` — stable since 0.1.x
- `issue comment add` — stable since 0.1.x; `--content-stdin` added in 0.2.x
- `issue comment list` — stable since 0.1.x; `--recent`, `--tail`, `--since` added in 0.2.x
- `issue status` — stable since 0.1.x
- `issue metadata set/list/delete` — stable since 0.2.x
- `issue create` — stable since 0.1.x
- `squad activity` — stable since 0.3.x
- `autopilot get` — stable since 0.2.x

If `multica version` reports a version below `0.3.4`, run `multica update` before proceeding.


---

## Command Reference

### issue get

Fetch full issue details as JSON.

**Anchor:** `<<cli:issue.get>>`

**Synopsis:**
```
multica issue get <id> [--output json]
```

**Arguments:**
- `<id>` — issue key (e.g. `MUL-123`) or full UUID.

**Flags:**
- `--output json` — required for machine-readable output (default is `json`).

**Minimal JSON response schema:**
```json
{
  "id": "string (UUID)",
  "key": "string (e.g. MUL-123)",
  "title": "string",
  "description": "string | null",
  "status": "string (backlog|todo|in_progress|in_review|done|blocked|cancelled)",
  "assignee": {
    "id": "string (UUID)",
    "name": "string",
    "type": "string (member|agent)"
  } | null,
  "metadata": {
    "<key>": "<value>"
  }
}
```

**Error behaviour:** Non-zero exit on not-found or auth failure. Check exit code before parsing.

---

### issue comment add

Post a comment to an issue. Primary output channel for agent communication.

**Anchor:** `<<cli:issue.comment.add>>`

**Synopsis:**
```
multica issue comment add <issue-id> --content "..." [--parent <comment-id>] [--content-stdin]
```

**Arguments:**
- `<issue-id>` — issue key or UUID.

**Key flags:**
- `--content "..."` — comment body. Decodes `\n`, `\t`, `\\`.
- `--content-stdin` — read body from stdin; preserves multi-line content verbatim (preferred for HITL comments and final reports).
- `--content-file <path>` — read body from a UTF-8 file.
- `--parent <comment-id>` — reply to a specific comment thread.
- `--output json` — structured response (default `json`).

**Minimal JSON response schema:**
```json
{
  "id": "string (UUID)",
  "issue_id": "string (UUID)",
  "content": "string",
  "created_at": "string (RFC3339)",
  "parent_id": "string (UUID) | null"
}
```

**Usage notes:**
- For HITL comments, prefer `--content-stdin` to preserve formatting.
- The `id` field in the response is the comment's UUID; store in metadata if a later reply needs to reference it via `--parent`.

---

### issue comment list

Fetch comments on an issue. Use to read prior agent and human communication.

**Anchor:** `<<cli:issue.comment.list>>`

**Synopsis:**
```
multica issue comment list <issue-id> [--recent N] [--thread <comment-id> [--tail N]]
```

**Arguments:**
- `<issue-id>` — issue key or UUID.

**Key flags:**
- `--recent N` — return the N most recently active threads (recommended for discover phase).
- `--thread <comment-id>` — return a single thread (root + descendants).
- `--tail N` — cap replies within a thread to the N most recent.
- `--since <RFC3339>` — incremental polling; filters replies older than the timestamp.

**Minimal JSON response schema (per comment entry):**
```json
{
  "id": "string (UUID)",
  "parent_id": "string (UUID) | null",
  "content": "string",
  "author": {
    "id": "string (UUID)",
    "name": "string",
    "type": "string (member|agent)"
  },
  "created_at": "string (RFC3339)"
}
```

**Usage notes:**
- Hard cap of 2000 rows on flat reads. Use `--recent 20` on long-running issues.
- Pagination cursor emitted on stderr as `Next thread cursor` or `Next reply cursor`.

---

### issue status

Change the status of an issue. Used at every phase transition.

**Anchor:** `<<cli:issue.status>>`

**Synopsis:**
```
multica issue status <id> <status>
```

**Arguments:**
- `<id>` — issue key or UUID.
- `<status>` — one of the valid values below.

**Valid status values:**

| Value | Meaning for agent workflow |
|-------|---------------------------|
| `in_progress` | Agent is actively executing (set at plan→execute) |
| `blocked` | HITL required; agent has exited (set at report when blocked) |
| `done` | Task complete; agent has exited (set at report on success) |
| `backlog` | Pre-assignment; agent should not set this |
| `todo` | Queued; agent should not set this |
| `in_review` | Human review stage; agent may set if task is a PR/review |
| `cancelled` | Withdrawn; agent should not set this unilaterally |

**Minimal JSON response schema (with `--output json`):**
```json
{
  "id": "string (UUID)",
  "status": "string"
}
```

---

### issue metadata set

Persist a durable key-value pair on the issue for cross-run state.

**Anchor:** `<<cli:issue.metadata.set>>`

**Synopsis:**
```
multica issue metadata set <issue-id> --key <key> --value <value> [--type string|number|bool]
```

**Usage notes:**
- Write only materially important, cross-run values: PR URL, deploy URL, pipeline status.
- Do not write: runtime bookkeeping, investigation notes, secrets, or comment copies.
- Values are auto-typed unless `--type` is specified.
- Max 50 keys per issue; blob capped at 8KB.

---

## Version Compatibility Declaration

This ABI is validated against `multica 0.3.4` (commit `cf000d1e`, built `2026-05-20`).

Minimum required version: **multica >= 0.3.4**

Commands used:
- `issue get` — stable since 0.1.x
- `issue comment add` — stable since 0.1.x; `--content-stdin` added in 0.2.x
- `issue comment list` — stable since 0.1.x; `--recent`, `--tail`, `--since` added in 0.2.x
- `issue status` — stable since 0.1.x
- `issue metadata set` — stable since 0.2.x

If `multica version` reports a version below `0.3.4`, run `multica update` before proceeding.
