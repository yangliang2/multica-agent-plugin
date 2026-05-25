# multica-workflow — 5-Phase State Machine

This skill governs the full lifecycle of a Multica agent task from assignment to terminal state.

---

## Phase 1: discover

**Entry condition:** Issue assigned to agent, or `on_comment` event received while status is `blocked`.

**Actions:**
1. Fetch issue details: `<<cli:issue.get>>`
2. Fetch full comment history: `<<cli:issue.comment.list>>`
3. Check metadata for prior run context via `<<cli:issue.metadata.set>>`
4. Read issue metadata for prior agent context: `<<cli:issue.metadata.list>>`
   Key fields to look for: blocked_reason (prior HITL), pr_url, pipeline_status, waiting_on
5. Identify task, completed work, and missing pieces

**Exit condition:** Requirements are understood with no blocking unknowns.

**Recommended CLI calls:**
- `<<cli:issue.get>>` — task description
- `<<cli:issue.comment.list>>` — prior commentary and human replies
- `<<cli:issue.metadata.set>>` — durable cross-run state (PR URL, deploy URL)

**Transition:** → plan (clear requirements) | → report/blocked (HITL needed immediately)

---

## Phase 2: plan

**Entry condition:** Requirements clear; all needed information available.

**Actions:**
1. Draft a concise implementation plan
2. Post the plan as a comment: `<<cli:issue.comment.add>>`
   - Format: `[phase] discover→plan — <brief plan summary>`
3. Set status to `in_progress`: `<<cli:issue.status>>`

**Exit condition:** Plan is written to an issue comment; status is `in_progress`.

**Recommended CLI calls:**
- `<<cli:issue.comment.add>>` — post plan for traceability
- `<<cli:issue.status>>` — signal active execution

**Transition:** → execute

---

## Phase 3: execute

**Entry condition:** Status is `in_progress`; plan exists in issue comments.

**Actions:**
1. Implement each planned step
2. For steps >60s, post interim progress: `<<cli:issue.comment.add>>`
3. On unexpected ambiguity or missing credential: proceed to blocked
4. Track attempt count; do not loop indefinitely

**Exit condition:** Work product complete; no known defects remain; ready for verification.

**Recommended CLI calls:**
- `<<cli:issue.comment.add>>` — progress updates for long steps
- `<<cli:issue.metadata.set>>` — persist durable artifacts (PR URL, deploy URL)

**Transition:** → verify

---

## Phase 4: verify

**Entry condition:** Implementation complete.

**Actions:**
1. Run appropriate checks (tests, linters, smoke tests)
2. On failure: diagnose, fix, re-run (max 3 cycles)
3. After 3 consecutive failures without progress: → blocked
4. Post verification outcome: `<<cli:issue.comment.add>>`

**Exit condition:** All checks pass, or 3-strike failure is ready for HITL escalation.

**Recommended CLI calls:**
- `<<cli:issue.comment.add>>` — log verification results

**Transition:** → report (pass) | → blocked (3-strike failure)

---

## Phase 5: report

**Entry condition:** Verification passed, or blocked condition confirmed.

**Actions (success path):**
1. Write final summary: what was done, artifacts, caveats
   `<<cli:issue.comment.add>>`
2. Clear stale metadata: if blocked_reason was set, delete it: `<<cli:issue.metadata.delete>>` --key blocked_reason
3. Set status to `done`: `<<cli:issue.status>>`

**Actions (blocked path):**
1. Write `[HITL]` comment (see `skills/core/hitl-protocol.md`)
   `<<cli:issue.comment.add>>`
2. Set status to `blocked`: `<<cli:issue.status>>`
3. Exit immediately; do not wait for reply

**Exit condition:** Status is `done` or `blocked`. Process terminates.

**Recommended CLI calls:**
- `<<cli:issue.comment.add>>` — final summary or HITL question
- `<<cli:issue.status>>` — terminal status signal

**Transition:** None (terminal). Daemon reawakens via `on_comment` if status is `blocked`.

---

## State Transition Diagram

```
[assigned / on_comment]
        │
        ▼
    discover ──────────────────────────────┐
        │ requirements clear               │ HITL needed immediately
        ▼                                  │
      plan                                 │
        │                                  │
        ▼                                  │
    execute ◄──── fix ◄──── verify (fail, <3) 
        │                       │
        │                       │ verify pass
        ▼                       ▼
    verify ──────────────► report
        │ 3-strike fail         │
        └───────────────────────┘
                                │
                         done / blocked
```

---

## Context Budget Awareness

| Remaining | Action |
|-----------|--------|
| >$MULTICA_CONTEXT_CHECKPOINT_PCT% | Continue work |
| ≤$MULTICA_CONTEXT_CHECKPOINT_PCT% | Write checkpoint comment before complex work |
| ≤$MULTICA_CONTEXT_BLOCKED_PCT% | Checkpoint + set status `blocked` with reason "context-budget-critical" |

Checkpoint format: `[checkpoint] Completed: <done>. Remaining: <left>. Context: <N>% remaining.`

---

## Autopilot Run-Only Mode

When `$MULTICA_AUTOPILOT_RUN_ID` is set and `$MULTICA_ISSUE_ID` is empty,
this is an autopilot run-only task:
- Skip all `multica issue *` calls (get, comment, status)
- Write result directly to stdout — the platform captures it
- Persistence loop and HITL protocols do not apply
- Use `multica autopilot get $MULTICA_AUTOPILOT_RUN_ID` for configuration

---

## Daemon-Safe Notes

- Never use `sleep`, `read`, polling loops, or blocking waits
- Never hold resources (locks, connections) across `blocked` exit
- Phase transitions are driven by work completion, not time
- The daemon reaper owns timeout enforcement; do not implement timeouts
- Each phase completes in a single process invocation; `blocked` exits
