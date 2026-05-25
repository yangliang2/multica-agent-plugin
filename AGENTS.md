# AGENTS.md — Multica Agent Plugin Contract

## Identity

You operate inside a Multica issue. The issue is your task.
No human is at the keyboard. All output must be reproducible from issue comments alone.
Never ask the user a question interactively. AskUserQuestion is disabled.

---

## Cross-Harness Invariants

**Invariant 1 — Ground truth is the issue.**
Always fetch the current issue state with `<<cli:issue.get>>` before acting.
Never assume the initial prompt is complete or current.

**Invariant 2 — All communication is written.**
Report progress, questions, and results exclusively via `<<cli:issue.comment.add>>`.
No side-channel output (stdout, files outside the workspace) is authoritative.

**Invariant 3 — Status is the process signal.**
Set issue status with `<<cli:issue.status>>` at every phase transition.
Valid terminal states: `done` (success) or `blocked` (HITL required).

---

## 5-Phase Workflow State Machine

### Phase 1: discover

**Entry:** Task assigned or `on_comment` event received after `blocked`.
**Actions:**
- Fetch issue: `<<cli:issue.get>>`
- Fetch comments: `<<cli:issue.comment.list>>`
- Read any referenced files or prior run context.
**Exit:** Requirements understood, ambiguities identified.
**Next:** → plan (clear) | → blocked (HITL needed).

### Phase 2: plan

**Entry:** Requirements clear, no blocking unknowns.
**Actions:**
- Draft approach as a comment: `<<cli:issue.comment.add>>`
- Set status `in_progress`: `<<cli:issue.status>>`
- Decompose into checkable sub-steps.
**Exit:** Plan written to issue, status is `in_progress`.
**Next:** → execute.

### Phase 3: execute

**Entry:** Status is `in_progress`, plan exists in comments.
**Actions:**
- Implement each step; commit to local workspace.
- Post incremental progress comments for long-running work.
- On ambiguity or missing credential: → verify or → blocked.
**Exit:** Work product complete, no known defects.
**Next:** → verify.

### Phase 4: verify

**Entry:** Implementation complete.
**Actions:**
- Run tests, linters, or smoke checks appropriate to the task.
- On failure: fix in execute, re-enter verify (max 3 cycles).
- After 3 failures without progress: → blocked.
**Exit:** All checks pass (or failure is documented for HITL).
**Next:** → report.

### Phase 5: report

**Entry:** Verification passed (or blocked condition confirmed).
**Actions:**
- Write a final summary comment: `<<cli:issue.comment.add>>`
- Set terminal status: `<<cli:issue.status>>` → `done` or `blocked`.
- If blocked: include `[HITL]` tag with question (see hitl-protocol.md).
**Exit:** Status is `done` or `blocked`. Process exits.
**Next:** None (terminal) | daemon reawakens on `on_comment` if `blocked`.

---

## Skills Index

- `skills/core/multica-workflow.md` — Phase state machine, CLI calls, exit conditions
- `skills/core/hitl-protocol.md` — Human-in-the-loop triggers, comment template, blocked lifecycle
- `docs/abi/cli-outward.md` — CLI subset reference, JSON schemas, version contract
- `capabilities/claude-code.json` — Claude Code harness capability map

---

## HITL Contract

AskUserQuestion is **disabled**. No interactive prompting is permitted.
Human-in-the-loop is achieved exclusively by:
1. Writing a `[HITL]` comment via `<<cli:issue.comment.add>>`
2. Setting status to `blocked` via `<<cli:issue.status>>`
3. Exiting the process and awaiting `on_comment` reactivation by the daemon

See `skills/core/hitl-protocol.md` for full protocol.

---

## Daemon-Safe Notes

- Never use `sleep`, polling loops, or any construct that suspends the process waiting for user input.
- Never hold a file lock or network connection across a status=`blocked` exit.
- The daemon reaper is the sole owner of timeout enforcement. Skills must not implement their own timeouts.
- Each invocation is stateless except for what is persisted in issue comments and metadata.
- Do NOT invoke OMC skills (/ralph, /autopilot, /team) or Superpowers skills
  (/brainstorming) — they require AskUserQuestion which is disabled in daemon mode
  and will cause the session to hang or produce unexpected output.

---

## Squad Awareness

When the Multica daemon assigns an issue to a squad, it writes a runtime config
to disk containing a Squad Operating Protocol header and a Squad Roster. Detect
your role by reading the on-disk config written at session start.

**Role detection** (check `${MULTICA_WORKDIR}/CLAUDE.md` at session start):
- The Squad Operating Protocol header is present → you are the **Squad Leader**
  - Load `skills/core/squad-leader-workflow.md`
  - Coordinate, do NOT implement; delegate via roster members
  - Call `<<cli:squad.activity>>` at every turn end (mandatory)
- No such header → **Squad Member** (triggered by leader @mention) or single-agent
  - Squad Member: load `skills/core/squad-member-workflow.md`
  - Single-agent: continue standard 5-phase workflow

**HITL in squad context:**
- Members escalate to `[HITL:leader]` first (not `[HITL:human]`)
- After 3 bounces with same `question_id` → escalate to `[HITL:human]`
