<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-06-07 | Updated: 2026-06-07 -->

# skills/advanced

## Purpose
Optional execution strategy skills for complex, long-running, or multi-agent tasks. These are loaded on-demand (referenced from `CLAUDE.md` skills index) rather than injected at every session start.

## Key Files

| File | Description |
|------|-------------|
| `persistence-loop.md` | PRD-driven persistence loop — session state via loop.json, story-by-story completion tracking, automatic retry up to `loop_max_iterations`, and mandatory deslop pass. Requires Stop hook (Claude Code only). |
| `parallel-exec.md` | Two-stage parallel review strategy — spec-compliance pass followed by code-quality pass with model routing (haiku/sonnet/opus by task size). |
| `subagent-dispatch.md` | Subagent dispatch with fresh-context principle — model routing table, isolation guidelines, and result synthesis protocol. |

## For AI Agents

### Working In This Directory
- All skills here must include a degradation notice if they depend on Claude Code hooks.
- `persistence-loop.md` depends on `stop.sh` exit-2 signal — it is a no-op in non-Claude Code harnesses.
- Reference `capabilities/claude-code.json` capability values before activating features in these skills.

### Common Patterns
- Model routing: `fast=haiku`, `standard=sonnet`, `deep=opus` — read from `capabilities/claude-code.json`.

## Dependencies

### Internal
- `hooks/stop.sh` — persistence-loop relies on exit-2 continuation signal
- `capabilities/claude-code.json` — model routing and threshold values

<!-- MANUAL: -->
