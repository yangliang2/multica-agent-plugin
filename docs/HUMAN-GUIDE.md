# multica-agent-plugin — Human Guide

Audience: operators, developers, and issue reviewers.

---

## §1 Setup & Configuration

### Prerequisites

| Requirement | Notes |
|-------------|-------|
| `multica` CLI | `multica --help` must exit 0 |
| `git` 2.x | Required for learnings sync (stop hook) |
| `python3` 3.8+ | Required for install JSON merge and staleness detection |
| Claude Code | Any current release; hooks registered into its settings.json |

### Installation

```bash
npx github:yangliang2/multica-agent-plugin
```

The installer verifies the `multica` CLI is present, copies hooks to
`~/.claude/hooks/multica/`, merges hook registrations into `~/.claude/settings.json`
(existing hooks are preserved; duplicates are skipped), and writes
`MULTICA_PLUGIN_ROOT` to your shell profile automatically.

To verify the installation:

```bash
npx github:yangliang2/multica-agent-plugin --verify
```

`MULTICA_PLUGIN_ROOT` is managed by the installer and does not need to be exported
manually. You may set it explicitly to override the default (e.g. in daemon
environments with a non-standard install path).

### Hooks Registered

The installer adds three entries to `~/.claude/settings.json` pointing to stable
paths under `~/.claude/hooks/multica/`:

| Event | Script | Notes |
|-------|--------|-------|
| `Stop` | `~/.claude/hooks/multica/stop.sh` | Completion gate, learnings git-commit, Working Memory prune |
| `PreToolUse` | `~/.claude/hooks/multica/pre-tool.sh` | Safe-exec proxy for destructive CLI calls |
| `SessionStart` | `~/.claude/hooks/multica/session-start.sh` | Context injection; fires on `startup\|clear\|compact` |

Hooks are installed to `~/.claude/hooks/multica/`, which is decoupled from the
plugin directory. Moving or updating the plugin does not break registered hooks.

### .multica/ Directory

The plugin reads/writes `.multica/` at `$MULTICA_WORKDIR` (defaults to cwd). The
daemon is expected to create this directory before spawning an agent.

`notepad.md` has three named sections:

- `## Priority Context` — ≤500 chars, loaded at every session start, auto-replaced on update.
- `## Working Memory` — timestamped entries `[YYYY-MM-DDTHH:MM:SSZ] …`; auto-pruned after 7 days by `stop.sh`.
- `## Manual Notes` — permanent, never auto-pruned; use for architecture rationale.

---

## §2 Comment Protocol

Agents and humans communicate through structured comment signals. This section defines the full signal grammar.

### Agent to User signals

The agent posts these signals to mark lifecycle events and request user action:

| Signal | When posted | Expected user response |
|--------|-------------|----------------------|
| `[spec:vN]` | End of spec phase | `[proceed]` or `[revise: <feedback>]` |
| `[demo:vN]` | End of demo phase | `[looks-right]` or `[wrong: <feedback>]` |
| `[result]` | End of result phase | Confirmation or `[abort]` |
| `[breakdown:vN]` | End of planning mode decomposition | `[proceed]` or `[revise: <feedback>]` |
| `[checkpoint:N]` | Execute phase iteration count (posted at 5+) | No action needed |
| `[verification]` | End of verify phase | No action needed |
| `[loop-exhausted]` | Execute hit 50-iteration cap | Human intervention required |
| `[loop-stuck]` | Same failure 3+ times | Human intervention required |
| `[phase] src→target` | Phase transition marker | No action needed |

### User to Agent signals

Post these in issue comments to steer the agent:

| Signal | Meaning |
|--------|---------|
| `[proceed]` | Approve current spec/demo/breakdown; agent continues to next phase |
| `[revise: <feedback>]` | Reject and revise; agent regenerates with feedback |
| `[looks-right]` | Approve demo; agent continues to execute phase |
| `[wrong: <feedback>]` | Demo is wrong; agent fixes and reposts |
| `[abort]` | Stop the task; agent sets status blocked and exits |
| `[retry]` | Retry the current phase from scratch |
| `[approve:task-x]` | Approve a specific sub-task in a breakdown |
| `[skip:story-x]` | Skip a specific story in a breakdown |

### Rules

- One signal per comment line; do not bundle multiple signals on one line.
- `vN` increments each time the agent regenerates (v1, v2, v3…).
- `[wrong:]` and `[revise:]` signals are automatically captured as repo-scoped learnings (confidence=9).
- Do not @mention the agent in response comments — it triggers off `on_comment` automatically.
- `[HITL]` is a separate signal prefix used only by the HITL protocol; it is not part of the phase signal grammar above.

### Good vs bad comments (REQ-10-03)

