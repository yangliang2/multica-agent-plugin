# Changelog

## [2.3.0] - 2026-06-01

### Added (T07 — HITL replay, REQ-06-01/02)

- **HITL state tracking** (`loop.json`): new `open_hitls` / `resolved_hitls`
  arrays. Every posted `[HITL]` question is recorded with `question_id`,
  `asked_at`, `tier`; answered entries move to `resolved_hitls` with `answer`
  and `answered_at`. Schema-validated in `hooks/stop.sh` (lists of objects),
  backward compatible — absent fields default to `[]`.

- **Replay detection on resume** (`hooks/session-start.sh`): when `open_hitls`
  is non-empty, the hook fetches recent comments, matches each `question_id` to
  a human reply (thread reply to the agent's `[HITL]` comment, or direct
  `question_id=` mention), injects the answers as "HITL Replies Detected"
  context, and moves entries open → resolved. The agent never re-posts an
  answered question; free-form replies are accepted (REQ-06-01).

- **48h hard timeout** (`hooks/session-start.sh`): an `[HITL]` question
  unanswered past `MULTICA_HITL_HUMAN_TIMEOUT_HOURS` (default 48) now injects a
  hard-timeout signal directing the agent to post a `[loop-stuck]` notice and
  stay `blocked` — takes precedence over the 24h conservative-option
  auto-degradation, and guarantees stalls leave a visible timeline trace.

- **Docs**: `skills/core/hitl-protocol.md` gains "HITL State Tracking
  (loop.json)" and the 48h hard-timeout rule; `skills/core/multica-workflow.md`
  schema table extended; `docs/HUMAN-GUIDE.md` explains free-form replies and
  the 48h behavior to reviewers.

- **Tests**: `tests/smoke/test-session-start-hitl-replay.sh` (6 cases: thread
  match, direct-mention match, unanswered stays open, resolved carries answers,
  idempotent re-run, valid JSON output).

### Added (T06 — learning pipeline, REQ-05-01/02/04)

- **Correction-signal capture** (`hooks/stop.sh`): on clean session exits the hook
  scans recent issue comments (7-day window anchored to `loop.json.start_time`)
  for human-authored `[wrong: ...]` / `[revise: ...]` signals and writes each as
  a repo-scoped learning with `confidence=9` — no agent involvement. Dedup key is
  the first 16 hex chars of `sha256(insight[:200])`; a re-seen key is reinforced
  (confidence reset to 9, `recorded_at` refreshed). Writes are atomic under an
  flock-protected tmp-rename. Agent-authored comments are ignored. This makes the
  behavior documented in HUMAN-GUIDE §2 actually exist.

- **Repo-correction injection** (`hooks/session-start.sh`): repo-scoped learnings
  now surface in a dedicated "Previous corrections on this repo:" context section
  including touched file paths for relevance filtering.

### Changed (T06)

- **Decay aligned to spec** (`tools/curate-memory.sh`): confidence decays −1 per
  week since `recorded_at` (floor 1), replacing the previous −2 (>90d) / −4 (>180d)
  step decay. Entries are pruned only when confidence < 4 AND `recorded_at` is
  older than 30 days; every prune is logged to `.multica/curate-memory.log` as
  `[learning-pruned key=X confidence=Y]` (no silent removal). A `last_decayed_at`
  marker makes repeated curate runs idempotent (no double-decay).

- **Self-checkout routing fix** (`hooks/stop.sh`): when `MULTICA_WORKDIR` is
  itself the git checkout matching a repo-scoped learning, routing now keeps the
  entry in place instead of appending it to the same file and then losing it in
  the issue-level rewrite.

### Tests (T06)

- `tests/smoke/test-stop-correction-capture.sh` (6 cases), `test-curate-decay.sh`
  (6 cases), `test-session-start-corrections.sh` (4 cases). `run-all.sh` now also
  runs the previously unregistered `test-stop-phase-dispatch.sh`. Scenario 8 in
  `run-claude.sh` updated to relative timestamps (hardcoded ancient dates now
  trigger the spec-aligned prune, which is decay behavior, not dedup behavior).

### Changed (honesty — review H2/H3)

- **H2 — Removed vaporware "adapters" claims** (`README.md`): the repository has
  no `adapters/` directory and no harness-specific integration shims. Removed the
  "and adapters" phrasing from the description and "What This Is" sections, dropped
  the `adapters/` line from the architecture tree, and rewrote the "Supported
  Frameworks" table. It now states plainly that only Claude Code is supported and
  that Codex / Gemini CLI / OpenCode are **not implemented** — replacing the
  aspirational "Roadmap" rows that implied work in progress.

