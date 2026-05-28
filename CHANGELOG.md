# Changelog

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