Agents follow these rules so reviewers can scan the timeline; humans benefit from
the same discipline:

| ✗ Bad | ✓ Good | Why |
|-------|--------|-----|
| `[proceed] [skip:story-2]` on one line | Two comments, one signal each | Parsers and humans read line-by-line |
| `Looks good but fix the header [looks-right]` | `[wrong: fix the header]` | A signal must match the actual intent — "looks-right plus a fix" is `[wrong:]` |
| `[revise]` with feedback in a later comment | `[revise: move auth to middleware]` | The feedback inside the brackets is what becomes the learning |
| Agent: `Done! @Reviewer please check` | Agent: `[result] Implemented X. Evidence: ...` | @mentions double-fire `on_comment`; signals carry the state |
| Agent: bare `tests pass` | Agent: `[verification] exit_code=0 command="npm test" output_hash=...` | Claims need machine-checkable evidence |

---

## §3 Feature Overview

### Verification Iron Law

Agents cannot claim completion without running fresh verification commands in the
same turn and writing a `[verification] exit_code=N command="…"` comment.

**You will see:** A `[verification]` comment block before any status change to `done`.
If you don't see one, the completion should be treated as suspect.

### PRD Story Tracking

Complex tasks are decomposed into user stories in `.multica/state/<id>/loop.json`;
the session resumes mid-story after restart. `stop.sh` blocks termination until the
agent emits `<promise>DONE</promise>` with all stories passing. Hard cap: 50
iterations (after which the issue is set `blocked`).

**You will see:** `[checkpoint]` comments periodically as the agent progresses through
stories, and a `[loop-complete]` comment when all stories pass.

### HITL Protocol

When an agent cannot proceed (ambiguity, missing credential, 3-strike failure), it
writes a `[HITL] question_id=<uuid>` comment, sets status `blocked`, and exits. The
daemon reawakens it on the next `on_comment` event.

**You will see:** A `[HITL]` comment with a clear question and options. Reply directly
to that comment with your answer — no special format required. Free-form answers are
fine: on the next session the agent automatically matches your reply to the question
(by thread or by `question_id`) and proceeds without re-asking. If no human reply
arrives within 48 hours, the agent posts a `[loop-stuck]` timeout notice and the
issue stays `blocked` until you respond.

### Squad Coordination

When a `## Squad Operating Protocol` section is present in `CLAUDE.md`, the
session-start hook injects the leader role and squad roster. The leader delegates via
child issues (parallel) or @mention (serial).

**You will see:** Multiple agents posting comments on related issues; a squad leader
posting coordination summaries.

### Squad Mode Walkthrough

**Prerequisites:**
1. Create a Squad in Multica (Settings → Squads → New Squad)
   - Add a leader agent (e.g., `claude-code-leader`)
   - Add member agents (e.g., `claude-code-frontend`, `claude-code-backend`)
2. **Install this plugin on every agent's Claude Code runtime** — both leader and all members
   need the plugin for verification Iron Law and HITL protocols to work

**Step-by-step:**

1. **Create an issue and assign to the Squad** (not to an individual agent)
   ```
   multica issue create --title "Refactor payment module" --assignee-id <squad-uuid>
   ```

2. **Leader is activated** — daemon detects Squad assignment and injects Squad Operating
   Protocol into the leader's CLAUDE.md. The plugin's session-start hook detects this and
   injects the squad roster into context.

3. **Leader decomposes the task** — if the issue description is clear, leader delegates
   immediately. If ambiguous, leader posts a `[HITL] phase=discover` question asking for
   clarification. Reply to that comment to unblock.

4. **Leader creates child issues** (parallel delegation):
   ```
   multica issue create --title "Frontend UI" --status todo --assignee-id <agent-uuid>
   multica issue create --title "Backend API" --status todo --assignee-id <agent-uuid>
   ```
   Multiple issues showing `in_progress` simultaneously is **normal** — this is parallel execution.

5. **Members work independently** — each member follows the standard 7-phase workflow.
   If a member is blocked, it posts `[HITL:leader]` (not `[HITL:human]`), which triggers
   the leader to wake up and route the decision.

6. **HITL routing** — when you see a `[HITL:human]` comment, it means the leader could not
   resolve it. **Reply to the `[HITL:human]` comment** (the one addressed to humans, not the
   original member question).

7. **Leader summarizes** — when all child issues complete, the parent issue receives a system
   notification. Leader wakes up, posts a summary comment, and sets parent issue to `done`.

**What to watch on the kanban:**
- Multiple `in_progress` child issues = normal parallel execution
- Parent issue stays `in_progress` until leader summarizes
- `blocked` on any issue = someone needs your input (check for `[HITL:human]` comments)

### Subagent Dispatch

