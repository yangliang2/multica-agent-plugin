# multica-agent-plugin Usage Guide

> Version: 0.4.0

Sections 1–2 are for **humans**. Sections 3–4 are for **agents** running inside the
Multica daemon — they are normative operating contracts. Section 5 covers troubleshooting
for both audiences.

---

## 1. For Humans: Setup & Configuration

### Prerequisites

| Requirement | Notes |
|-------------|-------|
| `multica` CLI | `multica --help` must exit 0 |
| `git` 2.x | Required for learnings sync (stop hook) |
| `python3` 3.8+ | Required for install JSON merge and staleness detection |
| Claude Code | Any current release; hooks registered into its settings.json |

### Installation

```bash
git clone https://github.com/your-org/multica-agent-plugin.git
cd multica-agent-plugin
bash install.sh
```

`install.sh` verifies the `multica` CLI is present, merges `hooks/hooks.json` into
`~/.claude/settings.json` (or `$CLAUDE_SETTINGS_PATH`) using Python's `json` module
(existing hooks are preserved; duplicates are skipped), and prints a reminder to export
`MULTICA_PLUGIN_ROOT`.

### MULTICA_PLUGIN_ROOT

Add to your shell profile after installation:

```bash
export MULTICA_PLUGIN_ROOT="/absolute/path/to/multica-agent-plugin"
```

Without this variable the hooks cannot locate skills or model routing configuration.

### Hooks Registered

`install.sh` adds three entries to `~/.claude/settings.json`:

| Event | Script | Notes |
|-------|--------|-------|
| `Stop` | `hooks/stop.sh` | Completion gate, learnings git-commit, Working Memory prune |
| `PreToolUse` | `hooks/pre-tool.sh` | Safe-exec proxy for destructive CLI calls |
| `SessionStart` | `hooks/session-start.sh` | Context injection; fires on `startup\|clear\|compact` |

### .multica/ Directory

The plugin reads/writes `.multica/` at `$MULTICA_WORKDIR` (defaults to cwd). The daemon
is expected to create this directory before spawning an agent.

**notepad.md** has three named sections:

- `## Priority Context` — ≤500 chars, loaded at every session start, auto-replaced on update.
- `## Working Memory` — timestamped entries `[YYYY-MM-DDTHH:MM:SSZ] …`; auto-pruned after 7 days by `stop.sh`.
- `## Manual Notes` — permanent, never auto-pruned; use for architecture rationale.

### Verifying the Installation

```bash
bash tests/smoke/run-claude.sh
```

Expected output: `PASS: N  FAIL: 0` across all 10 scenarios. No live daemon or Claude
session is required.

---

## 2. For Humans: Feature Overview

### Verification Iron Law
Agents cannot claim completion without running fresh verification commands in the same
turn and writing a `[verification] exit_code=N command="…"` comment. Trigger: every
phase transition that asserts success. No configuration required.

### PRD Story Tracking
Complex tasks are decomposed into user stories in `.multica/state/<id>/loop.json`; the
session resumes mid-story after restart. `stop.sh` blocks termination until the agent
emits `<promise>DONE</promise>` with all stories passing. Hard cap: 50 iterations
(after which the issue is set `blocked`). No user configuration required.

### HITL Protocol
When an agent cannot proceed (ambiguity, missing credential, 3-strike failure), it writes
a `[HITL] question_id=<uuid>` comment, sets status `blocked`, and exits. The daemon
reawakens it on the next `on_comment` event. Timeouts are the daemon reaper's responsibility,
not the plugin's.

### Squad Coordination
When the daemon writes a `## Squad Operating Protocol` section into `CLAUDE.md`, the
session-start hook injects the leader role and squad roster into context. The leader
delegates via child issues (parallel) or @mention (serial) and must call
`multica squad activity` each turn. Members use a two-tier HITL: escalate to leader
first, escalate to human after 3 bounces on the same `question_id`.

