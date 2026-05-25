# multica-agent-plugin

Claude Code agent plugin for the Multica ecosystem. Provides skills, hooks, tools, and adapters that enable Claude Code agents running inside the Multica daemon to interact with issues, comments, metadata, and the broader Multica platform.

## What This Is

Multica is an AI-native task management platform (think Linear, but with AI agents as first-class citizens). When an agent is assigned an issue, the Multica daemon spawns a Claude Code session and hands it a task. This plugin extends that session with skills, hooks, tools, adapters, and capability descriptors that wire the agent into Multica workflows — from posting comments and setting status, to coordinating squads, routing to subagents, and persisting cross-session learnings.

## Features

- **Verification Iron Law** — agents must verify with evidence before claiming done
- **PRD story tracking** — session-persistent loop with `<promise>DONE</promise>` completion signal
- **HITL protocol** — structured human-in-the-loop via `blocked` + comment, no interactive prompts
- **Squad coordination** — leader/member workflows, two-tier HITL routing, mandatory squad activity
- **Subagent dispatch** — model routing (haiku/sonnet/opus), fresh context principle
- **Knowledge management** — learnings dedup, staleness detection, cross-machine git sync
- **Plugin isolation** — hooks only activate in Multica daemon sessions; coexists with OMC/GSD

See [CHANGELOG.md](CHANGELOG.md) for full version history.

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

See [docs/USAGE.md](docs/USAGE.md) for complete installation and setup instructions.

For quick setup, clone and symlink manually:

```bash
git clone https://github.com/yangliang2/multica-agent-plugin.git
# Wire into your Claude Code config per your harness setup
```

## Compatibility

| Component | Minimum Version |
|-----------|----------------|
| multica CLI | 0.3.4 |
| Claude Code | latest |
| python3 | 3.8 |
| git | 2.x |

## Supported Frameworks

| Harness | Status |
|---------|--------|
| Claude Code | MVP (this repo) |
| Codex | Roadmap |
| Gemini CLI | Roadmap |
| OpenCode | Roadmap |

## Documentation

| Who you are | Where to start |
|-------------|----------------|
| First-time setup | [QUICKSTART.md](docs/QUICKSTART.md) — up and running in 5 minutes |
| Operator / developer | [HUMAN-GUIDE.md](docs/HUMAN-GUIDE.md) — full feature reference and troubleshooting |
| Issue reviewer | [HUMAN-GUIDE.md#for-reviewers](docs/HUMAN-GUIDE.md#for-reviewers) — reading agent comment trails |
| Agent (running inside Multica daemon) | [AGENT-CONTRACT.md](docs/AGENT-CONTRACT.md) — normative operating contract |

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

See [`VERSION`](VERSION) · [`CHANGELOG.md`](CHANGELOG.md)
