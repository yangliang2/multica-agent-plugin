# Multica Agent Plugin — v2.3.0 Structured Requirements

**Status:** Design Phase | **Version:** v2.3.0 | **Date:** 2026-06-09

---

## Discussion Status Legend

| Tag | Meaning |
|-----|---------|
| `[READY]` | Fully discussed in design session — cleared for implementation |
| `[CORRECTION-NEEDED]` | Discussed but acceptance criteria contains an error — fix before implementing |
| `[NEEDS-DISCUSSION]` | Not yet discussed in design session — **blocked: do not implement** |

---

## Executive Summary

This document defines the transition from v2.2.0 (reliability: preventing false-positive task completion) to v2.3.0 (intent alignment + task organization). The architectural shift moves from a single long session with exit-2 loops to a multi-session phase-driven model where user-visible checkpoints align with session exits (exit 0), and user comments trigger the next session via multica's `on_comment` mechanism.

**Core Constraint:** Only modifications to the plugin (hooks/skills/capabilities) are allowed. No changes to multica daemon itself.

---

## Architecture Evolution

### v2.2.0 Model (Current)
- Single long session per issue
- Agent loops internally via exit 2 until completion signal emitted
- User waits for session to finish (may hang indefinitely if agent loops)
- Checkpoint comments generated but have no structural significance

### v2.3.0 Model (Proposed)
- Multi-session, phase-driven lifecycle
- User-visible checkpoint = session exit (exit 0)
- User comment = next session trigger (via `multica on_comment`)
- Internal exit 2 loops only within execute phase for multi-turn implementation
- Learnings automatically captured from comment signals ([wrong:], [revise:]) without agent intervention

---

## Seven-Phase Workflow

```
spec → plan → demo → execute → verify → result → done
```

| Phase | Agent Activity | User Signal | Next |
|-------|----------------|-------------|------|
| **spec** | Generate structured specification with PRD-like detail; post [spec:vN] comment | User reviews spec; posts [proceed] or [revise:...] comment | plan |
| **plan** | Decompose into sub-steps (internal only, no spec bump needed); post no comment | Auto-transition; no user wait required | demo |
| **demo** | Build minimal visible version (MVP, non-functional test, UI prototype); post [demo:vN] comment | User reviews demo; posts [looks-right] or [wrong:...] comment | execute |
| **execute** | Full implementation; exit 2 for multi-turn iteration within this phase | Internal loop (no user visibility); post progress via [checkpoint:x] if slow | verify |
| **verify** | Run verification command; collect evidence; post [verification] comment with pass/fail | Auto-decision based on evidence gate | result |
| **result** | Synthesize learnings; post [result] comment with summary; set status done | User posts final confirmation or [abort] comment | done |
| **done** | Extract learnings to repo-scoped store; close issue | Process completes | — |

---

## Epic-Based Requirements

### **EPIC-01: Multi-Session Phase Architecture** `[READY]`
*Foundation: Enable session exits at user-visible checkpoints rather than internal loops.*

Rationale: Current v2.2.0 holds long sessions open until completion signal, blocking user feedback loops. v2.3.0 exits cleanly at checkpoints (spec, demo, result), allowing asynchronous user review.

**REQ-01-01: Spec Phase Entry & Exit Protocol**
- **Description:** Implement spec-generation phase that produces structured specification (requirements, acceptance criteria, constraints) and posts [spec:vN] comment before exit 0.
- **Priority:** P0 (architectural foundation)
- **Affected Files:** 
  - `skills/core/multica-workflow.md` (spec phase definition)
  - `hooks/stop.sh` (phase transition logic)
  - `hooks/session-start.sh` (context load for spec phase resumption)
- **Dependencies:** REQ-02-01 (comment protocol)
- **Acceptance Criteria:**
  - Agent enters spec phase on task assignment
  - Structured spec written to issue comment with [spec:vN] prefix
  - Phase transitions to plan on next session only after [proceed] received

**REQ-01-02: Plan Phase (Internal, No User Visible)**
- **Description:** Decompose spec into sub-steps without generating user-visible checkpoint.
- **Priority:** P0 (workflow sequencing)
- **Affected Files:**
  - `skills/core/multica-workflow.md` (plan phase definition)
  - `loop.json` schema extension (store decomposition for resume)
- **Dependencies:** REQ-01-01
- **Acceptance Criteria:**
  - Plan phase auto-triggers on next session if user posted [proceed]
  - Plan decomposition stored in `loop.json.plan` field (not visible as comment)
  - No [plan] comment generated; pure internal work

**REQ-01-03: Demo Phase Entry & Exit Protocol**
- **Description:** Build and present minimal working version; post [demo:vN] comment before exit 0.
- **Priority:** P0 (user feedback loop)
- **Affected Files:**
  - `skills/core/multica-workflow.md` (demo phase definition)
  - `hooks/stop.sh` (demo comment posting)
- **Dependencies:** REQ-01-02
- **Acceptance Criteria:**
  - Demo phase follows plan; outputs [demo:vN] comment
  - Demo is minimally functional (e.g., UI mock-up, non-functional test, proof-of-concept)
  - Session exits with exit 0 after [demo:vN] comment
  - Next session triggered by user's [looks-right] or [wrong:...] comment