### Subagent Dispatch
Agents spawn specialist subagents (executor, code-reviewer, debugger) using model routing
injected by `session-start.sh` as `$MULTICA_MODEL_FAST/STD/DEEP`. Each subagent prompt
must be self-contained — no shared session history. Results write to
`.multica/state/<id>/subagent-<task_id>.md` or an issue comment.

### Knowledge Management
Learnings accumulate in `.multica/learnings.jsonl`. Session-start loads the 10 most
recent entries plus all with `confidence >= 7`, marking entries whose source files have
changed as `[possibly stale]`. `stop.sh` git-commits the file on DONE for cross-machine
sync. `tools/curate-memory.sh` deduplicates (last-wins per key) and applies confidence
decay (>90 days: −2; >180 days: −4; archived when confidence < 3).

### Context Budget
`multica-workflow` enforces: ≤35% remaining → write checkpoint comment before new
complex work; ≤25% → checkpoint + set `blocked` (reason: `context-budget-critical`).

---

## 3. For Agents: Operating Contract

> MUST/SHOULD/MAY have RFC 2119 meaning throughout this section.

### Environment Assumptions

- No human is at the keyboard. `AskUserQuestion` is **disabled**.
- Issue comments are the sole authoritative communication channel.
- The daemon reaper owns all timeouts. The agent MUST NOT implement its own.
- `$MULTICA_WORKDIR` is the workspace root; `$MULTICA_ISSUE_ID` is the current issue.

### Iron Laws

**Law 1 — Verify before claiming done.**
Run the verification command in the current turn; write `[verification]` evidence to a
comment; only then set status `done` or emit `<promise>DONE</promise>`.
*Why: unverified claims cause rework cascades.*

**Law 2 — All communication is written.**
Write all progress, questions, and results via `<<cli:issue.comment.add>>` only.
*Why: the daemon reactivates from issue state alone; anything not in the issue is lost.*

**Law 3 — Status drives the process.**
Call `<<cli:issue.status>>` at every phase transition. After setting `blocked`, EXIT IMMEDIATELY.
*Why: the daemon polls status to decide reap vs. reactivate.*

### Issue Lifecycle State Machine

```
[assigned / on_comment]
        │
        ▼
    discover ──── HITL needed immediately ──► report → blocked
        │ requirements clear
        ▼
      plan  (post plan comment; set in_progress)
        │
        ▼
    execute ◄── fix ◄──────────────────┐
        │                              │ fail, attempts < 3
        ▼                              │
     verify ───────────────────────────┘
        │ pass
        ▼
     report ──► done (success)  |  blocked (HITL)
```

**Phase decision table:**

| Phase | Condition | Next |
|-------|-----------|------|
| discover | Requirements clear | plan |
| discover | Blocking unknown | report → blocked |
| execute | Ambiguity / missing credential | report → blocked |
| verify | Pass | report → done |
| verify | Fail, attempts < 3 | execute (fix) |
| verify | 3-strike failure | report → blocked |
| verify | Context ≤ 25% | report → blocked (`context-budget-critical`) |

### Completion Signal

Emit this exact string in stdout to signal the stop hook:

```
<promise>DONE</promise>
```

Emit ONLY when all stories have `passes: true` AND the reviewer has approved.
The stop hook cross-checks `loop.json`; speculative emission is detected and blocked.

### HITL Triggers and Format

**Trigger (any one sufficient):** 2+ mutually exclusive options not resolvable from issue
text; required credential absent; 3+ failed fix attempts before a destructive step;
task explicitly requires human sign-off.

**Do NOT trigger for:** transient errors (retry ≤3×), style ambiguities with a sensible
default, issues resolvable by re-reading comments.

**Comment format:**

```
[HITL] question_id=<uuid-v4>

**Question:** <one clear sentence>

**Context:**
<2-5 sentences: what the agent was doing, what it found, why it is blocked>

**Options (if applicable):**
- Option A: <description and trade-off>
- Option B: <description and trade-off>

**To unblock:** Reply with your choice or the missing information.
```

