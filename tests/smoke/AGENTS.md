<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-06-07 | Updated: 2026-06-07 -->

# tests/smoke

## Purpose
Shell-based integration tests that exercise the three hooks under realistic conditions without requiring a live Multica daemon. Each test script is independently runnable and covers a specific behavioral contract.

## Key Files

| File | Description |
|------|-------------|
| `run-all.sh` | Test runner — executes all `test-*.sh` scripts in sequence, reports pass/fail per test, exits non-zero on any failure. |
| `normalize.sh` | Helper that normalizes hook output JSON for deterministic comparison across environments. |
| `test-deny-list.sh` | Validates that `pre-tool.sh` blocks all patterns in `safe-exec.deny.list` and allows safe commands through. |
| `test-pretool-guard.sh` | End-to-end test for `pre-tool.sh` destructive-guard logic with simulated Bash tool calls. |
| `test-pretool-rate-limit.sh` | Tests rate-limit behavior in `pre-tool.sh` (if configured). |
| `test-shell-injection.sh` | Verifies that shell injection attempts via crafted Bash commands are caught by the deny list. |
| `test-static-analysis.sh` | Static checks on hook scripts: shellcheck, syntax validation, and guard block presence. |
| `test-stop-done-failing-story.sh` | Tests `stop.sh` behavior when a story fails verification — must NOT emit DONE signal. |
| `test-stop-evidence-structure.sh` | Validates that `stop.sh` evidence JSON has required fields. |
| `test-stop-evidence.sh` | Tests that `stop.sh` correctly reads and reports evidence from `.multica/state/`. |
| `test-stop-stdin.sh` | Tests `stop.sh` DONE signal detection from stdin — exercises the persistence-loop completion path. |
| `test-autofix-guards.sh` | Tests that autofix scripts in `.github/scripts/` don't bypass safety guards. |
| `test-session-start-log-error.sh` | Validates that `session-start.sh` logs errors to hook-errors.log instead of stdout. |
| `test-session-start-size-limit.sh` | Validates that `session-start.sh` enforces the 500-character Priority Context size limit. |

## For AI Agents

### Working In This Directory
- Every hook behavioral change needs a corresponding smoke test update or addition.
- Tests run without `MULTICA_ISSUE_ID` set by default — set it explicitly in the test if testing daemon-context paths.
- Use `normalize.sh` when comparing JSON output to avoid false failures from field ordering or whitespace.

### Testing Requirements
- Run with `bash tests/smoke/run-all.sh` from the project root.
- Tests must be hermetic: no network calls, no live multica daemon required.

<!-- MANUAL: -->
