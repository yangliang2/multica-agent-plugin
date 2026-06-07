<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-06-07 | Updated: 2026-06-07 -->

# tools

## Purpose
Standalone utility scripts for operators and agents — diagnostics, maintenance, and runtime helpers. These are not hooks (not called by Claude Code events); they are invoked directly by agents or humans.

## Key Files

| File | Description |
|------|-------------|
| `doctor.sh` | Health check — verifies dependencies (multica, python3, git, jq), environment variables, hook registration in `~/.claude/settings.json`, and plugin structure integrity. |
| `safe-exec.deny.list` | ERE deny patterns consumed by `hooks/pre-tool.sh` to block destructive Bash commands. One pattern per line; lines starting with `#` are comments. |
| `curate-memory.sh` | Prunes and curates `.multica/learnings.jsonl` — removes low-confidence or stale entries. |
| `learning-review.sh` | Reviews accumulated learnings and surfaces high-confidence patterns for promotion to workspace scope. |
| `loop-status.sh` | Inspects `.multica/state/<issue-id>/loop.json` to show current loop phase, iteration count, and active flag for a given issue. |
| `refresh-cli-reference.sh` | Regenerates the CLI anchor index in `docs/abi/cli-outward.md` from the live multica CLI. |
| `render-anchors.sh` | Resolves `<<cli:*>>` anchors in skill files to their concrete command strings for debugging. |

## For AI Agents

### Working In This Directory
- `safe-exec.deny.list` is a security-relevant file. Adding patterns is safe; removing or weakening patterns requires explicit human approval. See `KNOWN-LIMITATIONS.md` for bypass vectors.
- `doctor.sh` is the first diagnostic step for any hook or installation issue — run it before investigating further.
- `loop-status.sh` requires `MULTICA_ISSUE_ID` to be set; without it, it lists all known issues.

### Testing Requirements
- Changes to `safe-exec.deny.list` must be validated by `tests/smoke/test-deny-list.sh`.
- Changes to `doctor.sh` should be manually verified against a fresh install.

### Common Patterns
- Scripts use `PLUGIN_ROOT="${MULTICA_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"` to locate themselves without hardcoded paths.

## Dependencies

### Internal
- `hooks/pre-tool.sh` — consumes `safe-exec.deny.list`
- `.multica/state/` — read by `loop-status.sh`

### External
- `multica` CLI — required by `refresh-cli-reference.sh` and `learning-review.sh`
- `python3` — used by `curate-memory.sh` for date arithmetic

<!-- MANUAL: -->