In squad context use `[HITL:leader]` (member → leader, default) or `[HITL:human]`
(after 3 bounces on the same `question_id`, or no leader in roster).

After writing the HITL comment: `<<cli:issue.status>> blocked` → EXIT IMMEDIATELY.

### Prohibited Actions

1. **No `AskUserQuestion` or interactive prompt.** Agent runs headless; the call hangs indefinitely.
2. **No self-implemented timeouts** (sleep, poll loop, cron). Daemon reaper is the sole owner.
3. **No @mention in a completion comment.** @mention re-triggers the mentioned agent (double-fire).
4. **No open locks or connections across a `blocked` exit.** The process exits; unreleased locks deadlock the next invocation.
5. **No non-atomic writes to `loop.json`.** Use mktemp + rename. The stop hook may fire concurrently.

---

## 4. For Agents: Skill Reference

### multica-workflow
**Trigger:** Every agent invocation — primary operating contract.
**Effect:** Governs the 5-phase lifecycle, CLI calls per phase, context budget thresholds, daemon-safe rules.
**Prohibited:** Sleeping, polling, emitting `<promise>DONE</promise>` before all criteria verified.
**See:** `skills/core/multica-workflow.md`

### hitl-protocol
**Trigger:** Any qualifying HITL condition (see Section 3).
**Preconditions:** At least one qualifying condition is true; transient errors do not qualify.
**Effect:** Posts `[HITL] question_id=<uuid>` comment, sets `blocked`, exits. On resume, locates reply in Phase 1 discover.
**Prohibited:** Re-raising an already-answered `question_id`. Posting duplicate HITL when restarted in `blocked` state.
**See:** `skills/core/hitl-protocol.md`

### verification
**Trigger:** Before any claim of completion, story pass, or phase success.
**Effect:** Runs verification command; reads exit code; writes `[verification] exit_code=N command="…" output_hash=<8-hex>` comment; proceeds only on exit 0.
**Prohibited:** Cached results, inference, partial checks, "should work" language.
**See:** `skills/core/verification.md`

### systematic-debug
**Trigger:** A failure requires investigation before a fix can be proposed.
**Effect:** Four phases: (1) root cause — read errors fully, reproduce, instrument boundaries; (2) pattern analysis — find working examples, list differences; (3) single hypothesis + minimum change; (4) failing-test-first implementation. All evidence in issue comments. After 3 failed attempts: write `[HITL]`, set `blocked`, exit.
**Prohibited:** Proposing a fix before Phase 1 is complete. Bundling multiple fixes. Fourth attempt after 3 failures.
**See:** `skills/core/systematic-debug.md`

### persistence-loop
**Trigger:** Task requires guaranteed completion across iterations/restarts with verifiable acceptance criteria.
**Preconditions:** Stories have specific, testable acceptance criteria (generic criteria are forbidden).
**Effect:** Manages `loop.json` story state. After all stories pass: runs deslop pass (removes redundant comments, dead code, over-defensive guards), dispatches reviewer subagent, outputs `<promise>DONE</promise>` on approval. On `max_iterations`: sets `blocked`.
**Prohibited:** Marking `passes: true` without fresh evidence. Emitting DONE before reviewer approval. Non-atomic `loop.json` writes.
**See:** `skills/advanced/persistence-loop.md`

### parallel-exec
**Trigger:** 2+ independent implementation tasks that benefit from isolated fresh context.
**Effect:** Dispatches one subagent per task. Enforces two-stage review: (1) spec compliance — satisfies every requirement; (2) code quality — safe to ship. Both must pass before marking complete. Final opus review checks cross-task interactions.
**Prohibited:** Skipping Stage 1. Pausing between tasks for confirmation. Marking complete with outstanding reviewer items.
**See:** `skills/advanced/parallel-exec.md`