**REQ-01-04: Execute Phase with Internal Exit-2 Loop**
- **Description:** Full implementation with exit-2 iteration mechanism retained only within execute phase.
- **Priority:** P0 (implementation strategy)
- **Affected Files:**
  - `skills/core/multica-workflow.md` (execute phase definition)
  - `hooks/stop.sh` (exit-2 loop detection)
  - `loop.json` schema (iteration count, current task tracking)
- **Dependencies:** REQ-01-03
- **Acceptance Criteria:**
  - Execute phase loops internally via exit 2 (up to max iteration limit)
  - Each exit-2 loop tracked in `loop.json.iteration`
  - User sees [checkpoint:x] comments only if execute loop exceeds threshold (e.g., 5+ iterations)
  - No user wait or intervention required during execute phase

**REQ-01-05: Verify Phase with Evidence Gate**
- **Description:** Run verification command; gate progression on evidence (exit code, test output).
- **Priority:** P0 (completion validation)
- **Affected Files:**
  - `skills/core/verification.md` (verification protocol)
  - `hooks/stop.sh` (evidence collection and interpretation)
- **Dependencies:** REQ-01-04
- **Acceptance Criteria:**
  - Verification command run in same turn (not deferred)
  - [verification] comment includes exit_code, command, output_hash
  - Failure gates progression to result phase for attempts 1 and 2 (must fix in execute)
  - Max 3 verify attempts; after 3 consecutive failures → escape-hatch: auto-transition to result with [verify-failed] tag (gate overridden only after exhaustion, not on first failure)
  - [verify-failed] result is treated as incomplete; user must post [retry] or [abort] to resolve

**REQ-01-06: Result Phase & Final User Confirmation**
- **Description:** Synthesize learnings and results; post [result] comment; wait for user approval before done.
- **Priority:** P0 (completion handoff)
- **Affected Files:**
  - `skills/core/multica-workflow.md` (result phase definition)
  - `hooks/stop.sh` (result comment posting)
- **Dependencies:** REQ-01-05
- **Acceptance Criteria:**
  - Result phase posts summary comment with [result] tag
  - Issue status set to `done` only after user posts confirmation, or auto-close after 72 hours if no user response; agent posts a [result-timeout] comment before closing
  - Learnings extracted and stored (see EPIC-05)
  - Process exits cleanly without holding session open

---

### **EPIC-02: Comment-Based User Signaling Protocol** `[READY]`

*Enable users to steer task flow and capture corrections for learning.*

**REQ-02-01: Agent Comment Signals**
- **Description:** Define structured comment markers that agent sends to indicate phase transitions and checkpoints.
- **Priority:** P0 (user communication)
- **Affected Files:**
  - `docs/HUMAN-GUIDE.md` (new section "Comment Protocol")
  - `skills/core/multica-workflow.md` (signal emission)
  - `skills/core/hitl-protocol.md` (HITL signal format)
- **Dependencies:** None (foundation)
- **Acceptance Criteria:**
  - Define agent → user signals: [spec:vN], [demo:vN], [checkpoint:x], [result], [breakdown:vN], [loop-exhausted], [loop-stuck]
  - Each signal is a single-line prefix in a comment block
  - Signal version numbers (vN) enable multi-iteration refinement
  - All signals documented in Human Guide with intent and expected user response

**REQ-02-02: User Response Signals**
- **Description:** Define expected user comment patterns that agent can detect to steer workflow.
- **Priority:** P0 (user feedback mechanism)
- **Affected Files:**
  - `docs/HUMAN-GUIDE.md` (user response section)
  - `skills/core/multica-workflow.md` (signal detection logic)
- **Dependencies:** REQ-02-01
- **Acceptance Criteria:**
  - Define user → agent signals: [proceed], [revise:...], [looks-right], [wrong:...], [abort], [retry], [approve:task-x], [skip:story-x]
  - Agent detects these signals in discover phase and adjusts state
  - [revise:...] and [wrong:...] signals trigger learning capture (see EPIC-05)
  - [abort] signal gates issue closure; agent acknowledges and sets status blocked

**REQ-02-03: Phase Transition Comment Markers**
- **Description:** Add explicit phase markers to comments to aid reviewer comprehension.
- **Priority:** P1 (reviewer experience)
- **Affected Files:**
  - `skills/core/multica-workflow.md` (comment generation)
  - `docs/HUMAN-GUIDE.md` (comment format guide)
- **Dependencies:** REQ-02-01
- **Acceptance Criteria:**
  - All phase-transition comments include [phase] source→target prefix
  - Example: [phase] spec→plan, [phase] demo→execute
  - Helps reviewer quickly scan issue timeline and locate current state

---

### **EPIC-03: loop.json Schema Extension** `[READY]`

*Extend loop.json to track multi-session state, mode, and verification requirements.*

**REQ-03-01: Core Loop Fields for Multi-Session Tracking**
- **Description:** Add fields to loop.json for mode, spec_version, verification command, and progress tracking.
- **Priority:** P0 (state persistence)
- **Affected Files:**
  - `tools/loop-status.sh` (schema reader)
  - `skills/core/multica-workflow.md` (loop.json spec)
  - `hooks/stop.sh` (loop.json writer)
  - `hooks/session-start.sh` (loop.json reader)
