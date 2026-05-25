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
npx multica-agent-plugin
```

The installer verifies the `multica` CLI is present, copies hooks to
`~/.claude/hooks/multica/`, merges hook registrations into `~/.claude/settings.json`
(existing hooks are preserved; duplicates are skipped), and writes
`MULTICA_PLUGIN_ROOT` to your shell profile automatically.

To verify the installation:

```bash
npx multica-agent-plugin --verify
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

## §2 Feature Overview

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
to that comment with your answer — no special format required.

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

5. **Members work independently** — each member follows the standard 5-phase workflow.
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
complex work; ≤25% → checkpoint + set `blocked` (reason: `context-budget-critical`).

**You will see:** A `[checkpoint]` comment followed by a `blocked` status when the
agent is running low on context. Re-enqueue the issue to continue.

---

## §3 For Reviewers

You do not need to understand the agent internals to review its work. This section
explains the comment trail.

### [phase] prefix — what the agent is doing

Comments prefixed `[phase]` mark lifecycle transitions:

| Comment | Meaning |
|---------|---------|
| `[phase] discover` | Agent is reading the issue and clarifying requirements |
| `[phase] plan` | Agent has requirements; posting its work plan |
| `[phase] execute` | Agent is implementing |
| `[phase] verify` | Agent is running verification commands |
| `[phase] report` | Agent is summarising the result |

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

## §4 Troubleshooting

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
Fix: check whether the `SessionStart` hook fires (run `npx multica-agent-plugin --verify`
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
