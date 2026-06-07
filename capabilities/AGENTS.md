<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-06-07 | Updated: 2026-06-07 -->

# capabilities

## Purpose
Harness capability maps that declare what each AI harness (Claude Code, future: Codex, Gemini) natively supports versus what requires wrapper shims. Skills check these maps before using hook-dependent or harness-specific features.

## Key Files

| File | Description |
|------|-------------|
| `claude-code.json` | Capability map for the Claude Code harness — declares model routing tiers, operational thresholds (HITL timeout, loop max iterations, context checkpoints), and per-capability support level (`native`, `wrapper`, `missing`). |

## For AI Agents

### Working In This Directory
- This directory is the **authority** for what the current harness can do. Skills must not assume a capability is available without checking here first.
- Adding a new harness: create `<harness-name>.json` following the same schema as `claude-code.json`.
- Changing a threshold: update `claude-code.json` and verify that dependent skills (especially `persistence-loop.md`) still read the correct key.

### Common Patterns
- `"native"` — harness provides this natively, no shim needed.
- `"wrapper"` — feature works but requires an adapter layer (e.g. destructive-guard via pre-tool.sh).
- `"missing"` — feature not available; skill must degrade gracefully or skip.

## Dependencies

### Internal
- `skills/core/multica-workflow.md` — consults `hitl_timeout_hours` and `loop_max_iterations`
- `skills/advanced/persistence-loop.md` — consults `context_checkpoint_pct` and `context_blocked_pct`

<!-- MANUAL: -->
