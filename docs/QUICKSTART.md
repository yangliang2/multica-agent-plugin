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

**Option A (recommended) — npx from GitHub:**

```bash
npx github:yangliang2/multica-agent-plugin
```

One command handles everything: detects dependencies, copies hooks to
`~/.claude/hooks/multica/`, registers them in `~/.claude/settings.json`, and
writes `MULTICA_PLUGIN_ROOT` to your shell profile automatically.

**Option B — Claude Code plugin marketplace:**

```
/plugin marketplace add https://github.com/yangliang2/multica-agent-plugin
```

Run this inside Claude Code to install skills via the native plugin system.
Then run `npx github:yangliang2/multica-agent-plugin` once to register hooks.

## Verify

```bash
npx github:yangliang2/multica-agent-plugin --verify
```

Checks dependencies, hook registration, and `settings.json` status.

For deeper environment validation:

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
multica issue assign ISS-42 --to "Lambda"

# Watch the comment trail
multica issue comment list ISS-42
```

Within the first agent turn you will see `[phase] discover` then `[phase] plan`.
When the task completes you will see `[loop-complete]`.

## Example: Full 7-Phase Workflow

A realistic end-to-end trail (issue: *"Add login endpoint to auth module"*),
traceable in under 10 minutes. Lines marked `you:` are comments you post.

```text
        multica issue create --title "Add login endpoint to auth module" \
          --body 'POST /login with session cookie. [verification] command="npm test"'

agent:  [spec:v1]
        Requirements: POST /login accepting {email, password} ...
        Acceptance: 401 on bad credentials; sets httpOnly session cookie ...
you:    [revise: passwords are out of scope — we use OAuth2 only]
        ── session exits after each checkpoint; your reply triggers the next one

agent:  [spec:v2]
        Requirements: POST /login initiating OAuth2 authorization-code flow ...
you:    [proceed]

agent:  [phase] spec→plan          ← plan is internal; no review needed
agent:  [demo:v1]
        Demo: route stub + redirect to provider (non-functional, no token exchange)
you:    [looks-right]

agent:  [phase] demo→execute       ← implementation; internal iteration
agent:  [checkpoint:5] Loop active at iteration 5, phase=execute. Continuing.

agent:  [verification] exit_code=0 command="npm test" output_hash=3f9a1c2e
        14 passing (auth: 6 new)
agent:  [phase] verify→result
agent:  [result]
        Implemented POST /login (OAuth2 code flow), callback handler, session
        cookie issuance. Evidence above. Caveat: refresh tokens not in scope.
you:    (confirm)                  → issue status: done
```

Two things happened invisibly:

1. Your `[revise: passwords are out of scope ...]` was captured automatically as
   a repo-scoped learning (confidence 9). The next task on this repo starts with
   "Previous corrections on this repo: passwords are out of scope — OAuth2 only".
2. The `[verification] command="npm test"` line in the issue body was stored as
   `loop.json.verification_cmd` and used for every verify attempt.

The full signal grammar lives in
[HUMAN-GUIDE.md §2 Comment Protocol](HUMAN-GUIDE.md#2-comment-protocol); the
reviewer quick-table in §4.

## Something Went Wrong?

See [HUMAN-GUIDE.md — Troubleshooting](HUMAN-GUIDE.md#troubleshooting).

## Daemon Deployment

When deploying for Multica daemon (not local development), configure the daemon to
set `MULTICA_AGENT_SESSION=1` when spawning Claude Code agents:

```bash
MULTICA_AGENT_SESSION=1   # Activates plugin hooks in daemon-spawned sessions
```

Without `MULTICA_AGENT_SESSION=1`, hooks will still activate when `MULTICA_ISSUE_ID`
is present (which the daemon sets automatically). The explicit flag is useful when
you want to guarantee activation regardless of issue context.

`MULTICA_PLUGIN_ROOT` is set automatically by the installer and does not need to be
configured manually. You may override it in daemon environments if the plugin is
installed to a non-standard path.

**Coexistence with OMC/GSD:** If you have other Claude Code plugins installed,
set `MULTICA_AGENT_SESSION=0` in your local shell profile to disable multica-plugin
hooks outside of daemon sessions:
```bash
export MULTICA_AGENT_SESSION=0  # In ~/.zshrc or ~/.bashrc
```
