<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-06-07 | Updated: 2026-06-07 -->

# skills

## Purpose
Skill markdown files that define agent behavior protocols. Skills are loaded by the Claude Code harness at session start (via `hooks/session-start.sh`) or on-demand. Two tiers: `core/` (always-loaded workflow contracts) and `advanced/` (opt-in execution strategies).

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `core/` | Always-active workflow skills: 5-phase state machine, HITL protocol, verification Iron Law, systematic debug, Squad leader/member coordination (see `core/AGENTS.md`) |
| `advanced/` | Optional execution strategies: persistence loop, parallel review, subagent dispatch (see `advanced/AGENTS.md`) |

## For AI Agents

### Working In This Directory
- Skill files are Markdown — no code execution, no side effects.
- Each skill must declare its harness dependency via a degradation notice if it relies on Claude Code-specific features (hooks, interactive UI).
- Never add executable logic here; all runtime behavior belongs in `hooks/` or `tools/`.

### Common Patterns
- Skills reference CLI calls via `<<cli:*>>` anchors, never raw command literals (see `docs/abi/cli-outward.md`).
- Capability gating: check `capabilities/claude-code.json` before using hook-dependent features.

## Dependencies

### Internal
- `capabilities/claude-code.json` — capability map skills must consult before using hook features
- `docs/abi/cli-outward.md` — anchor definitions for all CLI calls

<!-- MANUAL: -->
