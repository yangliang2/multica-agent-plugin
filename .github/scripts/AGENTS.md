<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-06-07 | Updated: 2026-06-07 -->

# .github/scripts

## Purpose
Node.js scripts invoked by GitHub Actions workflows. These interact with the GitHub API and the Anthropic Claude API to automate review and autofix tasks on PRs.

## Key Files

| File | Description |
|------|-------------|
| `claude-review.js` | Posts AI-generated code review comments on PRs using the Claude API. Reads diff and posts structured feedback as PR review comments via GitHub API. |
| `claude-autofix.js` | Applies Claude-generated fixes to lint/test failures and pushes a fixup commit. Invoked by `auto-fix.yml`. |
| `ci-autofix.js` | Lightweight CI-specific autofix — handles deterministic fixes (formatting, import sorting) without Claude API calls. |

## For AI Agents

### Working In This Directory
- These scripts use `ANTHROPIC_API_KEY` and `GITHUB_TOKEN` from the Actions environment — never assume these are set locally.
- `claude-autofix.js` pushes commits — ensure the git identity is set in the workflow before invoking.
- Changes here must be tested via the corresponding workflow (use `workflow_dispatch` trigger).

## Dependencies

### External
- Anthropic Claude API — used by `claude-review.js` and `claude-autofix.js`
- GitHub API (`GITHUB_TOKEN`) — used by all three scripts for PR interaction

<!-- MANUAL: -->
