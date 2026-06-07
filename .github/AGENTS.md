<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-06-07 | Updated: 2026-06-07 -->

# .github

## Purpose
GitHub Actions workflows and automation scripts for CI, code review, PR linting, and Claude-powered autofix. These run in GitHub's cloud environment, not locally.

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `workflows/` | GitHub Actions YAML workflow definitions (see `workflows/AGENTS.md`) |
| `scripts/` | Node.js scripts invoked by workflows — CI autofix, Claude-powered review and autofix (see `scripts/AGENTS.md`) |

## For AI Agents

### Working In This Directory
- Workflow changes require careful review — they run with repository secrets and can push commits.
- Scripts in `scripts/` are invoked by GitHub Actions jobs, not locally; test via workflow dispatch or act.
- Never add workflow steps that write to `~/.claude/` — workflows run in ephemeral GitHub runners.

<!-- MANUAL: -->