- **H3 — Hardened the evidence gate** (`hooks/stop.sh`): a story marked
  `passes: true` now requires its evidence file to contain BOTH a `command:` line
  and an integer `exit_code:` line equal to `0`. The previous check accepted any
  single structured field — including a bare prose `summary:` — which let an agent
  self-certify with no proof a command ever ran. The hook now also cross-checks
  the recorded exit code: `passes: true` with a non-zero `exit_code:` is rejected.

- **H3 — Documented the gate's limits honestly** (`skills/core/verification.md`):
  tightened the documented evidence rules to match the hook, and added a "What
  this gate can and cannot enforce" section making clear the check is structural,
  not semantic — it cannot verify the recorded command is relevant or that the
  exit code was transcribed faithfully.

### Added

- **`tests/smoke/test-stop-evidence-structure.sh`**: expanded from 4 to 7 cases —
  prose-`summary:`-only is now rejected, `command:` + `exit_code: 0` is accepted,
  non-zero `exit_code:` is rejected even when `passes: true` (honesty
  cross-check), and `command:` without `exit_code:` is rejected.

## [2.2.0] - 2026-06-01

### Fixed

- **Version sync**: `VERSION`, `package.json`, and `.claude-plugin/marketplace.json`
  were not bumped in v2.1.0. Corrected to `2.2.0`.

- **M7 — Stop hook exit 2 feedback** (`hooks/stop.sh`): both `exit 2` (block)
  paths now write a structured JSON message to stdout before exiting. Claude Code
  relays this `hookSpecificOutput.additionalContext` to the model, preventing
  the session from stalling with no context after a block.

## [2.1.0] - 2026-06-01

### Fixed (security hardening — review C1/C6)

- **C6 — fail-closed guard** (`hooks/pre-tool.sh`): when `safe-exec.deny.list`
  cannot be found (e.g. `MULTICA_PLUGIN_ROOT` points to a wrong directory), the
  destructive guard now blocks all Bash tool calls with `exit 1` instead of
  silently disabling itself (`exit 0`). This closes the fail-open path that
  allowed arbitrary commands when the deny list was missing.

- **C1 — Stop hook stdin contract** (`hooks/stop.sh`): DONE signal detection now
  follows the Claude Code hook contract (stdin JSON) instead of the
  `CLAUDE_TOOL_OUTPUT` environment variable, which Claude Code never sets.
  Detection order: (1) raw stdin content, (2) `transcript_path` file referenced
  in stdin JSON, (3) `MULTICA_OUTPUT_FILE` daemon override. Nonce verification
  (H4) updated to use the same three-path lookup. The `CLAUDE_TOOL_OUTPUT` env
  var path has been removed.

### Added

- **`tests/smoke/test-pretool-guard.sh`**: new Test 4 — verifies that a missing
  deny list results in `exit 1` (fail-closed), not `exit 0`.

- **`tests/smoke/test-stop-stdin.sh`**: three cases covering C1 stdin contract —
  DONE in raw stdin is accepted, missing DONE in stdin blocks, DONE in
  `transcript_path` file is accepted.

## [2.0.0] - 2026-05-30

### Fixed (workflow hardening)

- **Commit message injection**: both `code-review.yml` and `auto-fix.yml` no
  longer interpolate Claude-generated `FIX_ANALYSIS` directly into `git commit -m`.
  Commit messages are written via temporary files and passed with `git commit -F`.

- **Exit code capture**: `code-review.yml` now captures `node .github/scripts/claude-review.js`
  exit code correctly (`rc=$?`) before writing `exit_code` to `GITHUB_OUTPUT`.

- **Over-broad staging**: both workflows now stage only `MODIFIED_FILES` emitted by
  the autofix scripts instead of `git add hooks/ tools/ bin/ tests/`.

- **GITHUB_ENV injection**: `claude-autofix.js` now writes `FIX_ANALYSIS` and
  `MODIFIED_FILES` using multiline-safe `<<EOF` blocks rather than raw `KEY=value`
  interpolation. Prevents newline / special-char corruption.

- **Workflow YAML robustness**: extracted the large inline Node.js block from
  `auto-fix.yml` into `.github/scripts/ci-autofix.js`, making the workflow valid
  strict YAML and easier to test.

### Added

- **`.github/PULL_REQUEST_TEMPLATE.md`**: standardized PR structure with required
  `Summary`, `Risk`, `Test plan`, and `Rollback` sections.

- **`.github/workflows/pr-lint.yml`**: PR title/body quality gate. Enforces:
  - title format: `<type>: <meaningful description>`
  - no vague titles like `wip`, `update`, `fix bug`
  - body must contain `## Summary`, `## Risk`, `## Test plan`, `## Rollback`
  - Summary must contain at least one non-empty bullet
  - Test plan must contain at least one checkbox item

## [1.9.0] - 2026-05-30

### Added

