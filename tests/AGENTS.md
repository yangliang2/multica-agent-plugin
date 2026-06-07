<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-06-07 | Updated: 2026-06-07 -->

# tests

## Purpose
Test suite for the plugin: unit tests for the installer and smoke tests for hook behavior under various Multica daemon conditions.

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `smoke/` | Shell-based integration tests for all three hooks — exercises real hook execution paths including deny-list, rate limiting, shell injection guards, and stop-hook evidence (see `smoke/AGENTS.md`) |
| `unit/` | Node.js unit tests for `bin/install.js` — validates installer logic without side effects (see `unit/AGENTS.md`) |

## For AI Agents

### Working In This Directory
- Run the full suite with `npm test` (unit + smoke) before any PR.
- Smoke tests require a Unix shell and `bash`; they do not require a live Multica daemon.
- Unit tests use Node.js built-in `--test` runner (no extra dependencies).

### Testing Requirements
- All hook changes must pass the relevant smoke tests in `tests/smoke/`.
- New features must include at minimum one smoke test covering the happy path and one covering the guard/error path.

## Dependencies

### External
- `bash` ≥4 — required for smoke test runner
- Node.js ≥16 — required for unit tests

<!-- MANUAL: -->
