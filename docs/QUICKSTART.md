# multica-agent-plugin — Quickstart

Get an agent handling your first issue in 5 minutes.

## Prerequisites

- `multica` CLI — `multica --help` must exit 0
- `git` 2.x
- `python3` 3.8+
- Claude Code (any current release)

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

## Verify

```bash
bash tests/smoke/run-claude.sh
# Expected: PASS: 10  FAIL: 0
```

No live daemon or Claude session required.

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