- **`tests/smoke/test-static-analysis.sh`**: 4 static pattern checks on hook
  source files — python3 -c shell-var injection, duplicate trap EXIT, bare
  `git add`, multica comment calls without error logging.

- **`tests/smoke/test-shell-injection.sh`**: adversarial input tests for
  session-start.sh and pre-tool.sh with paths/IDs containing spaces, quotes,
  `$`, `|`, `;`, and command substitution sequences. Verifies no injection
  artifacts are created.

### Fixed

- **`test-pretool-rate-limit.sh`**: merged two separate `trap ... EXIT`
  registrations into one to avoid silent trap replacement.

## [1.8.0] - 2026-05-30

### Fixed

- **GitHub Actions Node.js 24 migration**: pinned all actions to latest v4
  patch releases (`actions/checkout@v4.3.1`, `actions/setup-node@v4.4.0`,
  `actions/upload-artifact@v4.6.2`, `actions/download-artifact@v4.3.0`)
  across `ci.yml`, `code-review.yml`, and `auto-fix.yml`. Avoids the
  forced Node.js 24 switch on 2026-06-16.

### Added

- **`tests/smoke/test-stop-evidence-structure.sh`**: 4 cases covering H3
  evidence content validation — freeform text rejected, `exit_code:` /
  `summary:` fields accepted, empty file still rejected.

- **`tests/smoke/test-pretool-rate-limit.sh`**: 3 cases covering M8
  rate-limit — rate file created on first blocked call, not updated within
  60s window, not created in non-daemon session.

- **`tests/smoke/test-session-start-size-limit.sh`**: 3 cases covering M10
  learnings size guard — normal file injected, >1000 lines skipped with
  warning in context, output remains valid JSON.

## [1.7.0] - 2026-05-30

### Fixed

- **H6 — `hooks/session-start.sh`**: replaced all `awk -F'"'` JSON parsing
  with a single `python3` call that reads `loop.json` fields (`active`,
  `iteration`, `phase`, `next_story`) atomically. Also replaced awk-based
  `hitl-bounces.json` parsing with python3. Eliminates silent failures on
  Alpine/busybox where awk field-splitting on JSON is unreliable.

- **H3 (partial) — `hooks/stop.sh`**: evidence files must now contain at
  least one structured field (`exit_code:`, `command:`, `output_hash:`, or
  `summary:`) in addition to being non-empty. Bare freeform text no longer
  satisfies the evidence gate.

### Added

- **`tools/curate-memory.sh` auto-run**: `stop.sh` DONE path now automatically
  invokes `curate-memory.sh` when `learnings.jsonl` exists. Knowledge dedup
  and decay runs on every successful DONE instead of requiring manual
  invocation. Errors are non-blocking (logged to `hook-errors.log`).

## [1.6.0] - 2026-05-30

### Fixed

- **C6 — `tools/safe-exec.deny.list` + `hooks/pre-tool.sh`**: destructive guard
  upgraded from substring (`grep -iF`) to ERE (`grep -iE`) matching. New patterns
  cover previously bypassable vectors: `rm  -rf /` (double-space), `find -delete`,
  `find -exec rm`, `curl|bash`, `wget|sh`, `base64 -d|bash`, reverse shells
  (`/dev/tcp/`, `nc -e`, `socat exec:`), and Python/Perl one-liner remote
  execution. `git push -f` now requires trailing whitespace to avoid false
  positives on `-force`. Missing deny list now logged and fails open with a
  log entry rather than silently passing all commands.

- **M8 — `hooks/pre-tool.sh`**: destructive-guard issue comment no longer
  pastes the raw command. Commands ≤80 chars are shown as-is; longer commands
  are truncated to 80 chars with a sha256 hash suffix to avoid leaking secrets.
  Rate limit: at most 1 comment per minute per issue (enforced via
  `.multica/state/{issue_id}/pretool-comment-rate.txt`).

- **M1 — `hooks/pre-tool.sh`**: added `log_error()` function and proper error
  logging for rate-limit events and failed comment posts. Eliminates silent
  failure paths in the destructive guard.

## [1.5.0] - 2026-05-29

### Fixed

- **H4 — `hooks/stop.sh` + `hooks/session-start.sh`**: `<promise>DONE</promise>` signal is
  now nonce-bound. On each loop resume, `session-start.sh` generates a stable per-session
  nonce and writes it to `.multica/state/{issue_id}/done-nonce.txt`; the nonce is injected
  into the `## Loop State` context section as `Emit <promise>DONE:{nonce}</promise> when
  complete.` `stop.sh` checks for the matching `DONE:{nonce}` form when a nonce file is
  present; plain `DONE` (without nonce) is rejected. Nonce file is removed on clean exit.
  This closes the magic-string bypass identified in the internal review.

