<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-06-07 | Updated: 2026-06-07 -->

# .claude-plugin

## Purpose
Claude Code marketplace and plugin manifest files. These define how the plugin appears in the Claude Code plugin registry and marketplace.

## Key Files

| File | Description |
|------|-------------|
| `plugin.json` | Plugin manifest — lists all skill file paths included in the plugin bundle, used by Claude Code to load skills at session start. |
| `marketplace.json` | Marketplace manifest — display metadata (name, description, category, tags, version) for the Claude Code marketplace listing. Follows `anthropic.com/claude-code/marketplace.schema.json`. |

## For AI Agents

### Working In This Directory
- `plugin.json` skill paths must stay in sync with actual files in `skills/`. An entry pointing to a missing file will cause plugin load failure.
- `marketplace.json` version must match `package.json` version — update both together on release.
- Do not add skills to `plugin.json` that haven't been reviewed for daemon-safety (no interactive prompts, no sleep loops).

## Dependencies

### Internal
- `skills/` — all skill paths listed in `plugin.json` must exist here

<!-- MANUAL: -->