- **Dependencies:** None (schema extension)
- **Acceptance Criteria:**
  - New fields: `mode` (execution | planning), `spec_version`, `verification_cmd`, `progress.summary`, `progress.pct`
  - Backward compatible: old loop.json files load without errors
  - All fields documented in schema section of multica-workflow.md
  - loop.json validation on read checks required fields; fail-closed on corruption: exit 1, rename corrupted file to `loop.json.corrupt` (preserve for debugging), post `[loop-stuck]` comment with path to corrupted file; do not silently discard

**REQ-03-02: Phase Enumeration in Loop**
- **Description:** Track current and previous phase for resumption logic.
- **Priority:** P0 (resume support)
- **Affected Files:**
  - `skills/core/multica-workflow.md` (phase field)
  - `hooks/session-start.sh` (phase-based context injection)
- **Dependencies:** REQ-03-01, REQ-01-01 through REQ-01-06
- **Acceptance Criteria:**
  - loop.json.phase field set to current phase (spec | plan | demo | execute | verify | result | done)
  - Session start reads phase and injects appropriate context
  - Phase transitions use write-then-verify: write new phase to `loop.json.tmp` → post phase comment → only then rename `loop.json.tmp` → `loop.json`; if comment post fails, do not rename (retain prior phase); retry comment up to 3 times before aborting with `[loop-stuck]`

**REQ-03-03: Iteration Count & Exit-2 Loop Tracking**
- **Description:** Track iteration count and exit-2 occurrences within execute phase.
- **Priority:** P0 (loop detection)
- **Affected Files:**
  - `skills/core/multica-workflow.md` (iteration field semantics)
  - `hooks/stop.sh` (increment logic)
  - `tools/loop-status.sh` (status output)
- **Dependencies:** REQ-01-04
- **Acceptance Criteria:**
  - loop.json.iteration incremented on each exit-2 from execute phase
  - loop.json.max_iterations = 50 (hard cap; after 50 → set blocked + [loop-exhausted])
  - Secondary cap: 4 hours wall-clock elapsed (measured from `loop.json.start_time` against multica issue metadata timestamps, not local system clock) also triggers `[loop-exhausted]`
  - loop.json.exit2_triggers_per_session tracked for diagnostics (session-level counter; loop.json.iteration is lifetime counter)
  - Iteration counter resets to 0 on explicit human re-queue (operator must post `[retry]` comment; stop.sh detects and resets on next session start)
  - `[loop-exhausted]` comment documents last attempted iteration, failure reason, and human recovery instructions (post `[retry]` to reset and re-enqueue)

---

### **EPIC-04: Planning Session Mode & Squad Coordination** `[READY]`

*Enable multi-issue decomposition via planning sessions and squad leader coordination.*

**REQ-04-01: Planning Mode Detection & Activation**
- **Description:** Detect macro issues that require decomposition and enter planning mode instead of spec phase.
- **Priority:** P1 (squad enabler)
- **Affected Files:**
  - `skills/core/squad-leader-workflow.md` (planning mode section)
  - `hooks/session-start.sh` (mode detection logic)
  - `loop.json` schema (mode field)
- **Dependencies:** REQ-02-01, REQ-03-01
- **Acceptance Criteria:**
  - Issue title contains epic keywords (epic, initiative, roadmap) → enter planning mode
  - Planning mode: discover → explore codebase → post [breakdown:vN] comment → exit 0
  - User confirms breakdown via [proceed] or [revise:...] before child issues created
  - No implementation in planning mode; pure decomposition

**REQ-04-02: Breakdown Comment & Child Issue Creation**
- **Description:** Generate [breakdown:vN] comment with task decomposition tree; create child issues.
- **Priority:** P1 (squad structure)
- **Affected Files:**
  - `skills/core/squad-leader-workflow.md` (breakdown generation)
  - `docs/adr/` (ADR on child issue linking)
- **Dependencies:** REQ-04-01
- **Acceptance Criteria:**
  - [breakdown:vN] comment lists child issues with effort estimate, dependency graph
  - Child issues created via multica CLI after user approval
  - Parent issue links to children via `blocks:` metadata
  - Squad member assignment in child issue metadata (from issue.metadata or roster)

**REQ-04-03: Squad Member State Exchange via Issue Metadata**
- **Description:** Squad members exchange state via issue.metadata (no shared filesystem required).
- **Priority:** P1 (headless multi-machine support)
- **Affected Files:**
  - `skills/core/squad-member-workflow.md` (metadata protocol)
  - `docs/adr/squad-coordination.md` (metadata schema)
- **Dependencies:** REQ-04-01, REQ-04-02
- **Acceptance Criteria:**
  - Child issue carries `parent_id`, `epic_id`, `squad_id` in metadata
  - Member reads parent metadata to fetch leader roster and parent status
  - Member writes completion status to issue.metadata.member_status before marking done
  - Leader reads member statuses from child issue metadata to coordinate (no polling shared files)

**REQ-04-04: Squad Leader Activity Checkpoint**
- **Description:** Leader calls `<<cli:squad.activity>>` at every turn end to check member progress.
- **Priority:** P1 (coordination heartbeat)
- **Affected Files:**
  - `skills/core/squad-leader-workflow.md` (activity section)
  - `hooks/stop.sh` (activity call before session exit)
