<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-06-07 | Updated: 2026-06-07 -->

# tests/unit

## Purpose
Node.js unit tests for `bin/install.js` using the built-in `node:test` runner. Validates installer logic (hook file copying, settings.json mutation, idempotency) without side effects on the host system.

## Key Files

| File | Description |
|------|-------------|
| `install.test.js` | Unit tests for the installer — covers hook registration, settings.json patching, idempotency on re-run, and `--verify` flag behavior. |

## For AI Agents

### Working In This Directory
- Run with `node --test tests/unit/install.test.js` — no test framework to install.
- Tests must mock filesystem operations; do not write to `~/.claude/` during unit tests.
- Add a test case for every new installer code path.

### Testing Requirements
- All tests must pass before merging changes to `bin/install.js`.

## Dependencies

### External
- Node.js ≥16 (`node:test` built-in runner)

<!-- MANUAL: -->
