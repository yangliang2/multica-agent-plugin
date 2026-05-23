# Persistence Loop

PRD-driven persistence loop with session state, completion signal protocol, automatic retry,
and mandatory deslop pass. Distilled from OMC ralph and oh-my-openagent.

> **Degradation notice:** When running outside Claude Code, this skill is a no-op.
> The Stop hook that enforces loop continuation is Claude Code-specific.
> In other harnesses, implement continuation manually.

---

## When to Use

- Task requires guaranteed completion with reviewer verification (not "do your best")
- Work may span multiple iterations and needs persistence across session restarts
- Task has discrete acceptance criteria that can be checked story-by-story
- You need automatic retry on failure with capped iteration count

---

## State Schema

Loop state lives at `.multica/state/<issue_id>/loop.json`.

```json
{
  "active": true,
  "iteration": 0,
  "max_iterations": 50,
  "issue_id": "<id>",
  "session_id": "<claude-session-id>",
  "started_at": "<ISO8601>",
  "last_checkpoint_at": "<ISO8601>",
  "stories": [
    {
      "id": "S1",
      "title": "<short title>",
      "acceptance": "<concrete verifiable criterion>",
      "passes": false
    }
  ],
  "phase": "execution"
}
```

Field constraints:
- `active` — `true` while the loop is running; set to `false` only on completion or hard block
- `iteration` — incremented at the start of each loop iteration; never decremented
- `max_iterations` — hard cap, default 50; when reached the loop halts with HITL comment
- `phase` — one of: `"setup"`, `"execution"`, `"deslop"`, `"review"`, `"complete"`
- `stories[].passes` — set to `true` only after ALL acceptance criteria are verified with fresh evidence
- All writes to `loop.json` MUST use mktemp + atomic rename (see `docs/concurrency-model.md`)

---

## Completion Signal Protocol

The Stop hook (`hooks/stop.sh`) gates session termination.
An agent is considered **done** only when it emits the following literal string in its output:

```
<promise>DONE</promise>
```

This string must appear in the agent's stdout (captured via `CLAUDE_TOOL_OUTPUT` or the
output capture file). The Stop hook scans for this exact byte sequence.

Rules:
- Output `<promise>DONE</promise>` only when ALL stories have `passes: true` AND the
  reviewer has signed off.
- Never output it speculatively or as a progress marker.
- If the Stop hook does not detect `<promise>DONE</promise>`, it writes a checkpoint
  comment and returns exit code 2, which blocks the Stop and forces continuation.
- The agent must not attempt to fake completion by outputting the signal without
  meeting all acceptance criteria. The Stop hook cross-checks `loop.json` state.

---

## Execution Loop (7 Steps)

### Step 1 — Setup (first iteration only)

a. Read `loop.json` if it exists; create it if not.
b. Decompose the issue into user stories with concrete, verifiable acceptance criteria.
   Generic criteria ("implementation is complete") are forbidden — replace with specific
   assertions (e.g., "function X returns Y given input Z", "test at path P passes").
c. Write the initial `loop.json` with `phase: "setup"`, `iteration: 0`, all stories
   with `passes: false`.
d. Set `phase: "execution"` and write checkpoint.

### Step 2 — Pick Next Story

Read `loop.json`. Select the highest-priority story where `passes: false`.
If all stories have `passes: true`, skip to Step 6.

### Step 3 — Implement the Story

- Delegate to specialist agents at appropriate tiers (see `skills/advanced/parallel-exec.md`):
  - Mechanical (1–2 files, clear spec) → haiku
  - Integration / judgment (multi-file, pattern matching) → sonnet
  - Architecture / review → opus
- Run long operations in background (builds, installs, test suites).
- Post incremental progress comments for work > 2 minutes via `multica issue comment add`.

### Step 4 — Verify Acceptance Criteria

For EACH acceptance criterion in the current story:
a. Gather fresh evidence (run test, read output, inspect file).
b. If any criterion is not met, continue implementing — do NOT mark the story complete.
c. Only proceed when ALL criteria are met with evidence in hand.

### Step 5 — Mark Story Complete

a. Set `passes: true` for the story in `loop.json`.
b. Increment `iteration` counter.
c. Write a learning entry to `.multica/learnings.jsonl` capturing what was learned.
d. Write checkpoint: `last_checkpoint_at = now`, `phase: "execution"`.
e. Loop back to Step 2.

### Step 6 — Deslop Pass

When all stories have `passes: true`, set `phase: "deslop"` and run a cleanup pass.

**Deslop pass removes:**
- Unnecessary comments that restate what the code does (e.g., `# increment counter` above `i += 1`)
- Over-defensive code that guards against conditions the type system already prevents
- Redundant type annotations that TypeScript/Python already infers unambiguously
- Dead code paths that are never reached
- Excessive logging added during debugging

**Deslop pass does NOT:**
- Remove comments that explain *why* (rationale, non-obvious constraints)
- Remove error handling for real failure modes
- Alter behavior or tests
- Touch files outside the scope of the current issue

After deslop, write `phase: "review"` checkpoint.

### Step 7 — Reviewer Sign-Off

Dispatch a reviewer subagent (see `skills/advanced/parallel-exec.md`).
The reviewer checks ALL acceptance criteria across ALL stories against the current code.

- If reviewer rejects: set `passes: false` on the failed stories, loop back to Step 2.
- If reviewer approves: set `phase: "complete"`, `active: false`, write final checkpoint.
- Post a `[loop-complete]` comment via `multica issue comment add`.
- Output `<promise>DONE</promise>` — the Stop hook will detect this and exit cleanly.

---

## Iteration Hard Cap

`max_iterations` defaults to 50. When `iteration >= max_iterations`:

1. Write a `[loop-blocked: max iterations reached]` comment with current story states.
2. Set issue status to `blocked` via `multica issue status set blocked`.
3. Set `active: false` in `loop.json`.
4. Exit WITHOUT outputting `<promise>DONE</promise>`.

The daemon reactivates on `on_comment` (human provides direction).
Do not increase `max_iterations` without explicit human approval.

---

## Checkpoint Deduplication

Each checkpoint comment written by the Stop hook includes a dedup hash:
`sha256(issue_id + iteration + phase)` truncated to 8 hex characters.

Before writing a new checkpoint comment, check recent comments for a matching hash.
If found, skip the write (idempotent behavior). This prevents duplicate comments
when the Stop hook fires multiple times in the same state.
