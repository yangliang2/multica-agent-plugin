# multica-agent-plugin — Quickstart

Get an agent handling your first issue in 5 minutes.

## Prerequisites

> **Version compatibility:** multica >= 0.3.4, Claude Code >= latest

| Requirement | Purpose | Install |
|-------------|---------|---------|
| `multica` CLI | All issue/comment/status calls | [multica install guide](https://multica.ai/docs/install) |
| `git` 2.x | Learnings cross-machine sync (stop hook commits on task completion) | system package manager |
| `python3` 3.8+ | Staleness detection, threshold configuration | system package manager |
| Claude Code | Hook registration target | [claude.ai/code](https://claude.ai/code) |

## Installation

```bash
# 1. Clone
git clone https://github.com/yangliang2/multica-agent-plugin.git
cd multica-agent-plugin

# 2. Install (merges hooks into ~/.claude/settings.json)
bash install.sh

# 3. Export plugin root — add to your shell profile
export MULTICA_PLUGIN_ROOT="/absolute/path/to/multica-agent-plugin"
```

`install.sh` prints the path where hooks were registered, e.g.:
```
[install] Hooks registered to: /Users/you/.claude/settings.json
```
If the path looks wrong, set `CLAUDE_SETTINGS_PATH=/path/to/settings.json` before running install.

## Verify

```bash
bash tests/smoke/run-claude.sh
# Expected: PASS: 10  FAIL: 0
```

No live daemon or Claude session required.

> **Note:** Smoke tests verify script logic only. They do not verify daemon integration
> (whether `MULTICA_ISSUE_ID` is correctly injected by your daemon). Run `bash tools/doctor.sh`
> for a full environment check.

## Run Your First Issue

```bash
# Create a simple issue
multica issue create --title "Hello agent" --body "Print the current date to a comment."
# → prints issue ID, e.g. ISS-42

# Assign to an agent
multica issue assign ISS-42 --agent default

# Watch the comment trail
multica issue comments ISS-42 --follow
```

Within the first agent turn you will see `[phase] discover` then `[phase] plan`.
When the task completes you will see `[loop-complete]`.

## Something Went Wrong?

See [HUMAN-GUIDE.md — Troubleshooting](HUMAN-GUIDE.md#troubleshooting).

## Daemon Deployment

When deploying for Multica daemon (not local development), configure the daemon to
set these environment variables when spawning Claude Code agents:

```bash
MULTICA_PLUGIN_ROOT=/absolute/path/to/multica-agent-plugin
MULTICA_AGENT_SESSION=1   # Activates plugin hooks in daemon-spawned sessions
```

Without `MULTICA_AGENT_SESSION=1`, hooks will still activate when `MULTICA_ISSUE_ID`
is present (which the daemon sets automatically). The explicit flag is useful when
you want to guarantee activation regardless of issue context.

**Coexistence with OMC/GSD:** If you have other Claude Code plugins installed,
set `MULTICA_AGENT_SESSION=0` in your local shell profile to disable multica-plugin
hooks outside of daemon sessions:
```bash
export MULTICA_AGENT_SESSION=0  # In ~/.zshrc or ~/.bashrc
```
