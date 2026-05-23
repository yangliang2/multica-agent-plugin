# multica-workflow — 5-Phase State Machine

This skill governs the full lifecycle of a Multica agent task from assignment to terminal state.

---

## Phase 1: discover

**Entry condition:** Issue assigned to agent, or `on_comment` event received while status is `blocked`.

**Actions:**
1. Fetch issue details: `<<cli:issue.get>>`
   - Read `title`, `description`, `status`, `assignee`, `metadata`.
2. Fetch full comment history: `<<cli:issue.comment.list>>`
   - For long-running issues, use `--recent 20` to load the most active threads.
3. Check metadata for prior run context: `<<cli:issue.metadata.set>>` keys such as `pipeline_status`, `pr_number`.
4. Identify: what is the task? What is already done? What is missing?

**Exit condition:** Requirements are understood with no blocking unknowns.

**Recommended CLI calls:**
- `<<cli:issue.get>>` — primary task description
- `<<cli:issue.comment.list>>` — prior agent commentary and human replies
- `<<cli:issue.metadata.set>>` — only to write durable cross-run state (PR URL, deploy URL)

**Transition:** → plan (clear requirements) | → report/blocked (HITL needed immediately)

---

## Phase 2: plan

**Entry condition:** Requirements clear; all needed information available.

**Actions:**
1. Draft a concise implementation plan.
2. Post the plan as a comment: `<<cli:issue.comment.add>>`
3. Set status to `in_progress`: `<<cli:issue.status>>`
4. Enumerate concrete, verifiable sub-steps.

**Exit condition:** Plan is written to an issue comment; status is `in_progress`.

**Recommended CLI calls:**
- `<<cli:issue.comment.add>>` — post plan for traceability
- `<<cli:issue.status>>` — signal active execution to daemon and teammates

**Transition:** → execute

---

## Phase 3: execute

**Entry condition:** Status is `in_progress`; plan exists in issue comments.

**Actions:**
1. Implement each planned step in the local workspace.
2. For steps that take >60s, post an interim progress comment: `<<cli:issue.comment.add>>`
3. On unexpected ambiguity or missing external credential: stop and proceed to blocked.
4. Do not loop indefinitely; track attempt count via local counter.

**Exit condition:** Work product complete; no known defects remain; ready for verification.

**Recommended CLI calls:**
- `<<cli:issue.comment.add>>` — progress updates for long steps
- `<<cli:issue.metadata.set>>` — persist durable artifacts (PR URL, deploy URL)

**Transition:** → verify

---

## Phase 4: verify

**Entry condition:** Implementation complete.

**Actions:**
1. Run appropriate checks (tests, linters, smoke tests) for the task type.
2. On failure: diagnose, fix, re-run. Track cycles (max 3).
3. After 3 consecutive failures without forward progress: → blocked.
4. Post verification outcome as a comment: `<<cli:issue.comment.add>>`

**Exit condition:** All checks pass, or a documented 3-strike failure is ready for HITL escalation.

**Recommended CLI calls:**
- `<<cli:issue.comment.add>>` — log verification results for traceability

**Transition:** → report (pass) | → blocked (3-strike failure)

---

## Phase 5: report

**Entry condition:** Verification passed, or blocked condition confirmed.

**Actions (success path):**
1. Write a final summary comment including: what was done, artifacts produced, any caveats.
   `<<cli:issue.comment.add>>`
2. Set status to `done`: `<<cli:issue.status>>`

**Actions (blocked path):**
1. Write a `[HITL]` comment (see `skills/core/hitl-protocol.md` for template).
   `<<cli:issue.comment.add>>`
2. Set status to `blocked`: `<<cli:issue.status>>`
3. Exit process immediately. Do not wait for reply.

**Exit condition:** Status is `done` or `blocked`. Process terminates.

**Recommended CLI calls:**
- `<<cli:issue.comment.add>>` — final summary or HITL question
- `<<cli:issue.status>>` — terminal status signal

**Transition:** None (terminal). Daemon reawakens via `on_comment` event if status is `blocked`.

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

## Daemon-Safe Notes

- Never use `sleep`, `read`, polling loops, or any blocking wait for human input.
- Never hold resources (locks, connections) across a `blocked` exit.
- Phase transitions are driven by work completion, not by time.
- The daemon reaper owns all timeout enforcement; this skill must not implement timeouts.
- Each phase should complete within a single process invocation; `blocked` exits the process.
