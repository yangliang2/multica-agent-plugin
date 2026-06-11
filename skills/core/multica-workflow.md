# multica-workflow — 7-Phase State Machine

This skill governs the full lifecycle of a Multica agent task from assignment to terminal state.

---

## Signal Grammar

Agents emit phase signals in issue comments to communicate lifecycle state. Users respond with steering signals.
Full tables for both directions are in `docs/HUMAN-GUIDE.md §2 Comment Protocol`.

Quick reference — signal emitted at each phase exit and the user signal that resumes it:

| Phase | Agent emits at exit | User signal to resume |
|-------|--------------------|-----------------------|
| spec | `[spec:vN]` | `[proceed]` or `[revise: <feedback>]` |
| plan | `[phase] spec→plan` | (automatic — no user action) |
| demo | `[demo:vN]` | `[looks-right]` or `[wrong: <feedback>]` |
| execute | `[checkpoint:N]` every 5 iterations | (automatic — no user action) |
| verify | `[verification]` | (automatic — no user action) |
| result | `[result]` | (automatic — terminal) |
| blocked (HITL) | `[HITL] phase=<phase> question_id=<uuid>` | Plain text reply to the HITL comment |

`[loop-exhausted]` and `[loop-stuck]` are emitted by the persistence loop when iteration limits are hit;
both require human intervention. `[revise:]` and `[wrong:]` user signals trigger agent regeneration and
are captured as repo-scoped learnings (confidence=9).

---

## Phase 1: spec

**Entry condition:** Issue newly assigned (iteration=0, no prior phase), or `on_comment` received after exit with `[spec:vN]` comment pending user response.

**Actions:**
1. Fetch issue: `<<cli:issue.get>>`
2. Fetch comments: `<<cli:issue.comment.list>>`
3. Check for `[revise: <feedback>]` signal in comments — if present, incorporate feedback into regenerated spec
4. Generate structured specification: requirements, acceptance criteria, constraints, out-of-scope
5. Post comment with `[spec:vN]` prefix (vN = spec_version + 1); increment spec_version in loop.json
6. Set loop.json phase = "spec"

**Exit:** exit 0 (user-visible checkpoint; user must post `[proceed]` or `[revise:]` to continue)

**Transition:** On next session — detect `[proceed]` → phase=plan | detect `[revise:]` → regenerate spec (bump vN)

---

## Phase 2: plan

**Entry condition:** Prior phase was "spec" and user posted `[proceed]` signal.

**Actions:**
1. Read spec from most recent `[spec:vN]` comment
2. Decompose into ordered sub-steps; store in loop.json.progress.completed_steps / current_step
3. Post `[phase] spec→plan` transition marker comment
4. Set loop.json phase = "plan"; auto-advance (no user wait)

**Exit:** exit 0, auto-advances to demo on next session (no user checkpoint)

**Transition:** Auto → phase=demo on next session start

---

## Phase 3: demo

**Entry condition:** Prior phase was "plan".

**Actions:**
1. Read plan from loop.json.progress
2. Build minimal working version (proof-of-concept, UI mock, non-functional test, or simplest passing implementation)
3. Post comment with `[demo:vN]` prefix showing what was built and key design decisions
4. Set loop.json phase = "demo"

**Exit:** exit 0 (user-visible checkpoint; user must post `[looks-right]` or `[wrong:]` to continue)

**Transition:** On next session — detect `[looks-right]` → phase=execute | detect `[wrong: <feedback>]` → fix demo (bump vN)

---

## Phase 4: execute

**Entry condition:** Prior phase was "demo" and user posted `[looks-right]` signal, or resuming mid-execute.

**Actions:**
1. Implement all planned sub-steps from loop.json.progress
2. Update progress.current_step and progress.completed_steps after each step
3. Commit code to workspace
4. If more steps remain: exit 2 (internal loop — no user visibility)
5. Post `[checkpoint:N]` comment only when iteration count >= 5
6. On ambiguity or missing credential: exit 0 with `[HITL]` comment (phase stays "execute")

**Exit:**
- exit 2 while steps remain (internal persistence loop; increment iteration and exit2_triggers_per_session)
- exit 0 when all steps complete → phase=verify
- exit 0 at max_iterations (50) → post `[loop-exhausted]` comment, set phase="result"

**Transition:** Auto → phase=verify when all steps complete

---

## Phase 5: verify

**Entry condition:** Prior phase was "execute" and all steps complete, or resuming mid-verify.

**Actions:**
1. Run `bash $MULTICA_PLUGIN_ROOT/tools/run-verification.sh {issue_id}` — it resolves the
   command (loop.json.verification_cmd, else ecosystem default: npm test / pytest /
   cargo test / go test), captures evidence (exit_code, command, output_hash = SHA256
   first 8 chars), categorizes failures, and detects flaky-suspect runs (same
   output_hash, differing exit_codes across attempts in verify-attempts.jsonl)