- **H7 — `hooks/stop.sh`**: added `flock -x` advisory lock on
  `.multica/state/{issue_id}/.multica.lock` before any state-file writes (`loop.json`,
  `hitl-bounces.json`, `learnings.jsonl`). Gracefully degrades on systems without `flock`.

- **H9 — `hooks/session-start.sh`**: runtime version check for multica CLI at session start.
  If installed version is below `0.4.0`, injects a warning into `additionalContext` and logs
  to `hook-errors.log`. Does not block the session.

- **M4 — `bin/install.js`**: `--uninstall` now removes the `MULTICA_PLUGIN_ROOT` and
  `MULTICA_AGENT_SESSION` export lines written to `~/.bashrc` / `~/.zshrc`. Uses the same
  shell-profile detection as install; collapses blank lines left behind.

- **M6 — `hooks/session-start.sh`**: stale-learning issue comments are now batched into a
  single comment per calendar day (one `.marker` file per issue per day). Eliminates the
  per-key per-resume comment flood.

- **M9 — `hooks/stop.sh`**: notepad Working Memory prune (7-day cutoff) is now extracted
  into a `prune_notepad()` function and called on every stop hook exit — not only on the
  DONE path. Long-running sessions that never reach DONE are now also pruned.

- **M5 — `hooks/hooks.json`**: dead artifact removed. The file was never read by `install.js`
  or any other tool, and had drifted from the actual hook registration logic.

### Changed

- **`README.md`**: multica CLI minimum version corrected from `0.3.4` to `0.4.0` (matches
  `KNOWN-LIMITATIONS.md` and the new runtime check).

- **`.claude-plugin/marketplace.json`**: version synced to `1.5.0`.

- **Branch protection**: `master` branch now requires all four CI jobs (`Bash syntax check`,
  `shellcheck`, `Smoke tests`, `Node.js unit tests`) to pass before a push is accepted.
  This closes the gap where CI-failing commits could be pushed directly to `master`.

## [1.4.0] - 2026-05-28

### Fixed (engineering quality / tech debt)

- **`hooks/session-start.sh`** — `high_conf` awk ERE/BRE filter replaced with
  Python. The previous `/"confidence":[[:space:]]*([89]|10)/` pattern used ERE
  syntax that is silently broken on busybox/mawk (Alpine containers). Now the
  raw learnings file is passed directly to the existing python3 batch call;
  Python handles confidence≥7 filtering, recent-10 + dedup logic, and C5
  validation in a single pass. The awk fallback path is removed.

- **`uninstall.sh`** — now correctly removes hooks installed by `npx` (paths
  under `~/.claude/hooks/multica/`). Previously matched only `PLUGIN_ROOT`
  paths, leaving npm-installed hooks dangling. Prefers `node bin/install.js
  --uninstall`; falls back to direct python3 removal with atomic write.

- **`hooks/stop.sh`** — added `loop.json` schema validation before processing:
  `issue_id` and `stories[].id` validated against `^[A-Za-z0-9._-]{1,64}$`;
  `iteration` and `max_iterations` range-checked; `phase` checked against
  whitelist. Malformed files are rejected with `log_error` + `exit 0`
  (non-blocking — Claude Code stop is not blocked by bad plugin data).

- **`KNOWN-LIMITATIONS.md`** — deny list section rewritten to clearly state it
  is a convenience check, not a security control; lists bypass vectors;
  recommends OS-level sandboxing for production multi-tenant deployments.

### Added

- **`tests/unit/install.test.js`** — 15 unit tests for `bin/install.js`:
  `parseJsonc` (trailing comma, BOM, URL in string, block comment, escaped
  quote, invalid JSON) and `CLAUDE_SETTINGS_PATH` path-escape validation
- **`package.json`** — `test:unit` and `test:smoke` scripts; `npm test` now
  runs unit tests first, then smoke suite
- **`.github/workflows/ci.yml`** — `shellcheck` job (warning level) and `unit`
  job added alongside existing `syntax` and `smoke` jobs

---

## [1.3.0] - 2026-05-27

### Fixed (P0 security — all confirmed via reproduction)

- **C7 — `hooks/stop.sh`**: evidence gate path traversal fixed — `issue_id` and
  `story_id` from `loop.json` are now validated against `^[A-Za-z0-9._-]{1,64}$`
  and `Path.resolve()` checks the resulting path does not escape the state dir;
  python3 exception now exits 1 (fail-closed) so a corrupt loop.json cannot
  silently bypass the gate; `stories=[]` now emits `NO_STORIES` and blocks DONE

- **C5 addendum — `hooks/session-start.sh`**: insight sanitizer now rejects any
  entry containing control chars or newlines (ord < 0x20) before other checks,
  capping at 280 chars; this closes the `\n`-based STALE_KEY injection channel;
  UNSAFE_CHARS_RE extended with `{}|`