### subagent-dispatch
**Trigger:** Delegating work to a specialist (executor, code-reviewer, debugger) with isolated context.
**Preconditions:** `$MULTICA_MODEL_FAST/STD/DEEP` injected by session-start (falls back to haiku/sonnet/opus).
**Effect:** Dispatches `Task()` with model from routing table: mechanical → FAST, integration/judgment → STD, architecture/review/security → DEEP. Each prompt is complete and self-contained. Results to `.multica/state/<id>/subagent-<task_id>.md` or issue comment.
**Prohibited:** Passing orchestrator session history to a subagent. Relying on return values as the result.
**See:** `skills/advanced/subagent-dispatch.md`

### squad-leader-workflow
**Trigger:** `## Squad Operating Protocol` detected in `${MULTICA_WORKDIR}/CLAUDE.md` at session start.
**Preconditions:** `## Squad Roster` section present with parseable `[@Name](mention://agent/<uuid>)` links.
**Effect:** Delegates via Strategy A (child issue, parallel) or Strategy B (@mention, serial) — never implements directly. Every turn ends with `<<cli:squad.activity>>` and writes `squad-activity.marker`. On `[HITL:leader]` from member: replies without @mention link. After 3 bounces on same `question_id`: escalates to `[HITL:human]`.
**Prohibited:** Implementing code directly. Using A + B for the same work unit. @mention in replies to member HITL. Ending a turn without calling `squad.activity`.
**See:** `skills/core/squad-leader-workflow.md` *(squad leaders only)*

### squad-member-workflow
**Trigger:** `on_comment` event delivers an @mention from the squad leader.
**Preconditions:** Leader delegation comment is readable; task, constraints, and dependencies are unambiguous.
**Effect:** Standard 5-phase workflow scoped to the delegated subtask. HITL is two-tier: Tier 1 → `[HITL:leader]` with leader @mention; Tier 2 → `[HITL:human]` after 3 bounces (or no leader). Bounce count in `.multica/state/<id>/hitl-bounces.json`. Completion comment uses plain text only — no @mention links.
**Prohibited:** Skipping Tier 1 before 3 bounces. @mention of leader in completion comment. Claiming completion without fresh verification.
**See:** `skills/core/squad-member-workflow.md` *(squad members only)*

---

## 5. For Both: Troubleshooting

**1. Agent reported completion but issue status did not change.**
The agent did not call `<<cli:issue.status>> done` or the call failed silently.
Fix: `multica issue status <id> done`. Verify the final comment includes a `[verification]` block.

**2. Persistence loop stuck — no iteration progress across restarts.**
Possible causes: `loop.json` mtime is < 60 s old when `stop.sh` fires (throttle); a story
has not passed verification; issue is `blocked` awaiting a human reply.
Fix: read `loop.json` to find current phase and next story; check comments for
`[HITL]`/`[checkpoint]` entries. If stuck at `max_iterations`, set `"active": false` manually
and re-enqueue via `multica issue rerun <id>`.

**3. Squad activity not recorded — audit warning present.**
The squad leader ended its turn without calling `multica squad activity`. `stop.sh` called
`multica squad activity <id> failed` automatically.
Fix: check whether `MULTICA_PLUGIN_ROOT` is set and the `SessionStart` hook fires. Re-enqueue
the issue if the session terminated abnormally.

**4. Learnings disappeared after moving to a new machine.**
`stop.sh` only commits `learnings.jsonl` on the DONE path; mid-task sessions are not committed.
The workspace must be a git repository.
Fix: on the source machine run `git add .multica/learnings.jsonl && git commit -m "chore(knowledge): manual learnings sync" && git push`, then `git pull` on the target.

**5. Scenario 4 smoke test fails (SHA-256 mismatch).**
`docs/cli-reference.md` was updated without regenerating the lock, or the `multica` binary
was upgraded.
Fix: `bash tools/refresh-cli-reference.sh`, then re-run the smoke test.
