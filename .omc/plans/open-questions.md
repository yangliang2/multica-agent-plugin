# Open Questions

## multica-agent-plugin - 2026-05-23 (rev2 after Architect + Critic review)

### Active (need answers before or during Step 4–6)
- [ ] `multica` CLI 的 `issue comment` 幂等性细节 — `docs/abi/cli-outward.md` 已要求支持 `--idempotency-key`；待 multica 团队确认实现细节（hash 算法、TTL）— 决定 HITL 是否仍需 client-side dedup
- [ ] Cursor `.mdc` 的 frontmatter `globs` 字段在最新版本是否仍支持？— 决定 `tools/render-cursor.sh` 是否需要 schema 锁；影响 Cursor manual signed 流程稳定性
- [ ] OpenCode 的 `opencode.json` 是否有官方 merge 规范？— 决定 `adapters/opencode/install.sh` 用 `jq` patch 还是官方工具；影响 R2 风险等级
- [ ] Gemini extension 的 distribution 渠道（registry vs sideload）哪个稳定？— 决定 release 流程
- [ ] **Kimi-CLI ACP `opts.SystemPrompt` 字段是否在未来 minor 版本稳定**？— 已在 `docs/abi/daemon-inward.md` 锁定当前字段名 + sentinel 验证；待 Kimi 团队确认 SemVer 政策；影响 R3
- [ ] **`multica safe-exec` 二进制是否随 multica CLI 主包发布？还是需要单独安装**？— 决定 `docs/install-multica.md` 内容和所有 adapter install.sh 的检测逻辑；M4 落地依赖此答案
- [ ] **`capabilities/*.json` 的自动探测路径**：启动时由 daemon 写入 env (`MULTICA_HARNESS_CAPS`)，还是 adapter install 时静态写入？— 决定 capability schema 是 dynamic 还是 static；影响 Step 1 + Step 4a 实现细节
- [ ] HITL 超时 daemon reaper 的轮询频率与阈值默认值？— `hitl-protocol.md` 已锁定 daemon 是唯一 owner，但具体参数待与 multica 团队对齐
- [ ] AGENTS.md `<<cli:*>>` anchor 渲染发生在哪一层（install 时静态渲染，还是 runtime 动态渲染）？— 决定 `tools/render-anchors.sh` 在 adapter install 流程中的位置

