<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-06-07 | Updated: 2026-06-07 -->

# .githooks

## Purpose
Local git hooks for developer workflow enforcement. Installed via `git config core.hooksPath .githooks` or equivalent.

## Key Files

| File | Description |
|------|-------------|
| `pre-push` | Pre-push hook — runs `npm test` before allowing a push to any branch, preventing broken builds from reaching the remote. |

## For AI Agents

### Working In This Directory
- These hooks run in the developer's local git environment, not in CI.
- `pre-push` failures should be fixed, not bypassed with `--no-verify`.
- Adding a new hook: create the file, make it executable (`chmod +x`), and document it here.

<!-- MANUAL: -->