- **Dependencies:** REQ-04-01
- **Acceptance Criteria:**
  - Leader session end triggers `<<cli:squad.activity>>`
  - Activity call returns member status: in_progress, blocked, done
  - "Stuck" definition: member issue has no new exit-0 comment since last activity check; elapsed time sourced from issue comment timestamps (multica server time), not local system clock — avoids clock-skew false positives in multi-machine deployments
  - If any member stuck > 2 hours → post `[checkpoint]` with stuck member names; threshold configurable via `loop.json.squad_stuck_threshold_minutes` (default: 120)
  - If all children done → auto-transition to result phase

---

### **EPIC-05: Learning Pipeline & Automatic Correction Capture** `[READY]`

*Automatically capture [wrong:] and [revise:] signals as repo-scoped learnings without agent intervention.*

**REQ-05-01: Comment Signal → Learning Conversion**
- **Description:** When user posts [wrong:...] or [revise:...], automatically extract as learning without agent generating it.
- **Priority:** P1 (knowledge acceleration)
- **Affected Files:**
  - `hooks/stop.sh` (signal detection + conversion)
  - `.multica/learnings.jsonl` (storage)
  - `tools/curate-memory.sh` (dedup and decay)
- **Dependencies:** REQ-02-02, EPIC-05 foundation
- **Acceptance Criteria:**
  - On session exit, stop.sh scans issue comments for [wrong:...] or [revise:...]
  - Extract 5-10 most recent signals from the last 7 days; cutoff = UTC session-start timestamp recorded in `loop.json.start_time` minus 7×86400 seconds
  - Each signal → learning entry with confidence=9, scope=repo, `recorded_at`=UTC ISO-8601 timestamp (required field)
  - Atomic write: append entries to `.multica/learnings.jsonl.tmp`, then `flock`-protected rename to `.multica/learnings.jsonl`; prevents line interleaving if two squad members exit simultaneously
  - Dedup key = first 16 hex chars of `sha256(insight[:200])`; duplicate keys → keep highest-confidence entry (latest timestamp wins on tie)

**REQ-05-02: Session-Start Injection of Repo Learnings**
- **Description:** At session start, inject high-confidence learnings from repo-scoped store into context.
- **Priority:** P1 (knowledge carryover)
- **Affected Files:**
  - `hooks/session-start.sh` (learning load and injection)
  - `.multica/learnings.jsonl` (read)
- **Dependencies:** REQ-05-01
- **Acceptance Criteria:**
  - session-start reads repo learnings with confidence >= 7
  - Learnings injected into system context as "Previous corrections on this repo:"
  - Helps agent avoid repeat mistakes in similar tasks
  - Includes file paths touched (for relevance filtering)

**REQ-05-03: Workspace-Scoped Learnings Routing (Bug Fix)**
- **Description:** Fix workspace-scoped learnings routing; SCOPE_PY2 is currently a no-op shell script.
- **Priority:** P0 (bug fix)
- **Affected Files:**
  - `hooks/stop.sh` (workspace learning write path)
  - `tools/curate-memory.sh` (SCOPE_PY2 implementation)
- **Dependencies:** None (bug fix)
- **Acceptance Criteria:**
  - SCOPE_PY2 refers to the second `python3` subprocess in `hooks/stop.sh` responsible for workspace-scoped learning writes (locate the `python3` call following the `scope=workspace` branch in stop.sh)
  - Workspace learnings (scope=workspace) are persisted to workspace context field
  - stop.sh does not silent-fail on workspace-scoped learning writes
  - Cross-machine workspace agents inherit corrected learnings from workspace context
  - Error logs recorded if workspace context write fails

**REQ-05-04: Learnings Dedup & Confidence Decay**
- **Description:** Deduplicate and decay confidence of repeated learning entries over time.
- **Priority:** P2 (knowledge hygiene)
- **Affected Files:**
  - `tools/curate-memory.sh` (dedup + decay logic)
  - `hooks/stop.sh` (curate-memory invocation)
- **Dependencies:** REQ-05-01
- **Acceptance Criteria:**
  - curate-memory runs on every session end if .multica/learnings.jsonl exists
  - Decay computed from `recorded_at` field (required ISO-8601 field on every entry)
  - Duplicate keys → keep highest-confidence entry
  - Confidence decay: -1 per week since `recorded_at`; floor at 1 (entries never auto-removed by time alone)
  - Entries removed only when confidence < 4 AND no matching correction signal (same key) seen in the last 30 days
  - Recurrence reinforcement: if a `[wrong:]` or `[revise:]` signal matches an existing key, reset confidence to 9 and update `recorded_at`
  - Pruned entries logged to `.multica/curate-memory.log` as `[learning-pruned key=X confidence=Y]` before deletion (no silent removal)

---

### **EPIC-06: HITL Protocol Refinement** `[READY]`

*Improve human-in-the-loop signaling for reviewer clarity and agent handling of user responses.*

**REQ-06-01: HITL Format Specification & Structured Response**
- **Description:** Define HITL comment format with question_id, context, options; support unstructured user responses.
- **Priority:** P1 (HITL reliability)
- **Affected Files:**
  - `skills/core/hitl-protocol.md` (format spec)
  - `docs/HUMAN-GUIDE.md` (HITL guide for reviewers)