2. Post its stdout as the `[verification]` comment (includes category=syntax|import|
   assertion|timeout|permission|unknown on failure, flaky_suspect=true when detected)
3. On failure: read `category=` to steer the fix — do not blindly retry the same change;
   flaky_suspect=true → retry once before treating as a real failure
4. Attempt fix in same session and re-verify (max 3 attempts)
5. After 3 failures: post `[verify-failed]` comment, advance to result phase

**Exit:** exit 0 → phase=result

**Transition:** Auto → phase=result

---

## Phase 6: result

**Entry condition:** Verify phase complete (pass or 3-strike fail).

**Actions:**
1. Extract learnings from `[wrong:]`/`[revise:]` signals in comment history
2. Synthesize final summary: what was done, evidence, caveats, any failures
3. Post `[result]` comment with summary
4. Set issue status done: `<<cli:issue.status>>`
5. Set loop.json phase = "done"

**Exit:** exit 0 (terminal)

**Transition:** → done (process exits)

---

## Phase 7: done

**Entry condition:** Phase="done" set by result phase.

**Actions:**
1. Extract learnings to repo-scoped store (handled by stop.sh on exit)
2. Issue is already status=done
3. No comment needed

**Exit:** exit 0 (immediate — stop.sh handles cleanup)

---

## State Transition Diagram

```
[assigned / on_comment]
        │
        ▼
      spec ──── [revise:] ──► regenerate spec (vN++)
        │ [proceed]
        ▼
      plan (internal, auto-advance)
        │
        ▼
      demo ──── [wrong:] ──► rebuild demo (vN++)
        │ [looks-right]
        ▼
    execute ◄── exit 2 (internal loop, ≤50 iter)
        │ all steps done
        ▼
     verify ◄── fix+retry (max 3)
        │ pass or 3-strike fail
        ▼
     result ──► done (terminal)

     spec/demo/result: exit 0 (user checkpoint)
     plan/verify: exit 0 (auto-advance)
     execute: exit 2 loop internally, exit 0 to advance
     HITL: exit 0 with [HITL] comment → blocked → on_comment resumes
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

## loop.json Schema

All fields are optional on read; defaults are applied by stop.sh and session-start.sh.
Old v2.2.0 files that lack v2.3.0 fields remain valid.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `active` | boolean | `false` | Whether the persistence loop is running |
| `session_id` | string | `""` | Claude Code session ID for this loop |
| `issue_id` | string | `""` | Multica issue ID (pattern: `[A-Za-z0-9._-]{1,64}`) |
| `iteration` | integer | `0` | Current iteration counter (0–1000) |
| `max_iterations` | integer | `50` | Hard stop after this many iterations (1–1000) |
| `phase` | string | `""` | Current workflow phase; valid values: `spec`, `plan`, `demo`, `execute`, `verify`, `result`, `done`, `setup`, `execution`, `deslop`, `complete`, `blocked`, `verification`, `report` |
| `passes` | boolean | `false` | Whether the current iteration passed verification |
| `last_updated` | string | `""` | ISO 8601 timestamp of last write |
| `nonce` | string | `""` | DONE-signal nonce for this session |
| `evidence_file` | string | `""` | Path to verification evidence artifact |
| `mode` | string | `"execution"` | `execution` or `planning`. Set once at session start: epic keywords (epic/initiative/roadmap) in the issue title → `planning` (decomposition only, no implementation); an existing key is never overwritten (v2.3.0+) |
| `spec_version` | integer | `0` | Schema version; 0 = v2.2.0 compat, 1 = v2.3.0 (v2.3.0+) |
| `verification_cmd` | string | `""` | Shell command to run during verify phase (v2.3.0+) |
| `progress.summary` | string | `""` | Human-readable progress summary (v2.3.0+) |
| `progress.pct` | integer | `0` | Explicit progress percentage 0–100; overrides story-derived pct in loop-status (v2.3.0+) |
| `progress.completed_steps` | array | `[]` | List of completed step identifiers (v2.3.0+) |
| `progress.current_step` | string | `""` | Identifier of the step currently in progress (v2.3.0+) |
| `exit2_triggers_per_session` | integer | `0` | Count of exit-2 stop-hook triggers in this session; incremented by execute-phase exit-2 (v2.3.0+) |
| `open_hitls` | array | `[]` | Open HITL questions: `{question_id, asked_at, tier}`. session-start matches human replies against each `question_id` on resume (v2.3.0+) |
| `resolved_hitls` | array | `[]` | Answered HITL questions: open entry + `{answer, answered_at}`. Never re-post a question that appears here (v2.3.0+) |

---

## Daemon-Safe Notes

- Never use `sleep`, `read`, polling loops, or blocking waits
- Never hold resources (locks, connections) across `blocked` exit
- Phase transitions are driven by work completion, not time
- The daemon reaper owns timeout enforcement; do not implement timeouts
- Each phase completes in a single process invocation; `blocked` exits
