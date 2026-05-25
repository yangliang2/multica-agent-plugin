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
git clone https://github.com/yangliang2/multica-agent-plugin.git
cd multica-agent-plugin
bash install.sh
```

`install.sh` verifies the `multica` CLI is present, merges `hooks/hooks.json` into
`~/.claude/settings.json` (or `$CLAUDE_SETTINGS_PATH`) using Python's `json` module
(existing hooks are preserved; duplicates are skipped), and prints a reminder to
export `MULTICA_PLUGIN_ROOT`.

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

If you relocate the plugin directory, run `bash install.sh` again to update the
registered paths (they are written as absolute paths at install time).

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
Fix: check whether `MULTICA_PLUGIN_ROOT` is set and the `SessionStart` hook fires.
Re-enqueue the issue if the session terminated abnormally.
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
