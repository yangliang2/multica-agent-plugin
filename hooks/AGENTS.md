<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-06-07 | Updated: 2026-06-07 -->

# hooks

## Purpose
Claude Code lifecycle hooks that wire the Multica daemon into the Claude Code event system. All hooks are no-ops when `DISABLE_MULTICA_PLUGIN=1` or when running outside a Multica daemon context (`MULTICA_ISSUE_ID` and `MULTICA_AGENT_SESSION` both absent).

## Key Files

| File | Description |
|------|-------------|
| `session-start.sh` | SessionStart hook — injects notepad Priority Context, workspace learnings, and AGENTS.md content into the session as `additionalContext`. Also validates multica CLI version (≥0.4.0). |
| `stop.sh` | Stop hook — enforces the verification Iron Law: writes loop checkpoint, detects DONE signal from stdin, and signals loop continuation via exit code 2 for the persistence-loop skill. |
| `pre-tool.sh` | PreToolUse hook — screens Bash commands against `tools/safe-exec.deny.list` ERE patterns; blocks destructive operations (rm -rf, git push --force, git reset --hard). |

## For AI Agents

### Working In This Directory
- All scripts must begin with the Multica session guard block (check `DISABLE_MULTICA_PLUGIN` then `MULTICA_ISSUE_ID`/`MULTICA_AGENT_SESSION`) — never remove these guards.
- Use `atomic_write()` pattern for any file writes to avoid partial-write corruption.
- Hooks communicate with Claude Code via stdout JSON (`{"hookSpecificOutput": {...}}`). Non-JSON stdout corrupts the hook protocol.
- Exit code semantics: 0 = proceed, 1 = block tool call, 2 = stop-and-retry (stop.sh persistence signal).

### Testing Requirements
- Smoke tests live in `tests/smoke/` and cover each hook's behavior.
- Run `bash tests/smoke/run-all.sh` before committing hook changes.
- Test both Multica-context and non-Multica-context paths (session guard must be exercised).

### Common Patterns
- `json_escape()` helper used in session-start.sh to safely embed arbitrary strings in JSON output.
- `log_error()` writes to `.multica/logs/hook-errors.log` — never to stdout.
- `dedup_hash()` in stop.sh prevents duplicate checkpoint comments per (issue, iteration, phase) tuple.

## Dependencies

### Internal
- `tools/safe-exec.deny.list` — deny patterns consumed by pre-tool.sh
- `skills/core/multica-workflow.md` — defines the phases that stop.sh checkpoints against
- `.multica/notepad.md` — read by session-start.sh for Priority Context injection

### External
- `multica` CLI (≥0.4.0) — required for issue/squad API calls from within hooks
- `python3` — used for version comparison and JSON parsing in session-start.sh

<!-- MANUAL: -->