- **pre-tool.sh fallback — `hooks/pre-tool.sh`**: `python3 except` blocks now
  call `sys.exit(1)` instead of `pass`, so `|| echo "${CLAUDE_TOOL_NAME:-}"`
  fallback actually triggers when stdin JSON is absent/malformed; previously
  all tools were silently allowed through on stdin-parse failure

- **parseJsonc — `bin/install.js`**: trailing comma before `}` or `]` now stripped
  before `JSON.parse` (regex `,(\s*[}\]])`); BOM stripped; `readSettings`
  catch block now calls `process.exit(1)` instead of returning `{}`—corrupt
  settings.json no longer silently overwrites user config

- **install.sh**: now exits 1 immediately with a clear error pointing to
  `npx multica-agent-plugin`; the script never copied hooks to
  `~/.claude/hooks/multica/` and would produce a silently broken installation

### Changed

- **`.claude-plugin/marketplace.json`**: version synced to 1.3.0
- **`tools/doctor.sh`**: `MULTICA_AGENT_SESSION` default shown as `0` (was `1`
  — contradicted the v1.1.0 H1 fix); hook "not registered" message now points
  to `npx multica-agent-plugin` instead of broken `bash install.sh`
- **`docs/QUICKSTART.md`**: two broken CLI commands fixed:
  `multica issue assign ISS-42 --agent default` → `--to "Lambda"`;
  `multica issue comments ISS-42 --follow` → `multica issue comment list ISS-42`

### Note on evidence gate (v1.2.0 omission)

v1.2.0 introduced an evidence file gate in `hooks/stop.sh` (every `passes: true`
story requires `.multica/state/{issue_id}/evidence/{story_id}.txt`) but this was
not mentioned in the v1.2.0 CHANGELOG. The gate is documented in
`skills/core/verification.md` (Gate Function step 4) and
`skills/advanced/persistence-loop.md` (Step 5). If `<promise>DONE</promise>` is
unexpectedly rejected with "missing evidence files", create the evidence file
for each story before re-emitting the signal.

---

## [1.2.0] - 2026-05-27

### Fixed (P1 — security hardening + reliability)

- **C3 — `hooks/stop.sh`**: `git commit` now scoped to `-- "$_learnings"` pathspec.
  Previously `git commit` without pathspec would silently bundle any unrelated
  staged files into the `chore(knowledge): update learnings` commit.

- **C4 — `bin/install.js`**: three-part `settings.json` safety fix:
  - JSONC parser replaced with a state-machine implementation that correctly
    skips `//` only outside string literals (prevents mangling URLs like `https://`)
  - Atomic write via `tmp + fs.renameSync` (no corrupt file on mid-write crash)
  - Backup to `.bak` before every write
  - `CLAUDE_SETTINGS_PATH` env var rejected if it points outside `~/.claude/`

- **C5 — `hooks/session-start.sh`**: `learnings.jsonl` treated as untrusted input:
  - `key` field validated against `^[A-Za-z0-9._-]{1,64}$` — invalid keys skipped
  - `files[]` entries reject absolute paths and any path containing `..`
  - `insight` field stripped of markdown structural characters before context injection

### Changed

- **M2 — `hooks/session-start.sh`**: learnings processing now uses a single
  `python3` call for all entries instead of one fork per entry (≈20× fork reduction
  per SessionStart). Data passed via temp file to avoid bash pipe+heredoc stdin conflict.

- **`tests/smoke/run-claude.sh`**, **`test-session-start-log-error.sh`**: test
  fixtures updated to use relative paths in `files[]` (correct per C5 — absolute
  paths are now rejected as potential path traversal).

### Tests

All 5 smoke test files pass (50/50 scenarios, 0 XFAIL).

---

## [1.1.0] - 2026-05-27

### Fixed (P0 — "Take-back trust" sprint)

- **C1 — `hooks/pre-tool.sh`**: hook input now read from stdin JSON (Claude Code
  PreToolUse contract) instead of `CLAUDE_TOOL_NAME`/`CLAUDE_TOOL_INPUT` env vars
  which Claude Code never sets. Deny list now actually executes. Fallback to env
  vars retained for test harness compatibility.

- **C2 — `hooks/session-start.sh`**: `log_error` function now defined locally in
  session-start.sh. Previously only defined in stop.sh; under `set -euo pipefail`
  any stale-learning warning path would abort the hook before emitting JSON output.

- **H6 — `hooks/stop.sh`**: JSON field extraction and story-completion check
  replaced with `python3 json.load` (robust to compact/spaced JSON and escaped
  strings). Previous `awk -F'"'` parser and `grep -qF '"passes": false'` (space-
  sensitive) silently failed on compact JSON like `"passes":false`.

