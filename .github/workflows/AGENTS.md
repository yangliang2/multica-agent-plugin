<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-06-07 | Updated: 2026-06-07 -->

# .github/workflows

## Purpose
GitHub Actions workflow definitions for automated CI, code review, PR linting, and Claude-powered autofix.

## Key Files

| File | Description |
|------|-------------|
| `ci.yml` | Main CI workflow — runs `npm test` (unit + smoke) on every push and PR. |
| `code-review.yml` | Claude-powered code review workflow — invokes `scripts/claude-review.js` on PRs to post AI review comments. |
| `auto-fix.yml` | Claude-powered autofix workflow — runs `scripts/claude-autofix.js` to automatically fix lint/test failures and push a fixup commit. |
| `pr-lint.yml` | PR title and description linting — enforces conventional commit format and required PR fields. |

## For AI Agents

### Working In This Directory
- Workflow files use GitHub-managed secrets (e.g. `ANTHROPIC_API_KEY`) — never hardcode credentials.
- `auto-fix.yml` pushes commits; ensure it only runs on PRs from trusted contributors (use `pull_request_target` guard).
- When changing `ci.yml`, verify the test command matches `package.json` scripts exactly.

<!-- MANUAL: -->
