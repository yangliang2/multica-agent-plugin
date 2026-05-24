# multica-agent-plugin

Claude Code agent plugin for the Multica ecosystem. Provides skills, hooks, tools, and adapters that enable Claude Code agents running inside the Multica daemon to interact with issues, comments, metadata, and the broader Multica platform.

## What This Is

Multica is an AI-native task management platform (think Linear, but with AI agents as first-class citizens). When an agent is assigned an issue, the Multica daemon spawns a Claude Code session and hands it a task. This plugin extends that session with skills, hooks, tools, adapters, and capability descriptors that wire the agent into Multica workflows — from posting comments and setting status, to coordinating squads, routing to subagents, and persisting cross-session learnings.

## Features

### v0.1.0 — MVP
- **Verification Iron Law** (`skills/core/verification.md`) — agents must verify before claiming done; 3-attempt minimum before escalating
- **PRD story tracking** (`skills/advanced/persistence-loop.md`) — session-state-driven PRD loop with completion signal protocol and deslop pass
- **HITL blocked protocol** (`skills/core/hitl-protocol.md`) — structured human-in-the-loop escalation with blocked/unblocked state machine
- **Stop hook** (`hooks/stop.sh`) — completion signal protocol; posts checkpoint comments on session end
- **Pre-tool hook** (`hooks/pre-tool.sh`) — safe-exec proxy for destructive CLI calls
- **Session-start hook** (`hooks/session-start.sh`) — loads notepad Priority Context and recent learnings into session context
- **CLI ABI** (`docs/cli-reference.md`) — locked multica CLI reference with SHA-256 integrity check

### v0.2.0 — Squad Support
- **Squad leader workflow** (`skills/core/squad-leader-workflow.md`) — coordinate-don't-execute pattern, two delegation strategies (child issue parallel vs @mention serial), mandatory squad activity, HITL reply no-mention rule, 3-strike escalation
- **Squad member workflow** (`skills/core/squad-member-workflow.md`) — two-tier HITL ([HITL:leader] preferred, [HITL:human] as fallback), independent 3-strike counter, no @mention on completion to prevent double-fire
- **Squad leader detection** — session-start injects roster when `## Squad Operating Protocol` marker found in CLAUDE.md
- **Squad activity audit** — stop hook performs passive squad activity check (non-blocking)
- **CLI anchors** — three new anchors added: `squad.activity`, `issue.create.child`, `issue.comment.list.thread`
- **Render-anchors drift guard** — `tools/render-anchors.sh` exits 2 on unknown anchor

### v0.3.0 — Subagent Dispatch and Reliability
- **Subagent dispatch spec** (`skills/advanced/subagent-dispatch.md`) — model routing table (haiku/sonnet/opus), fresh context principle (complete prompt, no history references), Task() examples, output contract
- **Model routing env vars** — session-start injects `MULTICA_MODEL_FAST/STD/DEEP` from `capabilities/claude-code.json` `model_routing` field
- **3-strike file storage** — session-start reads `.multica/state/<issue_id>/hitl-bounces.json` and injects bounce count into context (program-enforced, not LLM-discipline)
- **Direct squad activity call** — stop hook calls `multica squad activity failed` immediately when leader skips squad activity (replaces deferred warning)
- **Context budget awareness** — multica-workflow skill enforces checkpoint at ≤35% context, blocked at ≤25%

### v0.4.0 — Knowledge Management
- **Learning dedup** (`tools/curate-memory.sh`) — last-wins dedup by key, confidence decay (>90d: -2, >180d: -4), archive on conf<3, atomic write
- **Staleness detection** — session-start uses stat-based staleness (marks `[possibly stale]` when source file missing or mtime newer than learning); requires python3
- **Multi-machine knowledge sync** — stop hook git-commits `.multica/learnings.jsonl` on DONE path for cross-machine knowledge propagation
- **Memory consolidation** — stop hook writes `consolidation-prompt.txt` for haiku subagent to merge and summarize learnings
- **Working Memory expiry** — stop hook prunes notepad Working Memory entries older than 7 days

## Architecture

```
multica-agent-plugin/
├── docs/
│   ├── abi/                  # ABI / contract definitions
│   ├── cli-reference.md      # Locked multica CLI help output
│   └── cli-reference.lock    # SHA-256 of cli-reference.md
├── tools/
│   ├── refresh-cli-reference.sh
│   ├── render-anchors.sh
│   └── curate-memory.sh      # Learning dedup and confidence decay (v0.4.0)
├── skills/
│   ├── core/                 # Core skills (workflow, hitl, verification, squad)
│   └── advanced/             # Advanced skills (persistence-loop, parallel-exec, subagent-dispatch)
├── hooks/                    # Claude Code lifecycle hooks
│   ├── stop.sh               # Completion signal, squad audit, learnings git commit
│   ├── pre-tool.sh           # Safe-exec proxy
│   └── session-start.sh      # Context injection, staleness detection, env vars
├── tests/smoke/              # Smoke tests
├── capabilities/             # Capability descriptors
│   └── claude-code.json      # Capability matrix incl. model_routing
├── adapters/                 # Harness-specific integration shims
├── VERSION                   # Semver version string
└── README.md
```

## Installation

> Installation instructions will be added once the packaging format is finalized.

For now, clone and symlink manually:

```bash
git clone https://github.com/your-org/multica-agent-plugin.git
# Wire into your Claude Code config per your harness setup
```

## Supported Frameworks

| Harness | Status |
|---------|--------|
| Claude Code | MVP (this repo) |
| Codex | Roadmap |
| Gemini CLI | Roadmap |
| OpenCode | Roadmap |

## CLI Reference

The canonical `multica` CLI reference is in [`docs/cli-reference.md`](docs/cli-reference.md). It is locked via [`docs/cli-reference.lock`](docs/cli-reference.lock) (SHA-256 of the reference file).

To refresh after a `multica` update:

```bash
tools/refresh-cli-reference.sh
```

To expand `<<cli:some.command>>` anchors in any file:

```bash
tools/render-anchors.sh --inplace path/to/file.md
```

## Version

See [`VERSION`](VERSION). Current version: 0.4.0