- **H1 — All hooks**: `MULTICA_AGENT_SESSION` default changed from `1` to `0`.
  Previous default meant hooks activated in every Claude Code session, contradicting
  the README claim "only activates in Multica daemon sessions". Daemon must now
  explicitly set `MULTICA_AGENT_SESSION=1` (which it does via env config).

- **H8 — `.claude-plugin/marketplace.json`**: version bumped to 1.1.0 to match
  package.json. Was stuck at 0.8.0, so marketplace installs got stale plugin.

### Changed

- **`hooks/stop.sh`**: `loop.json` update on DONE path now uses `python3` for
  atomic JSON round-trip (preserves all fields, avoids sed regex fragility).

- **`tests/smoke/run-claude.sh`**: added `MULTICA_AGENT_SESSION=1` to all
  session-start.sh invocations (Scenarios 3, 5, 9) — required after H1 fix.

- **`tests/smoke/test-session-start-log-error.sh`**: removed stale XFAIL markers
  now that C2 is fixed; added stale-learning-in-context assertion.

### Tests

- All 5 smoke test files pass (50/50 scenarios, 0 XFAIL).

---

## [1.0.0] - 2026-05-26

### Added
- **`docs/abi/cli-outward.md`** — expanded from 5 to 12 commands: added `squad.activity`,
  `issue.create`, `issue.create.child`, `issue.metadata.list`, `issue.metadata.delete`,
  `autopilot.get`, `issue.comment.list.thread`; each with synopsis, flags, JSON schema,
  and usage notes; anchor index updated to match
- **`docs/cli-reference.md`** — added full `multica squad activity` command block
  with help text, outcome semantics table, and examples

### Changed
- **`docs/abi/cli-outward.md`** — `issue comment add` usage notes: clarified that
  `--idempotency-key` does NOT exist in the CLI; client-side dedup hash in comment
  body is the correct approach; version declaration updated to 1.0.0

### Resolved (source code research)
- Briefing-to-disk path: daemon writes squad briefing into `{workDir}/CLAUDE.md`
  via `InjectRuntimeConfig` — plugin's existing CLAUDE.md detection is correct
- Roster staleness: roster is re-injected on every squad-leader claim — always current
- Child-issue backlink: daemon auto-notifies parent on child done — leader needs no manual backlink
- `MULTICA_HARNESS_CAPS`: daemon does not inject this env var — capabilities are
  static, written at adapter install time only

---

## [0.9.0] - 2026-05-26

### Fixed
- **`hooks/pre-tool.sh`** — was blocking every tool call in daemon mode because
  `multica safe-exec` does not exist in the multica CLI; replaced with a local
  deny-list check against `tools/safe-exec.deny.list` (covers force-push,
  `rm -rf /`, DROP DATABASE, etc.); non-Bash tools pass through unmodified

### Added
- **`tools/learning-review.sh`** — reviewer-facing summary of all accumulated
  learnings: confidence scores, stale status (source file changed), type tags,
  and archived entries below confidence threshold
- **Squad HITL Routing section** in `hitl-protocol.md` — defines `[HITL:leader]`
  comment format with explicit "← This is routed to the squad leader, not to you"
  prefix so reviewers are never confused about who is expected to act

### Changed
- **`hooks/stop.sh`** — `[loop-complete]` comment now includes keys of learnings
  added this run (extracted via `git diff --cached`) and a metadata review hint;
  git `add` happens before the comment so keys are available at post time
- **`hooks/session-start.sh`** — when a stale learning is detected and injected,
  a `[knowledge-warning]` comment is posted to the issue so reviewers can see the
  agent's knowledge state in the issue timeline
- **`skills/core/hitl-protocol.md`** — `[HITL:timeout]` comment format now reads
  "Auto-degraded after Nh without reply. Chose conservative option: <desc>.
  If incorrect, reply to this comment to override." — clearly marks auto-degradation
  for reviewers; old format omitted the "auto-degraded" framing
- **`skills/core/multica-workflow.md`** — Phase 2 plan comment rule: when a prior
  learning materially influences the approach, agent must cite it inline
  (`Using prior learning "<key>" (confidence:N): <rationale>. Override: reply if
  incorrect before execution starts.`) so reviewers can correct before execute

---

## [0.8.0] - 2026-05-26

### Added
- **npm package distribution** — `npx multica-agent-plugin` installs hooks and
  configures environment automatically; no manual shell profile editing required
- **Claude Code plugin marketplace** — `/plugin marketplace add <url>` installs
  skills via Claude Code's native plugin system
- **Stable hook paths** — hooks installed to `~/.claude/hooks/multica/` (decoupled
  from plugin directory); moving the plugin no longer breaks hooks
