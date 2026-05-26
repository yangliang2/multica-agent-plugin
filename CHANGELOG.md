# Changelog

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