- **Dependencies:** REQ-02-01
- **Acceptance Criteria:**
  - HITL format: [HITL] question_id=<uuid>, **Question:** ..., **Context:** ..., **Options:** (optional), **To unblock:** ...
  - Agent detects question_id in user reply and updates loop.json.open_hitls with answered status
  - User response need not match exact A/B options; agent handles free-form text by re-raising HITL if unclear
  - HITL may escalate: member → leader (tier 1) → human (tier 2, after 3 bounces)
  - If human does not respond within 48 hours of a `[HITL:human]` post: set issue status to `blocked` with `[loop-stuck]` tag and post a timeout notice; prevents indefinite silent stalls

**REQ-06-02: Replay HITL Detection on Session Resume**
- **Description:** On session start, detect user's reply to open HITL questions without re-raising.
- **Priority:** P1 (session continuity)
- **Affected Files:**
  - `hooks/session-start.sh` (HITL detection on resume)
  - `skills/core/multica-workflow.md` (discover phase HITL handling)
- **Dependencies:** REQ-06-01
- **Acceptance Criteria:**
  - If loop.json.open_hitls exists, session-start fetches issue comments
  - Looks for user reply to each question_id in comment thread
  - Extracts answer text and injects into context for discover phase
  - Moves HITL from open_hitls to resolved_hitls with answer
  - Does not re-post HITL if answer already present

**REQ-06-03: Context-Budget Handoff (Internal Checkpoint Only)** `[READY]` *(correction applied 2026-06-09; implemented 2026-06-11)*
- **Description:** When context budget is near exhaustion, agent does a graceful handoff rather than setting blocked. Blocked requires on_comment to reactivate — wrong for an internal resource constraint.
- **Priority:** P2 (reviewer noise reduction)
- **Affected Files:**
  - `skills/core/multica-workflow.md` (context-budget checkpoint definition)
  - `hooks/session-start.sh` (context budget calculation)
- **Dependencies:** REQ-01-04, REQ-02-03
- **Correction:** Original draft said "context budget < 25% → set blocked". This is wrong in headless mode. `blocked` status waits for on_comment; context exhaustion is an internal resource limit, not a user decision point. Daemon has no mechanism to detect or act on context limits. The correct behavior is an automatic handoff: wrap up the current sub-step, persist state to loop.json, post a [checkpoint] comment with a note, and exit 0. The daemon relaunches a fresh session automatically (same issue, next sub-step picked up from loop.json.progress).
- **Acceptance Criteria (corrected):**
  - Context budget < 25% → agent wraps up current sub-step and exits with **exit 0** (not blocked)
  - Before exit: persist progress to `loop.json.progress` (current sub-step, completed steps list)
  - Post [checkpoint] comment: `[checkpoint] context-handoff | progress: X%`
  - On next session start: session-start.sh detects loop.json.progress and resumes from saved sub-step
  - Do NOT set status blocked; do NOT post HITL; no user action required

---

### **EPIC-07: Verification & Evidence Gate** `[READY]`

*Strengthen verification protocol with clearer evidence requirements and automatic test discovery.*

**REQ-07-01: Verification Command Discovery & Storage**
- **Description:** Extract verification command from issue description; store in loop.json for consistent re-runs.
- **Priority:** P1 (verification consistency)
- **Affected Files:**
  - `hooks/session-start.sh` (discover phase: parse issue description)
  - `loop.json` schema (verification_cmd field)
  - `skills/core/verification.md` (verification protocol)
- **Dependencies:** REQ-03-01
- **Acceptance Criteria:**
  - Issue description can include `[verification] command="npm test"` or similar
  - If found, stored in loop.json.verification_cmd
  - If not found, agent uses sensible defaults (npm test, pytest, cargo test, etc.)
  - Same verification command used across all verify attempts in same task
  - Verification command immutable once set (prevent muddying of signal)

**REQ-07-02: Evidence Artifact Collection**
- **Description:** Collect and hash test output; detect flaky failures vs. genuine errors.
- **Priority:** P2 (failure diagnosis)
- **Affected Files:**
  - `skills/core/verification.md` (evidence collection)
  - `hooks/stop.sh` (output hashing)
- **Dependencies:** REQ-07-01
- **Acceptance Criteria:**
  - Verification output hashed (first 8 chars of SHA256)
  - [verification] comment includes exit_code, command, output_hash
  - Output hash enables detecting flaky tests (same failure hash → likely environment issue, not code)
  - If exit code differs but output_hash same → log as flaky-suspect, allow retry

**REQ-07-03: Automatic Failure Categorization**
- **Description:** Categorize verification failures to guide agent troubleshooting.
- **Priority:** P2 (guided debugging)
- **Affected Files:**
  - `skills/core/verification.md` (failure categorization logic)
  - `hooks/stop.sh` (categorization on verify comment)
- **Dependencies:** REQ-07-01
- **Acceptance Criteria:**
  - Parse verification output for common error patterns (syntax, import, assertion, timeout, permission)
  - Inject categorization into [verification] comment (e.g., [verification] category=import)
  - Agent reads category in verify phase to guide next fix attempt
  - Helps prevent agent from blindly retrying same fix

---

### **EPIC-08: Destructive Guard & Safe-Exec Proxy Hardening** `[NEEDS-DISCUSSION]`

> **Blocked:** Requirements extrapolated without design discussion. Do not implement until discussed and approved.

*Prevent accidental destructive commands; provide audit trail for safe-exec decisions.*