Agents spawn specialist subagents (executor, code-reviewer, debugger) using model
routing injected as `$MULTICA_MODEL_FAST/STD/DEEP`. Results write to
`.multica/state/<id>/subagent-<task_id>.md` or an issue comment.

**You will see:** Comments from specialist subagents, often prefixed with their role.

### Knowledge Management

Learnings accumulate in `.multica/learnings.jsonl`. Session-start loads the 10 most
recent entries plus all with `confidence >= 7`, marking entries whose source files
have changed as `[possibly stale]`. `stop.sh` git-commits the file on DONE.
`tools/curate-memory.sh` deduplicates and applies confidence decay.

**You will see:** No direct user-facing output; this runs silently in the background.

### Context Budget

`multica-workflow` enforces: ≤35% remaining → write checkpoint comment before new
complex work; ≤25% → graceful handoff — the agent persists its position to
`loop.json.progress`, posts `[checkpoint] context-handoff | progress: <pct>%`,
and exits 0. The daemon relaunches a fresh session automatically; no human
action is needed (REQ-06-03).

**You will see:** A `[checkpoint] context-handoff` comment and then a new session
continuing from the saved sub-step. The issue is never set `blocked` for this.

---

## §4 For Reviewers

You do not need to understand the agent internals to review its work. This section
explains the phase state machine and the comment trail (REQ-10-01).

### The 7-phase state machine

```
            [proceed]            (auto)            [looks-right]
  spec ────────────────► plan ──────────► demo ────────────────► execute
   ▲  │                                    ▲  │                     │
   │  └─[revise: ...]──(new [spec:vN])     │  └─[wrong: ...]──     │ (internal
   └────────────────────────────────────┘  └──(new [demo:vN])     │  exit-2 loop)
                                                                    ▼
  done ◄──── result ◄──────────────────────────────────────────  verify
        (user confirms      (auto on pass, or [verify-failed]
         or 72h timeout)     after 3 attempts)
```

- **spec** — the agent writes a structured specification and posts `[spec:vN]`,
  then exits. Your `[proceed]` or `[revise: ...]` comment starts the next session.
- **plan** — internal decomposition into sub-steps; no comment, no waiting.
- **demo** — a minimal visible version (mock-up, proof-of-concept) posted as
  `[demo:vN]`. Reply `[looks-right]` or `[wrong: ...]`.
- **execute** — full implementation; the only phase with internal iteration. You
  see `[checkpoint:N]` only if it runs long.
- **verify** — the verification command runs and `[verification]` records exit
  code, command, and output hash. Three failures → `[verify-failed]`.
- **result** — final summary as `[result]`; the issue closes on your confirmation
  (or auto-closes after 72h with a `[result-timeout]` notice).

### "You see X → do Y" quick table

| You see | Phase | Expected action |
|---------|-------|-----------------|
| `[spec:vN]` | spec done | Reply `[proceed]` or `[revise: <feedback>]` |
| `[demo:vN]` | demo done | Reply `[looks-right]` or `[wrong: <feedback>]` |
| `[breakdown:vN]` | planning mode | Reply `[proceed]` or `[revise: <feedback>]` |
| `[checkpoint:N]` | execute running | Nothing — informational |
| `[checkpoint] context-handoff` | execute paused | Nothing — auto-resumes |
| `[verification] exit_code=0 ...` | verify passed | Nothing |
| `[verification] ... category=...` | verify failed | Nothing yet — agent is fixing |
| `[verify-failed]` | verify exhausted | Reply `[retry]` or `[abort]` |
| `[result]` | result | Confirm, or `[abort]` |
| `[HITL] question_id=...` | any (blocked) | Reply in plain text to the comment |
| `[loop-exhausted]` / `[loop-stuck]` | stuck | Investigate; `[retry]` resets the loop |

### Example comment trail

```
agent:  [spec:v1] Spec: add POST /login ... acceptance criteria ...
you:    [revise: must support OAuth2, not just passwords]
agent:  [spec:v2] Spec: add POST /login with OAuth2 ...
you:    [proceed]
agent:  [phase] spec→plan
agent:  [demo:v1] Demo: non-functional login form + route stub
you:    [looks-right]
agent:  [phase] demo→execute
agent:  [verification] exit_code=0 command="npm test" output_hash=a1b2c3d4
agent:  [phase] verify→result
agent:  [result] Implemented POST /login (OAuth2) ... 14 tests passing.
```

Your `[revise: ...]` at step 2 was automatically captured as a repo-scoped
learning (confidence 9) — the next task on this repo starts knowing it.

### [HITL] — agent needs your input

The agent is blocked and waiting for a human reply. Read the comment; it contains a
clear question and (usually) a list of options. Reply directly to the comment in plain
text — no special format required. The daemon will reactivate the agent on your reply.