- **`--verify` flag** — `npx multica-agent-plugin --verify` checks deps, hook
  registration, and settings.json status
- **`--uninstall` flag** — clean removal of hooks and settings.json entries
- **`.claude-plugin/plugin.json`** and **`.claude-plugin/marketplace.json`** manifests

### Changed
- `install.sh` deprecated in favor of `npx multica-agent-plugin`
- `hooks/hooks.json` updated to reference `~/.claude/hooks/multica/` stable paths
- `MULTICA_PLUGIN_ROOT` no longer required to be set manually (installer handles it)

---

## [0.7.0] - 2026-05-26

### Added
- **Metadata deep integration** — agents now read `blocked_reason` from issue
  metadata on resume, pin it on HITL blocked, and clear it on completion;
  Phase 1 (discover) reads metadata first for faster context recovery
- **Autopilot run-only awareness** — session-start detects `MULTICA_AUTOPILOT_RUN_ID`
  and injects Autopilot Mode context (no issue calls, stdout-only output);
  stop.sh exits cleanly without loop.json checks in autopilot sessions
- **Squad leader capacity probe** — before Strategy A delegation, leader checks
  member in_progress count; skips members at capacity (≥6); escalates to
  `[HITL:human]` when all members full
- **Blocked restart protection** — session-start detects unanswered HITL in
  `hitl-bounces.json` and prepends strong warning before agent does any work
- **`tools/loop-status.sh`** — one-command task progress viewer: iteration,
  phase, per-story pass/fail with progress bar, HITL pending status
- **New CLI anchors**: `<<cli:issue.metadata.list>>`, `<<cli:issue.metadata.set>>`,
  `<<cli:issue.metadata.delete>>`, `<<cli:autopilot.get>>`

---

## [0.6.0] - 2026-05-25

### Added
- **Plugin isolation guards** — all hooks check `MULTICA_ISSUE_ID` or
  `MULTICA_AGENT_SESSION=1` before activating; `DISABLE_MULTICA_PLUGIN=1`
  disables entirely; resolves conflicts with OMC/GSD/Superpowers when running
  local Claude Code sessions alongside Multica daemon
- **`tools/doctor.sh`** — one-command diagnostics: deps, env vars, hook
  registration, conflict detection with other plugins, recent hook errors
- **Squad Mode Walkthrough** in `docs/HUMAN-GUIDE.md` — 7-step guide covering
  prerequisites, member installation requirement, parallel execution explanation,
  HITL two-tier routing, and leader summarization lifecycle
- **Compatibility table** in README (multica >= 0.3.4, python3 >= 3.8, git 2.x)
- **Daemon deployment section** in QUICKSTART with `MULTICA_AGENT_SESSION` and
  OMC/GSD coexistence instructions (`MULTICA_AGENT_SESSION=0` in local shell)
- **Docs split**: `USAGE.md` → `QUICKSTART.md` + `HUMAN-GUIDE.md` + `AGENT-CONTRACT.md`

### Changed
- `stop.sh`: `loop-complete` comment includes learnings count for visibility
- `AGENTS.md`: added prohibition on invoking OMC/Superpowers interactive skills
  (AskUserQuestion is disabled in daemon mode)
- QUICKSTART.md: prerequisites table with purpose/install columns, multica
  install link, smoke test caveat (does not verify daemon integration)

---

## [0.5.0] - 2026-05-24

### Added
- **Configurable thresholds** (`capabilities/claude-code.json` `thresholds` field) — HITL timeout,
  strike limit, context budget percentages, and loop max iterations are now configurable;
  session-start injects them as `MULTICA_HITL_TIMEOUT_HOURS`, `MULTICA_HITL_STRIKE_LIMIT`,
  `MULTICA_CONTEXT_CHECKPOINT_PCT`, `MULTICA_CONTEXT_BLOCKED_PCT`, `MULTICA_LOOP_MAX_ITERATIONS`
- **HITL 24h timeout auto-degradation** — after `$MULTICA_HITL_TIMEOUT_HOURS` hours without
  reviewer reply, session-start injects `[HITL:timeout]` signal; agent proceeds with most
  conservative option and posts explanatory comment (multica has no built-in reaper)
- **`[phase]` comment prefix** — phase transition comments now include `[phase] X→Y` prefix
  so reviewers can quickly scan issue timeline to understand agent progress
- **Memory consolidation one-shot trigger** — `consolidation-prompt.txt` written by `stop.sh`
  is now consumed by `session-start.sh` as the first task of the next session (no external
  scheduler required); file is deleted after injection (single-use)

### Changed
- `skills/core/multica-workflow.md`: context budget thresholds reference env vars instead of
  hardcoded percentages
- `skills/advanced/persistence-loop.md`: max_iterations references `$MULTICA_LOOP_MAX_ITERATIONS`
- `CLAUDE.md`: added note that hook paths are resolved at install time