**REQ-08-01: Allowlist vs. Deny-List Hybrid**
- **Description:** Extend safe-exec from simple deny-list to hybrid allowlist + deny-list.
- **Priority:** P2 (safety improvement)
- **Affected Files:**
  - `hooks/pre-tool.sh` (decision logic)
  - `tools/safe-exec.deny.list` (deny-list)
  - `tools/safe-exec.allow.list` (new allowlist)
- **Dependencies:** None (safety hardening)
- **Acceptance Criteria:**
  - Allowlist takes precedence (e.g., `rm /tmp/build/` is safe if in allowlist)
  - Deny-list catches bypass attempts (e.g., `find -delete`)
  - Both checked; deny-list wins if conflict
  - Hook logs all decisions to `.multica/safe-exec.log` (file, not stdout)

**REQ-08-02: Pattern-Based Bypass Detection**
- **Description:** Detect obfuscation attempts (double spaces, flag reordering, eval, heredocs).
- **Priority:** P2 (bypass prevention)
- **Affected Files:**
  - `hooks/pre-tool.sh` (pattern detection)
  - `docs/KNOWN-LIMITATIONS.md` (update disclaimer)
- **Dependencies:** REQ-08-01
- **Acceptance Criteria:**
  - Detect and reject: double spaces, eval, $(...), ```, <<EOF variants
  - Log rejected attempts to `.multica/safe-exec.log` with [BYPASS_ATTEMPT] tag
  - Set status blocked + post comment if bypass detected
  - Clarify in KNOWN-LIMITATIONS that this is convenience check, not security boundary

---

### **EPIC-09: Installation & Verification Tooling** `[NEEDS-DISCUSSION]`

> **Blocked:** Requirements extrapolated without design discussion. Do not implement until discussed and approved. Note: REQ-09-01 (--verify) and REQ-09-02 (auto shell profile) are partially implemented already in `bin/install.js`.

*Improve first-time setup experience and post-install health checks.*

**REQ-09-01: Installer Verification Sub-Command**
- **Description:** Add `install.sh --verify` to check installation success without re-running setup.
- **Priority:** P1 (installation UX)
- **Affected Files:**
  - `install.sh` (new --verify flag)
  - `tools/multica-plugin-doctor.sh` (new tool)
- **Dependencies:** None (installation improvement)
- **Acceptance Criteria:**
  - `bash install.sh --verify` checks:
    - `multica` CLI present and >= 0.4.0
    - `~/.claude/hooks/multica/*.sh` exist and are executable
    - MULTICA_PLUGIN_ROOT exported in shell profile
    - `.claude/settings.json` contains hook registrations
  - Prints PASS/FAIL for each check
  - Exits 0 if all checks pass, 1 if any fail
  - Provides remediation steps for each failure

**REQ-09-02: Automatic Shell Profile Update**
- **Description:** Offer installer option to auto-add MULTICA_PLUGIN_ROOT to shell profile.
- **Priority:** P2 (installation ease)
- **Affected Files:**
  - `install.sh` (new --auto-profile flag)
  - `tools/install-shell-profile.sh` (new helper)
- **Dependencies:** REQ-09-01
- **Acceptance Criteria:**
  - `bash install.sh --auto-profile` detects shell (bash/zsh/fish)
  - Appends MULTICA_PLUGIN_ROOT export to appropriate profile file
  - Creates backup of profile before modification (.bak)
  - Warns user to restart shell or source profile

**REQ-09-03: Health Check Log on Install**
- **Description:** Post-installation, generate `.multica/install-health.json` with setup diagnostics.
- **Priority:** P1 (installation transparency)
- **Affected Files:**
  - `install.sh` (health check generation)
  - `tools/multica-plugin-doctor.sh` (health reporter)
- **Dependencies:** REQ-09-01
- **Acceptance Criteria:**
  - install-health.json logs: timestamp, OS, shell, multica version, python3 version, git version
  - Logs success/failure of each install step
  - If any step fails, detailed error message and remediation link
  - Used by --verify command to diagnose installation problems
  - Also logged to user's terminal for immediate visibility

**REQ-09-04: Daemon Deployment Mode Detection**
- **Description:** Detect if running in daemon mode and adjust installation/verification steps accordingly.
- **Priority:** P2 (daemon-first mindset)
- **Affected Files:**
  - `install.sh` (daemon detection)
  - `hooks/session-start.sh` (MULTICA_AGENT_SESSION env var check)
  - `docs/QUICKSTART.md` (daemon setup section)
- **Dependencies:** REQ-09-01
- **Acceptance Criteria:**
  - If MULTICA_AGENT_SESSION=1 or $MULTICA_WORKDIR present → assume daemon mode
  - Skip "Restart Claude Code" instruction for daemon deployments
  - Warn daemon deployers that MULTICA_PLUGIN_ROOT must be set in daemon startup env
  - Provide example systemd unit file or deployment guide

---

### **EPIC-10: Documentation & Reviewer Experience** `[NEEDS-DISCUSSION]`

> **Blocked:** Requirements extrapolated without design discussion. Do not implement until discussed and approved.

*Improve guides and comment trails for human reviewers and operators.*

**REQ-10-01: Human-Guide Phase Annotation**
- **Description:** Update HUMAN-GUIDE.md with phase state machine and reviewer navigation guide.
- **Priority:** P1 (reviewer clarity)
- **Affected Files:**
  - `docs/HUMAN-GUIDE.md` (new "For Reviewers" section)
  - `docs/adr/reviewer-mental-model.md` (new ADR)
- **Dependencies:** REQ-01-01 through REQ-01-06, REQ-02-03
- **Acceptance Criteria:**
  - Add state machine diagram (text or ASCII)
  - Explain each phase in 2-3 sentences for non-agent audiences
  - List expected comment markers for each phase
  - Troubleshooting table: "You see [marker] → phase is X → expected next action is Y"
  - Include example comment trail (full issue walkthrough)

**REQ-10-02: Operator Observability Guide**
- **Description:** Guide operators (squad leads, tech leads) on monitoring agent health and intervention points.
- **Priority:** P2 (squad ops)
- **Affected Files:**
  - `docs/HUMAN-GUIDE.md` (new "For Operators" section)
  - `docs/adr/operator-interventions.md` (new ADR)
- **Dependencies:** EPIC-04, REQ-06-03
- **Acceptance Criteria:**
  - Explain loop.json status, phase, iteration fields for health diagnosis
  - Document when to intervene: agent stuck (iteration > threshold), member blocked, context budget critical
  - Provide `tools/loop-status.sh` usage examples
  - Squad leader checklist: what to check when member is stuck

**REQ-10-03: Comment Trail Best Practices**
- **Description:** Document how agents should format comments to aid reviewer comprehension.
- **Priority:** P2 (readability)
- **Affected Files:**
  - `docs/HUMAN-GUIDE.md` (comment format guide)
  - `skills/core/multica-workflow.md` (comment emission rules)
- **Dependencies:** REQ-02-01, REQ-02-03
- **Acceptance Criteria:**
  - Rule: one signal per comment line (no bundling)
  - Rule: [phase] marker on transitions, [checkpoint] for internal progress, [verification] for test results
  - Rule: [HITL] for blocking questions; [result] for final summary
  - Rule: no @mention in completion comments (avoid double-fire)
  - Example: before/after bad comments vs. good comments

**REQ-10-04: Quickstart with Real Example**
- **Description:** Add end-to-end example in docs showing a complete 7-phase workflow.
- **Priority:** P2 (first-time user)
- **Affected Files:**
  - `docs/QUICKSTART.md` (new "Example: Full Workflow" section)
  - `.omc/sessions/` (saved example session for reference)
- **Dependencies:** All EPIC-01 through EPIC-06 requirements
- **Acceptance Criteria:**
  - Example issue: "Add login endpoint to auth module"
  - Show actual comment trail from spec through done
  - Explain each phase transition and user action
  - Include example [revise:...] signal and resulting learning capture
  - Reproducible: reader can trace through example in < 10 minutes

---

## Dependency Graph (Text Format)

```
EPIC-01 (Multi-Session Phase Architecture)
├── REQ-01-01: spec phase
│   └── DEPENDS: REQ-02-01 (comment protocol)
├── REQ-01-02: plan phase
│   └── DEPENDS: REQ-01-01
├── REQ-01-03: demo phase
│   └── DEPENDS: REQ-01-02
├── REQ-01-04: execute phase exit-2
│   └── DEPENDS: REQ-01-03
├── REQ-01-05: verify phase
│   └── DEPENDS: REQ-01-04
└── REQ-01-06: result phase
    └── DEPENDS: REQ-01-05

EPIC-02 (Comment Protocol)
├── REQ-02-01: agent signals [spec:vN], [demo:vN], [checkpoint], [result], etc.
│   └── DEPENDS: (foundation)
├── REQ-02-02: user response signals [proceed], [revise:...], [wrong:...], etc.
│   └── DEPENDS: REQ-02-01
└── REQ-02-03: phase transition markers
    └── DEPENDS: REQ-02-01

EPIC-03 (loop.json Schema)
├── REQ-03-01: core fields (mode, spec_version, verification_cmd, progress)
│   └── DEPENDS: (foundation)
├── REQ-03-02: phase field
│   └── DEPENDS: REQ-03-01, EPIC-01
└── REQ-03-03: iteration count
    └── DEPENDS: REQ-03-01, REQ-01-04

EPIC-04 (Planning & Squad)
├── REQ-04-01: planning mode
│   └── DEPENDS: REQ-02-01, REQ-03-01
├── REQ-04-02: breakdown comment & child issues
│   └── DEPENDS: REQ-04-01
├── REQ-04-03: squad metadata protocol
│   └── DEPENDS: REQ-04-01, REQ-04-02
└── REQ-04-04: squad activity checkpoint
    └── DEPENDS: REQ-04-01

EPIC-05 (Learning Pipeline)
├── REQ-05-01: [wrong:] / [revise:] → learning conversion
│   └── DEPENDS: REQ-02-02
├── REQ-05-02: session-start learning injection
│   └── DEPENDS: REQ-05-01
├── REQ-05-03: workspace learnings fix
│   └── DEPENDS: (bug fix, no prereq)
└── REQ-05-04: dedup & confidence decay
    └── DEPENDS: REQ-05-01

EPIC-06 (HITL Refinement)
├── REQ-06-01: HITL format & structured response
│   └── DEPENDS: REQ-02-01
├── REQ-06-02: HITL replay on resume
│   └── DEPENDS: REQ-06-01
└── REQ-06-03: context-budget checkpoint
    └── DEPENDS: REQ-01-04, REQ-02-03

EPIC-07 (Verification & Evidence)
├── REQ-07-01: verification command discovery
│   └── DEPENDS: REQ-03-01
├── REQ-07-02: evidence artifact collection
│   └── DEPENDS: REQ-07-01
└── REQ-07-03: failure categorization
    └── DEPENDS: REQ-07-01

EPIC-08 (Safe-Exec Hardening)
├── REQ-08-01: allowlist + deny-list hybrid
│   └── DEPENDS: (foundation)
└── REQ-08-02: bypass pattern detection
    └── DEPENDS: REQ-08-01

EPIC-09 (Installation & Verification)
├── REQ-09-01: installer --verify
│   └── DEPENDS: (foundation)
├── REQ-09-02: auto shell profile
│   └── DEPENDS: REQ-09-01
├── REQ-09-03: install health log
│   └── DEPENDS: REQ-09-01
└── REQ-09-04: daemon mode detection
    └── DEPENDS: REQ-09-01

EPIC-10 (Documentation)
├── REQ-10-01: reviewer guide
│   └── DEPENDS: EPIC-01, REQ-02-03
├── REQ-10-02: operator guide
│   └── DEPENDS: EPIC-04, REQ-06-03
├── REQ-10-03: comment best practices
│   └── DEPENDS: REQ-02-01, REQ-02-03
└── REQ-10-04: quickstart example
    └── DEPENDS: EPIC-01 through EPIC-06
```

## Critical Path

The minimum viable set of requirements to unblock dependent work (READY epics only):

1. **EPIC-02, REQ-02-01** — Comment protocol (foundation; unblocks EPIC-01)
2. **EPIC-03, REQ-03-01 through REQ-03-03** — loop.json schema (state persistence; unblocks EPIC-01)
3. **EPIC-01, REQ-01-01 through REQ-01-06** — Seven-phase workflow (primary architecture)
4. **EPIC-05, REQ-05-03** — Workspace learnings bug fix (P0; no prereqs)
5. **EPIC-05, REQ-05-01 through REQ-05-02** — Learning pipeline (depends on EPIC-02)
6. **EPIC-06, REQ-06-01 through REQ-06-02** — HITL refinement (depends on EPIC-02)
7. **EPIC-07, REQ-07-01 through REQ-07-02** — Verification & evidence (depends on EPIC-03)

EPIC-04 (Planning & Squad), EPIC-06 REQ-06-03 (after correction), EPIC-07 REQ-07-03 are high-value follow-ons.

EPIC-08, EPIC-09, EPIC-10 are **blocked pending design discussion** and excluded from this critical path.

---

## Priority Distribution

| Priority | Count | Rationale |
|----------|-------|-----------|
| **P0** | 18 | Architectural foundation (phases, loops, schema, learning routing) |
| **P1** | 17 | Core user value (comment protocol, planning, HITL, verification, installer) |
| **P2** | 9 | Quality & experience (dedup, bypass detection, guide, examples) |

---

## Out of Scope (Not This Release)

- Changes to multica daemon itself (constraint: plugin-only modifications)
- Harness adapters for Codex, Cursor, Gemini (v0.6.0+)
- Server-side knowledge API (planned for multica 0.5.0)
- Automatic code review / linting (covered by `skills/advanced/parallel-exec.md`)
- Squad member auto-routing (manual roster in CLAUDE.md for now)

---

## Acceptance Criteria (Release Gate)

Release v2.3.0 only when:

1. All P0 requirements (18) have passing acceptance tests
2. All P1 requirements (17) have passing acceptance tests
3. Comment trail of 3 real-world example issues validates workflow end-to-end
4. Documentation (EPIC-10) is reviewed by non-author
5. Backward compatibility: v2.2.0 loop.json files load without errors
6. No regressions in existing v2.2.0 smoke tests (tests/smoke/run-claude.sh)

---

## Version & Timeline

| Milestone | Target | Artifacts |
|-----------|--------|-----------|
| Design review | 2026-06-14 | This document + ADRs |
| Implementation start | 2026-06-21 | Task breakdown |
| Alpha (internal) | 2026-07-31 | All P0 + P1 complete |
| Beta (closed) | 2026-08-21 | All requirements complete + docs |
| GA (v2.3.0) | 2026-09-07 | Release tag + CHANGELOG |

---

## Change Log & History

- **2026-06-07** — Initial requirements document created from design discussion
- **2026-06-07** — Added discussion status tags (`[READY]`, `[NEEDS-DISCUSSION]`, `[CORRECTION-NEEDED]`); EPIC-08/09/10 blocked pending discussion; REQ-06-03 acceptance criteria corrected (exit 0 handoff, not blocked)
- **2026-06-09** — Review remediation: clarified verify-phase escape-hatch ordering (REQ-01-05); added 72h result-phase timeout (REQ-01-06); specified fail-closed corruption handling (REQ-03-01); replaced "atomic" with write-then-verify rename pattern (REQ-03-02); added time cap, re-queue reset, and recovery instructions for iteration cap (REQ-03-03); specified stuck-detection clock source and configurable threshold (REQ-04-04); defined dedup key, atomic write, and 7-day cutoff anchor (REQ-05-01); added SCOPE_PY2 cross-reference (REQ-05-03); hardened decay with recurrence reinforcement and no-silent-removal (REQ-05-04); added 48h HITL human-timeout escape hatch (REQ-06-01); fixed phase table separators; updated document date