### Resolved (decisions made in rev2)
- [x] ~~多 issue 并发时 `.multica/state/` 的目录布局（per-issue subdir vs lockfile）？~~ → **Step 3 Decision**: per-issue subdir `state/<issue_id>/` + `flock(2)` advisory lock + stale-lock recovery (mtime > 15min) + atomic rename writes
- [x] ~~hooks 节流阈值（多久允许一次 checkpoint comment）？~~ → **Decision**: state file mtime 节流 60s + dedup hash 在 comment 模板
- [x] ~~AGENTS.md 漂移 CI 检测的具体方式（hash diff 还是关键词冲突扫描）？~~ → **Decision**: 双轨：(1) AGENTS.md hash + `docs/cli-reference.lock` diff guard；(2) `tools/check-no-conflict.sh` 扫描 CLAUDE.md/GEMINI.md/capabilities/** 与 AGENTS.md 关键词冲突
- [x] ~~Kimi-CLI 是否能读取 multica CLI 的环境变量？~~ → **Decision (C2 fix)**: Kimi daemon ACP **不读盘也不必读 env**；AGENTS.md 内容通过 `opts.SystemPrompt` JSON-RPC 字段注入；env 仅用于 launcher 配置
- [x] ~~`multica safe-exec` 二进制是否随 multica CLI 主包发布？还是需要单独安装？~~ → **Resolved by source code (2026-05-26)**: `multica safe-exec` does NOT exist in the CLI (`server/cmd/multica/` has no such command). `pre-tool.sh` now uses a local `tools/safe-exec.deny.list` instead. `capabilities/claude-code.json` updated: `destructive-guard: "wrapper"`.
- [x] ~~`multica` CLI の `issue comment` 幂等性细节~~ → **Resolved by source code (2026-05-26)**: `server/internal/handler/issue.go:2007` confirms attachment IDs are idempotent (re-sending same id is a no-op) but there is no `--idempotency-key` flag on `multica issue comment add`. Client-side dedup (dedup hash in comment body) remains the correct approach.
- [x] ~~`multica squad activity` CLI surface~~ → **Resolved by source code (2026-05-26)**: syntax is `multica squad activity <issue-id> <outcome> [--reason "..."]`; valid outcomes: `action`, `no_action`, `failed` (cmd_squad.go:399). No `log` subcommand exists.
- [x] ~~Child-issue parent backlink~~ → **Resolved by source code (2026-05-26)**: `server/internal/handler/issue_child_done.go` confirms multica auto-posts a system comment on the parent when a child transitions to done, and auto-triggers the parent leader agent (`triggerChildDoneAgent`/`triggerChildDoneSquad`). Leader does NOT need to manually backlink — daemon handles rollup notification automatically.

## v0.2.0-squad-aware - 2026-05-23

### Active (need answers before or during v0.2.0 Steps 5–6)
- [x] ~~**Briefing-to-disk path**: does multica daemon write the appended squad briefing to `$MULTICA_WORKDIR/.multica/briefing.md` (or similar)?~~ → **Resolved by source code (2026-05-26)**: `execenv/runtime_config.go:106` — daemon calls `InjectRuntimeConfig` which writes the full briefing (including Squad Operating Protocol + Roster) directly to `{workDir}/CLAUDE.md`. The session-start hook's existing detection of `$MULTICA_WORKDIR/CLAUDE.md` is correct. No separate briefing file exists.
- [x] ~~**`multica squad activity` CLI surface**: confirm subcommand syntax~~ → **Resolved by source code (2026-05-26)**: syntax confirmed as `multica squad activity <issue-id> <outcome> [--reason "..."] [--output json]`; valid outcomes: `action`, `no_action`, `failed` (`cmd_squad.go:399`). No `log` subcommand exists. Full help block added to `docs/cli-reference.md`.
- [x] ~~**Roster staleness window**: is the roster re-injected on every leader claim?~~ → **Resolved by source code (2026-05-26)**: `squad_briefing.go:12` explicitly states briefing is built "every squad-leader claim". Roster is always current at session start. No plugin work needed.
- [x] ~~**Child-issue parent backlink**: when a leader creates a child issue (Strategy A), does multica auto-link the child to the parent?~~ → **Resolved by source code (2026-05-26)**: `issue_child_done.go` confirms daemon auto-posts a system comment on the parent when child transitions to done, and auto-triggers `triggerChildDoneAgent`/`triggerChildDoneSquad`. Leader does NOT need to manually backlink — daemon handles rollup automatically. `cli-outward.md` updated to document this.
- [x] ~~**`capabilities/*.json` の自動探測路径**：启动时由 daemon 写入 env (`MULTICA_HARNESS_CAPS`)，还是 adapter install 时静态写入？~~ → **Resolved by source code (2026-05-26)**: daemon does NOT inject `MULTICA_HARNESS_CAPS` or any harness capability env var. Capabilities are static — written at adapter install time only. `capabilities/*.json` must be maintained manually.

---

### From Analyst (Critic) — folded into rev2 plan
- [x] C1: CLI 命令字面错误 → Step 0 锁定 `docs/cli-reference.md` + anchor 引用
- [x] C2: Kimi adapter 走 ACP `opts.SystemPrompt` 而非 cp → Step 4a Kimi adapter 重写为 daemon launcher
- [x] C3: smoke matrix 验收门槛 → Kimi 进 12/12 自动；Cursor 保留 manual 但要 signed + screenshots
- [x] M1: 降级不可观测 → `capabilities.schema.json` + 6 个 harness 矩阵
- [x] M2: 两个 ABI 未命名 → `docs/abi/cli-outward.md` + `docs/abi/daemon-inward.md`
- [x] M3: 并发隔离决策 → Step 3 per-issue subdir + flock
- [x] M4: 销毁性命令拦截下沉 → `multica safe-exec` wrapper（所有 harness 统一）
- [x] M5: 工具脚本归集 → Step 1.5 交付清单
- [x] M6: GEMINI smoke 改为 sentinel digest 比对
- [x] M7: smoke expected 加 timestamp normalization
- [x] HITL 超时责任主体 → daemon reaper 单一 owner
- [x] `multica` CLI 二进制依赖 → `docs/install-multica.md` + 所有 install.sh 版本检测
- [x] 语言锁定 → AGENTS.md 主语言英文，i18n 另置 `docs/i18n/`
