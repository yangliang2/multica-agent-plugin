# multica-agent-plugin

Claude Code agent plugin for the Multica ecosystem. Provides skills, hooks, tools, and adapters that enable Claude Code agents running inside the Multica daemon to interact with issues, comments, metadata, and the broader Multica platform.

## What This Is

Multica is an AI-native task management platform (think Linear, but with AI agents as first-class citizens). When an agent is assigned an issue, the Multica daemon spawns a Claude Code session and hands it a task. This plugin extends that session with:

- **Skills** — reusable slash-command workflows for common Multica operations (update status, post a comment, set metadata, etc.)
- **Hooks** — lifecycle hooks that fire at session start/stop, on tool use, and on errors
- **Tools** — shell scripts and utilities for working with the `multica` CLI
- **Adapters** — thin integration shims for connecting Claude Code output to Multica events
- **Capabilities** — declarative capability descriptors consumed by the harness

## Supported Frameworks

| Harness | Status |
|---------|--------|
| Claude Code | MVP (this repo) |
| Codex | Roadmap |
| Gemini CLI | Roadmap |
| OpenCode | Roadmap |

## Installation

> Installation instructions will be added in Step 3 once the packaging format is finalized.

For now, clone and symlink manually:

```bash
git clone https://github.com/your-org/multica-agent-plugin.git
# Wire into your Claude Code config per your harness setup
```

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

## Repository Layout

```
multica-agent-plugin/
├── docs/
│   ├── abi/                  # ABI / contract definitions (Step 1)
│   ├── cli-reference.md      # Locked multica CLI help output
│   └── cli-reference.lock    # SHA-256 of cli-reference.md
├── tools/
│   ├── refresh-cli-reference.sh
│   └── render-anchors.sh
├── skills/
│   ├── core/                 # Core skills (comment, status, metadata)
│   └── advanced/             # Advanced skills (autopilot, squad, etc.)
├── hooks/                    # Claude Code lifecycle hooks
├── tests/smoke/              # Smoke tests
├── capabilities/             # Capability descriptors
├── adapters/                 # Harness-specific integration shims
├── VERSION                   # Semver version string
└── README.md
```

## Version

See [`VERSION`](VERSION).