### [HITL:timeout] — agent chose a conservative default

The HITL comment timed out (daemon reaper decided). The agent selected the most
conservative available option and continued. Check the follow-up comment to see which
option was chosen and whether you agree. You can always post a correction comment to
redirect on the next turn.

### [loop-complete] — task finished

All stories have passed verification and the reviewer subagent has approved. The issue
status is `done`. No action required.

### [checkpoint] — task in progress, no action needed

The agent is pausing mid-task either because it is about to start complex work
(≤35% context remaining) or because it has been restarted. The issue will be
re-enqueued automatically. No action required unless you want to redirect.

---

## §5 For Operators

Operators (squad leads, tech leads) monitor agent health and decide when to
intervene (REQ-10-02).

### Reading loop.json for health

`.multica/state/<issue-id>/loop.json` is the live state. The fields that matter:

| Field | Healthy | Intervene when |
|-------|---------|----------------|
| `phase` | progressing spec→…→done | unchanged across many sessions |
| `iteration` / `max_iterations` | low, climbing slowly | approaching 50 — agent is thrashing |
| `exit2_triggers_per_session` | 0–3 | high values — agent loops within one session |
| `progress.pct` | climbing | frozen while iteration climbs |
| `open_hitls` | empty | entries older than 48h — nobody answered |
| `child_issues` (leader) | shrinking to all-done | a child silent past `squad_stuck_threshold_minutes` |

### One-command status

```bash
bash tools/loop-status.sh              # all active issues
bash tools/loop-status.sh <issue-id>   # one issue: iteration, phase, story bar, HITL
```

### When to intervene

- **`[loop-exhausted]`** — the 50-iteration cap fired and the loop deactivated.
  Read the last `[verification]` failures, fix the blocker (or refine the issue),
  then post `[retry]` to reset the counter and re-enqueue.
- **`[loop-stuck]`** — same failure 3+ times or a HITL aged past 48h. A human
  answer or scope decision is needed; reply on the issue.
- **Iteration high, progress.pct frozen** — the agent is retrying one sub-step.
  Post a steering comment (it is read at the next session start) or `[abort]`.
- **`blocked` with no `[HITL]` comment** — abnormal exit. Check
  `.multica/logs/hook-errors.log` and `multica issue rerun <id>`.

### Squad leader stuck-member checklist

1. `bash tools/loop-status.sh <child-id>` — phase and iteration of the member.
2. Child's last comment older than the stuck threshold? The leader's stop hook
   posts `[checkpoint] squad-stuck` naming it (rate-limited to 1/hour).
3. Check the child for `[HITL:leader]` the leader never answered — answer it.
4. Member at capacity (≥6 in_progress)? Reassign or wait.
5. Truly dead member → reassign the child issue; the leader picks up the new
   status from issue metadata on its next checkpoint.

---

## §6 Troubleshooting

**1. Agent reported completion but issue status did not change.**
The agent did not call `<<cli:issue.status>> done` or the call failed silently.
Fix: `multica issue status <id> done`. Verify the final comment includes a `[verification]` block.
Who can fix this: **operator**

**2. Persistence loop stuck — no iteration progress across restarts.**
Possible causes: `loop.json` mtime is < 60 s old when `stop.sh` fires (throttle); a
story has not passed verification; issue is `blocked` awaiting a human reply.
Fix: read `loop.json` to find current phase and next story; check comments for
`[HITL]`/`[checkpoint]` entries. If stuck at `max_iterations`, set `"active": false`
manually and re-enqueue via `multica issue rerun <id>`.
Who can fix this: **operator** (re-enqueue) or **reviewer** (reply to [HITL])

**3. Squad activity not recorded — audit warning present.**
The squad leader ended its turn without calling `multica squad activity`. `stop.sh`
called `multica squad activity <id> failed` automatically.
Fix: check whether the `SessionStart` hook fires (run `npx github:yangliang2/multica-agent-plugin --verify`
to confirm hook registration). Re-enqueue the issue if the session terminated abnormally.
Who can fix this: **operator**

**4. Learnings disappeared after moving to a new machine.**
`stop.sh` only commits `learnings.jsonl` on the DONE path; mid-task sessions are not
committed. The workspace must be a git repository.
Fix: on the source machine run
`git add .multica/learnings.jsonl && git commit -m "chore(knowledge): manual learnings sync" && git push`,
then `git pull` on the target.
Who can fix this: **operator**

**5. Scenario 4 smoke test fails (SHA-256 mismatch).**
`docs/cli-reference.md` was updated without regenerating the lock, or the `multica`
binary was upgraded.
Fix: `bash tools/refresh-cli-reference.sh`, then re-run the smoke test.
Who can fix this: **dev**
