<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-06-07 | Updated: 2026-06-07 -->

# bin

## Purpose
npm-published entry point. The `install.js` script is the sole binary exposed via `package.json`'s `bin` field, invoked when users run `npx github:yangliang2/multica-agent-plugin`.

## Key Files

| File | Description |
|------|-------------|
| `install.js` | Installer — copies hooks to `~/.claude/hooks/multica/`, registers them in `~/.claude/settings.json`, and verifies the installation. Also handles `--verify` flag for post-install health checks. |

## For AI Agents

### Working In This Directory
- The installer must be idempotent: re-running it on an already-installed setup must not corrupt `settings.json`.
- Hook destination is always `~/.claude/hooks/multica/` — never the plugin directory itself (path must be stable across plugin moves/updates).
- Use `npm run verify` to run `install.js --verify` and confirm the installed state is correct.

### Testing Requirements
- Unit tests in `tests/unit/install.test.js` cover installer logic.
- Run `node --test tests/unit/install.test.js` after any change here.

## Dependencies

### External
- Node.js ≥16
- `~/.claude/settings.json` — mutated by installer to register hooks

<!-- MANUAL: -->