### Documentation
- `KNOWN-LIMITATIONS.md`: prominent ⚠️ warning that learnings sync requires a git repository;
  added manual workaround steps

---

## [0.4.0] - 2026-05-24

### Added
- `tools/curate-memory.sh` — learning 去重（last-wins by key）、confidence 衰减（>90d: -2, >180d: -4）、归档（conf<3），原子写
- `hooks/stop.sh` DONE 路径：git commit `.multica/learnings.jsonl`（多机知识同步）、notepad Working Memory 7天过期清理、consolidation-prompt.txt 写入（供 haiku subagent 记忆整合）
- `hooks/session-start.sh`：stat-based staleness 检测（源文件不存在或 mtime 更新则标 [possibly stale]），python3 可用时生效

### Knowledge Management Design
Based on deep research of Hermes Agent (Curator + skill lifecycle), Graphify (stat-based dedup), and LLM Wiki (stale_since causal propagation):
- No TTL — staleness is causal (file changes), not time-based
- Write-time append-only, offline curate for dedup
- Confidence as weight, not deletion signal (archive instead of delete)

---

## [0.3.0] - 2026-05-24

### Added
- `skills/advanced/subagent-dispatch.md` — subagent 派发规范：模型路由表（haiku/sonnet/opus）、fresh context 原则（完整 prompt，不引用历史）、Task() 示例、output contract
- `capabilities/claude-code.json`: 新增 `model_routing` 字段（fast/standard/deep）
- `hooks/session-start.sh`: 注入 `MULTICA_MODEL_FAST/STD/DEEP` 环境变量（由 model_routing 驱动）
- `hooks/session-start.sh`: 读 `.multica/state/<issue_id>/hitl-bounces.json` 注入 3-strike 计数到 context

### Changed
- `hooks/stop.sh`: leader 跳过 squad activity 时直接调用 `multica squad activity failed`（不再只写 warning 等下次提示）
- `skills/core/squad-member-workflow.md`: bounce 计数写入 `hitl-bounces.json` 文件（程序可读，不只靠 metadata.set）
- `skills/core/multica-workflow.md`: 新增 context budget 感知规则（>35% 正常，≤35% checkpoint，≤25% blocked）

### Reliability Improvements
Replaced LLM-discipline mechanisms with program-enforced ones:
- 3-strike count: file-based storage → session-start injection (high reliability)
- squad activity: event-after warning → direct CLI call (high reliability)
- Model routing: skill text description → env var injection (high reliability)

---

## [0.2.0] - 2026-05-23

### Added
- `skills/core/squad-leader-workflow.md` — Squad leader 工作流：coordinate-don't-execute、两种委派策略决策矩阵（子 issue 并行 vs @mention 串行）、mandatory squad activity、HITL reply no-mention 规则、3-strike 升级
- `skills/core/squad-member-workflow.md` — Squad member 工作流：两级 HITL（[HITL:leader] 优先，[HITL:human] 作为 fallback）、独立 3-strike 计数、完成不 @mention 防 double-fire
- `hooks/session-start.sh`: Section 4 Squad leader 检测（grep `{workDir}/CLAUDE.md`）+ roster 注入
- `hooks/stop.sh`: squad activity passive audit（非阻塞，exit 0）
- `docs/cli-reference.md`: 新增 3 个 anchor（squad.activity、issue.create.child、issue.comment.list.thread）
- `tools/render-anchors.sh`: 未知 anchor 时 exit 2 防漂移
- `capabilities/claude-code.json`: squad-leader/squad-member capability flags
- Smoke scenarios 5/6/7（总计 44 → 44 通过）

### Design Decisions (sourced from multica daemon code)
- Leader detection: `strings.Contains(instructions, "## Squad Operating Protocol")` in `daemon.go`
- Daemon writes briefing to `{workDir}/CLAUDE.md` every task claim (`runtime_config.go:101-106`)
- `multica squad activity` mandatory every turn (`cmd_squad.go:379-434`)
- no_action outcome: silent exit, no comment
- Drift guard: `SQUAD_PROTOCOL_MARKER` literal in exactly 2 files (hooks only)

---

## [0.1.0] - 2026-05-23

### Added
- Initial Claude Code MVP release
- Core skills: multica-workflow, hitl-protocol, verification (Iron Law), systematic-debug (≥3 rule)
- Advanced skills: persistence-loop (PRD story tracking), parallel-exec (two-stage review)
- Hooks: stop (completion signal protocol), pre-tool (safe-exec proxy), session-start (notepad + learnings)
- CLI ABI documentation (cli-outward.md)
- Claude Code capability matrix (capabilities/claude-code.json)
- Install/uninstall scripts
