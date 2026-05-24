# Multica Agent Plugin — Implementation Plan (Revised after Architect + Critic review)

**Plan ID:** multica-agent-plugin
**Date:** 2026-05-23 (rev3: scope narrowed to Claude Code MVP; deep-research精髓注入)
**Mode:** DELIBERATE (consensus, high-risk: daemon-first, multi-framework synthesis)
**Owner:** TBD
**Revision Log:**
- rev1 (2026-05-23): initial DELIBERATE plan (6 harness targets)
- rev2 (2026-05-23): folded in Architect + Critic blockers C1/C2/C3/M1/M2/M3 and secondary M4–M7
- rev3 (2026-05-23): **scope = Claude Code MVP only**; 深度研究后注入各框架精髓到对应 skill 规范

---

## 1. Context

**rev3 范围收窄**：仅实现 Claude Code MVP。其他 harness（Codex/Cursor/Gemini/OpenCode/Kimi-CLI）的 adapter 架构见 rev2，待 MVP 验证后再扩展。AGENTS.md 和 3-archetype 设计保留，但本轮只交付 Claude Code 路径。

设计并实现 `multica-agent-plugin` 的 Claude Code 版本。插件以 Multica daemon 的**非交互模式**为第一公民（`claude -p --bypassPermissions --disallowedTools AskUserQuestion`），通过 `multica` CLI 作为唯一稳定接口，综合以下框架的精髓：

| 来源框架 | 吸取的精髓 | 对应 skill |
|---------|----------|-----------|
| **OMC ralph** | PRD story tracking（`passes: true/false`）+ Stop hook 持久化循环 + deslop pass | `persistence-loop.md` |
| **OMC** | Notepad 三分区（priority/working/manual，compaction-resistant）+ session-scoped state | `CLAUDE.md` + hooks |
| **Superpowers** | Verification Iron Law + 5步 Gate + 合理化防范表 | `verification.md` |
| **Superpowers** | Systematic debug ≥3次质疑架构规则 + 4阶段调查 | `systematic-debug.md` |
| **Superpowers** | subagent-driven 两阶段 review（spec compliance → code quality） | `parallel-exec.md` |
| **oh-my-openagent** | 完成信号协议（`<promise>DONE</promise>`）+ Hash-Anchored 防漂移思路 | `persistence-loop.md` + hooks |
| **GSD** | context rot 防护（skill 小而专一，按需加载）+ 包合法性门控思路 | `AGENTS.md` 设计约束 |
| **gstack** | Taste memory（learnings.jsonl，跨 session 项目知识积累） | `CLAUDE.md` + 可选 skill |

---

## 2. Work Objectives（Claude Code MVP）

1. 交付可被 Claude Code daemon 直接消费的插件目录树（AGENTS.md + CLAUDE.md + skills/ + hooks/）
2. 在 daemon 非交互模式下完整跑通：拉 issue → 执行工作流 → verification → 通过 comment HITL → 写回结果
3. 实现 PRD story tracking 持久化循环（ralph 精髓），完成信号用 `<promise>DONE</promise>`
4. verification skill 实现 Iron Law + 5步 Gate Function + 合理化防范表
5. systematic-debug skill 实现 4阶段流程 + ≥3次质疑架构规则
6. Stop hook 实现 session-scoped checkpoint，Notepad 三分区跨 session 保留项目知识
7. 提供 CLI ABI 文档（cli-outward.md）和 Claude Code smoke 验收

---

## 3. Guardrails

### Must Have
- AGENTS.md 必须是所有 harness 行为契约的源；CLAUDE.md / GEMINI.md 只能是**增强**，不能与 AGENTS.md 矛盾
- 所有 skill 都必须能在「无 hooks、无 AskUserQuestion」环境下退化执行
- HITL 仅通过 `multica issue comment` + `blocked` 状态实现，不依赖任何 harness 的交互对话框
- 每个 adapter 必须有一个 "smoke" 命令，跑通时输出 `OK harness=<name> version=<sha> archetype=<file|sysprompt|config>`
- 不允许 skill 内部硬编码 `claude` / `gemini` 二进制名（通过 `$MULTICA_HARNESS` 间接调用）
- 所有 multica CLI 调用样本必须 100% 引用 `docs/cli-reference.md`（CI diff guard 验证）
- 销毁性命令拦截**统一在 `multica safe-exec` wrapper**，所有 harness 必经此路径，而非只在 Claude Code pre-tool.sh
- AGENTS.md / GEMINI.md / CLAUDE.md / skills/** **主语言锁定为英文**；翻译版另置 `docs/i18n/<lang>/`

### Must NOT Have
- 不引入 brainstorming 之类的硬交互门控
- 不让任何 skill 依赖 `~/.claude` 路径常量（写入 `$MULTICA_PLUGIN_ROOT`）
- 不向 adapter 复制 skill 正文（adapter 只做引用 + 格式包装或 system-prompt 注入，避免内容漂移）
- 不在 AGENTS.md 中描述 hooks 细节（hooks 是 Claude Code 私有）
- 不假设任何 harness 会自动读盘 AGENTS.md（必须用 `capabilities.schema.json` 明确声明）

---

## 4. Task Flow（Claude Code MVP）

```
        ┌──────────────────────────────────┐
        │ Step 0: Bootstrap +              │  Lock multica CLI surface
        │         CLI surface lock         │  docs/cli-reference.md + anchor system
        └──────────────┬───────────────────┘
                       │
        ┌──────────────▼──────────────────────────────┐
        │ Step 1: Core Contract                        │  AGENTS.md (context-rot防护)
        │   + ABI doc (cli-outward.md)                 │  + multica-workflow.md
        │   + hitl-protocol.md                         │  + hitl-protocol.md
        └──────────────┬──────────────────────────────┘
                       │
        ┌──────────────▼──────────────────────────┐
        │ Step 1.5: Shared Tooling                 │  check-no-conflict.sh
        │                                          │  multica-smoke / safe-exec wrapper
        └──────────────┬──────────────────────────┘
                       │
        ┌──────────────▼────────────────────────────┐
        │ Step 2: Core Skills                        │  verification (Iron Law + Gate)
        │   (Superpowers 精髓)                       │  systematic-debug (4阶段 + ≥3规则)
        └──────────────┬────────────────────────────┘
                       │
        ┌──────────────▼────────────────────────────────────────┐
        │ Step 3: Claude Code Track                              │
        │   CLAUDE.md + Notepad三分区                            │
        │   persistence-loop (PRD story + 完成信号 + deslop)     │
        │   parallel-exec (两阶段review + 模型路由)              │
        │   hooks/ (stop + pre-tool + session-start)             │
        │   Concurrency: per-issue subdir + flock                │
        └──────────────┬────────────────────────────────────────┘
                       │
        ┌──────────────▼────────────┐
        │ Step 4: Smoke + verify    │  Claude Code 2 场景（正常 + HITL）
        │   (Claude Code only)      │  persistence loop e2e test
        └──────────────┬────────────┘
                       │
        ┌──────────────▼────────────┐
        │ Step 5: ADR + release doc │
        └───────────────────────────┘
```

Dependencies:
- Step 0 blocks Step 1 (CLI reference 是 contract substrate)
- Step 1 blocks Step 1.5, 2, 3
- Step 1.5 blocks Step 2, 3 (shared tools)
- Step 2 blocks Step 3 (advanced skills 引用 core skills)
- Step 4 blocks Step 5

---

## 5. Detailed TODOs

### Step 0 — Bootstrap + CLI surface lock (S→M, 0.5→1d, C1 fix)

**Files**
- `multica-agent-plugin/README.md` — 1 屏，说明：插件目的、支持的 6 个 harness、安装入口表
- `multica-agent-plugin/VERSION` — semver，初始 `0.1.0`
- `multica-agent-plugin/.editorconfig`, `.gitignore`
- **NEW**: `docs/cli-reference.md` — `multica issue --help`, `multica issue get --help`, `multica issue comment --help`, `multica issue status --help`, `multica safe-exec --help` 完整 dump
- **NEW**: `docs/cli-reference.lock` — 上述 help 输出的 sha256（CI diff guard 用）
- **NEW**: `tools/refresh-cli-reference.sh` — 跑真实 `multica` binary 重新生成 reference + lock

**Content rules**
- README 写什么：harness 安装路径表（Claude Code → `~/.claude/plugins/`、Codex → `~/.codex/skills/`、Cursor → `.cursor/rules/`、Gemini → `gemini ext install`、OpenCode → `opencode.json`、Kimi-CLI → daemon launcher 注入 system prompt）
- README 不写什么：任何 skill 内容细节、hooks 细节、daemon 内部协议
- `docs/cli-reference.md` 是**唯一**允许出现完整 CLI 命令字面量的位置；所有 AGENTS.md / skills/** / adapters/** 内文档对命令样本必须以 `<<cli:issue.get.basic>>` 等 anchor 形式引用，由 CI 渲染时替换

**Acceptance**
- `tree -L 2 multica-agent-plugin/` 输出与设计目录一致
- README 在 80 行内
- `bash tools/refresh-cli-reference.sh && git diff --exit-code docs/cli-reference.md docs/cli-reference.lock` 在 CI 通过（防止线下命令文档过时）
- `grep -rE "multica (issue|safe-exec) " AGENTS.md skills/ adapters/ | grep -v "<<cli:"` 返回 0（即所有命令样本都走 anchor）

---

### Step 1 — Core Contract + ABI + Capabilities (M→L, 1→1.5d, M1/M2 fix)

**Files**
1. `AGENTS.md`
2. `skills/core/multica-workflow.md`
3. `skills/core/hitl-protocol.md`
4. **NEW**: `docs/abi/cli-outward.md` (M2)
5. **NEW**: `docs/abi/daemon-inward.md` (M2)
6. **NEW**: `capabilities.schema.json` + `capabilities/<harness>.json` × 6 (M1)

**`AGENTS.md` — 写什么**（GSD context rot 防护：小而精准，按需加载）

Identity block（≤5 行）：
```
You operate inside a Multica issue. The issue is your task.
No human is at the keyboard. All decisions must be autonomous or deferred via comment+blocked.
All output must be reproducible from issue comments alone.
```

三个跨 harness 不变量（每条 ≤3 行，用 anchor）：
- 入口：`<<cli:issue.get>>` → 拉取 issue body + metadata
- 出口：`<<cli:issue.comment>>` → 写回任何用户可见输出
- 状态：`<<cli:issue.status>>` → 推进 in_progress / blocked / done

Workflow phases 状态机（每 phase ≤8 行，discover → plan → execute → verify → report）：
- discover: 读 issue，读 comment 历史，理解任务
- plan: 分解为可测试的 stories（写入 loop.json 或 comment）
- execute: 实现，每个 story 走 verification Gate
- verify: 走 `skills/core/verification.md` Iron Law
- report: 结果写 comment，状态设 done

Skills 引用索引（只列文件路径，不复制内容）：
- `skills/core/multica-workflow.md` — 5-phase 状态机详情
- `skills/core/hitl-protocol.md` — 何时 blocked，comment 模板
- `skills/core/verification.md` — Iron Law + Gate Function
- `skills/core/systematic-debug.md` — 4阶段调试流程
- `skills/advanced/persistence-loop.md` — PRD story tracking（Claude Code only）
- `skills/advanced/parallel-exec.md` — subagent 两阶段 review（Claude Code only）

**GSD context rot 防护规则**（必须遵守的设计约束）：
- AGENTS.md 总行数 ≤ 150 行（防止注入时撑爆 context）
- 每个 skill 文件独立且完整（agent 只加载当前需要的 skill，不全部注入）
- 不在 AGENTS.md 里复制任何 skill 内容（引用路径即可）
- 代码片段 ≤ 6 行；markdown 嵌套 ≤ 3 层

**`AGENTS.md` — 不写什么**
- 不写 hooks 细节（Claude Code 私有）
- 不写 AskUserQuestion（已被 `--disallowedTools` 禁掉）
- 不写完整 CLI 命令字面量（必须用 `<<cli:*>>` anchor）
- 不写超过 6 行的代码块
- 不写任何需要人类实时响应的语义

**`skills/core/multica-workflow.md`**
- 写什么: 一个 5-phase 状态机 (discover/plan/execute/verify/report)；每 phase 的入口条件、退出条件、推荐 multica CLI anchor
- **NEW**: 每 phase 列出依赖的 capability（如 execute 阶段依赖 `destructive-guard`，缺失时降级为「列出预期命令并 blocked」）
- **NEW**: 在 capability 缺失路径上，明确写「先 `multica issue comment --body '[capability=missing:<X>] reason=<why>'`」
- 不写什么: 任何具体业务领域、任何 hardcoded prompt 文本

**`skills/core/hitl-protocol.md`**
- 写什么: 何时升级到 HITL（决策不确定、外部凭据缺失、毁灭性操作）、comment 模板（含 `[HITL]` 前缀和 question id）、`blocked` 状态机变体
- **NEW (HITL 超时责任主体)**: HITL 超时**唯一**触发方为 multica daemon 侧的 reaper（按 issue `blocked_since` 字段轮询）。Skill / cron / CLI 三者均**不得**自己实现超时——明确写「if running outside daemon, set blocked and exit; do not poll」。理由：避免 3 个 owner 同时写状态导致 race
- 不写什么: 任何 harness 特定的交互 UI（AskUserQuestion、cursor inline、gemini chat）

**`docs/abi/cli-outward.md`** — 外向 ABI（plugin → multica CLI）
- 锁定子集：`issue get`（含分页：`--cursor`、`--limit`、`--state` filter；返回 JSON schema），`issue comment`（幂等约定：`--idempotency-key`），`issue status`，`safe-exec`（exit code 语义）
- 每命令配最小 JSON response example
- 版本兼容：声明依赖 `multica >= X.Y.Z`，列出 breaking change 政策

**`docs/abi/daemon-inward.md`** — 内向 ABI（multica daemon → harness）
- 环境变量约定：`MULTICA_ISSUE_ID`, `MULTICA_HARNESS`, `MULTICA_HARNESS_CAPS`, `MULTICA_PLUGIN_ROOT`, `MULTICA_WORKDIR`, `MULTICA_HITL_ALLOW`
- SystemPrompt 注入路径（Kimi/Gemini archetype）：ACP JSON-RPC `opts.SystemPrompt` 字段约定、内容编码、长度上限
- Workdir 布局：`$MULTICA_WORKDIR/.multica/state/<issue_id>/`, `.multica/logs/<harness>.log`, `.multica/locks/`
- 进程契约：stdout / stderr 用途（不得污染 ACP channel）

**`capabilities.schema.json`** — JSON Schema 描述每 harness capability 矩阵
```jsonc
// keys: hooks, destructive-guard, parallel, persistent-loop,
//       fs-load-agents-md, system-prompt-injection, config-embed,
//       interactive-ui, env-passthrough
// values: "native" | "wrapper" | "missing"
```
- `capabilities/claude-code.json`: hooks=native, destructive-guard=native, parallel=native, persistent-loop=native, fs-load-agents-md=native, system-prompt-injection=wrapper, config-embed=missing, interactive-ui=native, env-passthrough=native
- `capabilities/codex.json`: hooks=missing, destructive-guard=wrapper (safe-exec), parallel=missing, persistent-loop=missing, fs-load-agents-md=native, system-prompt-injection=missing, config-embed=missing, interactive-ui=missing, env-passthrough=native
- `capabilities/cursor.json`: hooks=missing, destructive-guard=wrapper, parallel=missing, persistent-loop=missing, fs-load-agents-md=native (`.mdc`), system-prompt-injection=missing, config-embed=missing, interactive-ui=native (manual only), env-passthrough=partial
- `capabilities/gemini.json`: hooks=missing, destructive-guard=wrapper, parallel=missing, persistent-loop=missing, fs-load-agents-md=native (GEMINI.md), system-prompt-injection=native (extension session), config-embed=missing, interactive-ui=missing, env-passthrough=native
- `capabilities/opencode.json`: hooks=missing, destructive-guard=wrapper, parallel=missing, persistent-loop=missing, fs-load-agents-md=missing, system-prompt-injection=missing, config-embed=native (opencode.json), interactive-ui=missing, env-passthrough=partial
- `capabilities/kimi-cli.json`: hooks=missing, destructive-guard=wrapper, parallel=missing, persistent-loop=missing, fs-load-agents-md=missing (**daemon ACP only**), system-prompt-injection=native (`opts.SystemPrompt` via ACP JSON-RPC), config-embed=missing, interactive-ui=missing, env-passthrough=native

**Acceptance**
- `grep -ri "AskUserQuestion\|inline-prompt\|cursor-modal" skills/core/` 返回 0
- 3 个核心 skill + 2 个 ABI 文件都通过 markdown linter 且 ≤ 250 行
- `AGENTS.md` 中所有 skill 引用以相对路径 `skills/core/*.md` 形式存在，所有命令样本以 `<<cli:*>>` anchor 引用
- `jq -e . capabilities.schema.json && jq -e . capabilities/*.json` 全部 valid JSON
- 6 个 capability 文件每个都通过 `ajv validate -s capabilities.schema.json -d capabilities/<harness>.json`
- ABI 文档每个 ≥ 1 个 JSON example，CI 用 schema 校验
- `grep -E "(超时|timeout)" skills/core/hitl-protocol.md` 必须只在 "daemon reaper" 上下文出现

---

### Step 1.5 — Shared Tooling (M, 1d, M4/M5 fix)

**Files**
- `tools/render-cursor.sh` — AGENTS.md → `.cursor/rules/multica.mdc` 渲染器
- `tools/check-no-conflict.sh` — CLAUDE.md / GEMINI.md / capabilities/** 与 AGENTS.md 关键词冲突扫描
- `tools/multica-smoke` — 通用 smoke 入口（接 `--harness <name>`，调对应 adapter）
- `tools/safe-exec-wrapper.sh` — **本地参考实现**（如果 `multica safe-exec` 不可用时的 polyfill）。注意：真实 enforcement 在 `multica safe-exec` 二进制中，本脚本仅 dev 用
- `tools/render-anchors.sh` — 把 `<<cli:*>>` anchor 替换为 cli-reference.md 真实命令

**Content rules**
- 每个脚本顶部：`#!/usr/bin/env bash` + `set -euo pipefail`
- 所有脚本仅依赖 POSIX + jq + git；不依赖 node/python
- 销毁性命令拦截清单写入 `tools/safe-exec.deny.list`（rm -rf /, git push --force-with-lease=*main*, drop database 等），所有 harness 走 `multica safe-exec`，**不依赖任何 hook**

**Acceptance**
- `shellcheck tools/*.sh` 无 error
- `bash -n tools/*.sh` 全过
- `tools/render-anchors.sh AGENTS.md > /tmp/rendered && grep -F "$(head -1 docs/cli-reference.md)" /tmp/rendered` 成功（anchor 真的替换了）
- `tools/check-no-conflict.sh` 在故意制造冲突的 fixture 上 exit≠0
- `tools/safe-exec-wrapper.sh -- rm -rf /` 拦截并 exit=42（与 multica safe-exec 行为一致）

---

### Step 2 — Core Skills Body (M, 1d)

**Files**
1. `skills/core/verification.md`
2. `skills/core/systematic-debug.md`

**`verification.md`**（Superpowers verification 精髓，去掉交互门控）

Iron Law（必须出现在文件顶部）：
> NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE

5步 Gate Function（每次完成声明前必须走完）：
1. IDENTIFY — 什么命令能证明这个 claim？
2. RUN — 完整执行该命令（不得使用缓存结果或上次运行）
3. READ — 读全部输出，检查 exit code，统计 failures 数量
4. VERIFY — 输出真的确认了 claim 吗？NO → 报告真实状态；YES → 继续
5. ONLY THEN — 带证据作出 claim

常见 claim-to-proof 对照表（必须包含）：
| Claim | 需要 | 不够 |
|-------|------|------|
| Tests pass | 测试命令输出 0 failures | 上次运行、"应该能过" |
| Build succeeds | build 命令 exit 0 | linter 通过、日志看起来好 |
| Bug fixed | 复现原症状的测试通过 | 代码改了、"应该修好了" |
| Feature complete | 逐条对照需求清单 | 测试通过 |

合理化防范表（防止 agent 自我安慰，必须包含）：
| 借口 | 正确回应 |
|------|---------|
| "Should work now" | RUN the verification |
| "I'm confident" | Confidence ≠ evidence |
| "Agent said success" | Verify independently |
| "Just this once" | No exceptions |
| "I'm tired / almost done" | Exhaustion ≠ excuse |

Red flags（出现任何一条 → STOP，先 verify）：
- 使用 "should", "probably", "seems to"
- 在 verify 前表达满足感（"Great!", "Done!", "Perfect!"）
- 依赖 agent 自报成功
- 部分验证后推断整体

写什么：3 类 verification（compile/lint、test、behavior smoke），每类判定矩阵；证据回写 comment 格式（命令 anchor + exit code + 输出 hash + 关键摘录）

不写什么："ask user to confirm"；任何同步等待用户的语义

---

**`systematic-debug.md`**（Superpowers systematic-debugging 精髓）

Iron Law（必须出现在文件顶部）：
> NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST

4阶段流程：

**Phase 1 — Root Cause Investigation**
- 完整读取错误信息（不跳过，记录行号/文件路径/错误码）
- 稳定复现（触发不了 → 收集更多数据，不猜测）
- 检查最近变更（git diff，新依赖，配置变更）
- 多组件系统：在每个组件边界记录数据进出，找到断裂点再深入那一层

**Phase 2 — Pattern Analysis**
- 在同一代码库找到可工作的类似实现
- 完整阅读参考实现（不跳读）
- 列出每一处差异，无论多小

**Phase 3 — Hypothesis & Testing**
- 一次只提一个假设，明确写出："I think X is the root cause because Y"
- 最小变更测试假设（一次一个变量）
- 未生效 → 形成新假设，**不在旧假设上叠加修复**

**Phase 4 — Implementation**
- 先写 failing test（用 `multica issue comment` 记录测试命令和预期输出）
- 单一修复（只改根因，不做顺手重构）
- 验证通过 → 走 verification.md Gate Function

**≥3次修复规则**（关键机制，必须包含）：
- 修复尝试 < 3 次：返回 Phase 1 重新调查
- 修复尝试 ≥ 3 次：**停止，质疑架构**
  - 每次修复暴露新位置的新问题 → 可能是共享状态/耦合问题
  - 每次修复需要"大规模重构" → 在补丁上打补丁
  - **不允许第 4 次尝试**，必须先通过 HITL comment 与人类确认方向

Red flags（≥3次专项）：
- "One more fix attempt"（已经试了 2 次）
- 每次修复在不同地方暴露新问题
- "Just try X and see"（未调查就动手）

不写什么：语言/框架特定建议；任何"先试试看"的指引

**Acceptance**
- `verification.md` 包含：Iron Law、5步 Gate、claim-proof 对照表、合理化防范表、Red flags 区块
- `systematic-debug.md` 包含：Iron Law、4阶段流程、≥3次规则、Red flags 区块
- 两个文件都有 "Daemon-Safe Notes" 区块（无同步等待用户语义）
- `grep -i "brainstorm\|AskUser\|ask user" skills/core/` 返回 0
- `grep -i "should work\|probably\|seems to" skills/core/verification.md` 返回 0（防止 anti-pattern 出现在 skill 正文）

---

### Step 3 — Claude Code Track + Concurrency Decision (M→L, 1.5→2d, M3 fix)

**Files**
1. `CLAUDE.md`
2. `skills/advanced/persistence-loop.md`
3. `skills/advanced/parallel-exec.md`
4. `hooks/stop.sh`
5. `hooks/pre-tool.sh` — **降级为 thin proxy**，调用 `multica safe-exec`（M4）
6. **NEW**: `docs/concurrency-model.md` (M3 decision document)

**Concurrency Decision (M3, was Open Question)**
- **Decision**: per-issue subdir + `flock(2)` advisory lock
- Layout: `$MULTICA_WORKDIR/.multica/state/<issue_id>/`，每 issue 一个子目录；并发由 `state/<issue_id>/.lock` 文件 + `flock` exclusive 获取
- 锁失败行为：
  - non-blocking attempt (`flock -n`)，失败时 retry 3 次（指数回退 100ms / 500ms / 2s）
  - 仍失败 → `multica issue comment --body '[lock-contention] another worker holds <issue_id>'` + 设 `blocked`，**不**抢占
  - 锁 stale 判定：`mtime < now - 15min` 视为 dead worker，写 `[lock-recovered]` comment 后重试一次
- 写入原子性：所有 state 写操作走 `mktemp + atomic rename`，禁止 in-place 写
- 文档体例见 `docs/concurrency-model.md`

**`CLAUDE.md`**
- 写什么: 一句话声明 "AGENTS.md is the source of truth; this file only adds Claude-specific affordances"；advanced skills 索引；hooks 注册说明（指向 settings.json 片段）
- 引用 `capabilities/claude-code.json` 作为权威能力清单
- 不写什么: 重复 AGENTS.md 内容；任何与 AGENTS.md 矛盾的指令

**`persistence-loop.md`**（OMC ralph + oh-my-openagent 精髓）

核心机制：PRD story tracking + 完成信号协议

**State schema**（存入 `.multica/state/<issue_id>/loop.json`，走 concurrency 规约）：
```json
{
  "active": true,
  "iteration": 0,
  "max_iterations": 50,
  "issue_id": "<id>",
  "session_id": "<claude-session-id>",
  "started_at": "<ISO8601>",
  "last_checkpoint_at": "<ISO8601>",
  "stories": [
    { "id": "S1", "title": "...", "acceptance": "...", "passes": false },
    { "id": "S2", "title": "...", "acceptance": "...", "passes": true }
  ],
  "phase": "execution"
}
```

**完成信号协议**（来自 oh-my-openagent，防止假完成）：
- Agent 必须在真正完成时输出 `<promise>DONE</promise>` 标记
- Stop hook 检测此标记决定是否继续循环
- **不输出此标记 → Stop hook 认定未完成 → 继续下一轮**
- 输出此标记但 stories 仍有 `passes: false` → Stop hook 拒绝，继续执行

**执行循环步骤**：
1. 读取 loop.json，找到第一个 `passes: false` 的 story
2. 执行该 story（调用 executor subagent 或直接实现）
3. 走 `verification.md` Gate Function 验证 story acceptance criteria
4. 验证通过 → 标 `passes: true`，写回 loop.json
5. 全部 passes → 走 **deslop pass**（调用 `multica issue comment` 记录 deslop 开始）→ re-verify
6. deslop 后所有 story 仍通过 → 输出 `<promise>DONE</promise>`
7. 未全部通过 → 不输出完成标记，Stop hook 触发下一轮

**Deslop pass**（OMC ralph 精髓，清理 AI 风格代码）：
- 对本次 loop 修改的文件调用 code cleanup
- 重点：移除不必要注释、过度防御性代码、冗余类型注解、不必要的 fallback
- Deslop 后必须重跑受影响的 tests，确保 regression-free

**显式声明**：
- "When `capabilities.persistent-loop != native`, this skill is a no-op; use multica-workflow single-shot instead"
- Max iterations 上限（默认 50）防止无限循环；达到上限 → HITL comment + blocked

---

**`parallel-exec.md`**（Superpowers subagent-driven-development 精髓）

核心机制：per-task subagent + 两阶段 review

**任务分派流程**（每个 story/task）：
1. Dispatch implementer subagent（给完整 task context，不让 subagent 自己读 plan 文件）
2. Implementer 问问题？→ 回答后重新 dispatch；不问 → 实现、测试、自我 review
3. Dispatch spec compliance reviewer（先检查是否符合 acceptance criteria）
4. Spec reviewer 发现问题 → Implementer 修复 → 重新 spec review；通过 → 继续
5. Dispatch code quality reviewer（检查代码质量：冗余、命名、结构）
6. Quality reviewer 通过 → 标记 task 完成；未通过 → 修复 → 重新 quality review
7. **顺序不可颠倒**：spec compliance 必须先于 code quality

**模型路由**（来自 oh-my-openagent category 思路）：
- 机械实现任务（隔离函数、清晰规范、1-2 文件）→ `haiku`
- 集成/判断任务（多文件协调、模式匹配、调试）→ `sonnet`
- 架构/review 任务 → `opus`

**退化**：`capabilities.parallel != native` → 串行执行，跳过 subagent dispatch，直接在当前 session 实现

---

**`hooks/stop.sh`**（OMC persistent-mode.mjs 精髓）

检查优先级（镜像 OMC 的 priority queue）：
1. 读取 `.multica/state/<issue_id>/loop.json`
2. 检查 `active: true` + stdout 是否含 `<promise>DONE</promise>`
3. 未完成 → 写 checkpoint comment（节流：mtime < 60s 跳过）+ exit 2（block Stop）
4. 已完成 → 写 `[loop-complete]` comment + 清理 state + exit 0（allow Stop）

节流与幂等：
- State file mtime < 60s → 跳过本轮，直接 exit 2（防止高频触发淹没 comment）
- Comment 模板含 dedup hash（`sha256(issue_id + iteration + phase)`），服务端去重
- 所有写操作走 `mktemp + atomic rename`

**`hooks/pre-tool.sh`**
- thin proxy：把 tool args 转给 `multica safe-exec`，根据 exit code 决定 allow / deny / HITL
- 不在 hook 内部维护黑名单（黑名单只在 `multica safe-exec`）
- `multica safe-exec` 缺失时 → fail-closed，报 `[capability=missing:destructive-guard]` + blocked

**`hooks/session-start.sh`**（OMC SessionStart + gstack learnings 思路，**NEW**）
- 读取 `.multica/notepad.md` 的 priority section（≤500 字），注入 `additionalContext`
- 读取 `.multica/learnings.jsonl`（项目知识积累，gstack taste memory 格式）：取最近 10 条 + confidence ≥ 7 的条目，注入 additionalContext
- 读取当前 session 的 loop.json（如有），提示 agent"上次循环在第 N 轮第 M 个 story，从此继续"

**Notepad 三分区**（OMC 精髓，写入 CLAUDE.md 使用规范）：
```
.multica/notepad.md 结构：
## Priority Context （≤500 字，每次 session 必加载）
## Working Memory （带时间戳，7 天自动过期）
## Manual Notes   （永久，永不自动清理）
```

**Acceptance**
- `bash -n hooks/*.sh` 全部通过
- `shellcheck hooks/*.sh` 无 error 级问题
- Stop hook 在未见 `<promise>DONE</promise>` 时 exit 2（block Stop）；见到后 exit 0
- 用 `claude -p --bypassPermissions` 执行 dummy issue：Stop hook 在 `.multica/state/<issue_id>/` 留下 checkpoint 文件
- 并发测试：5 个进程同一 issue_id，有且仅有 1 个成功，其余 4 个 comment `[lock-contention]` 并 blocked
- session-start hook：`.multica/notepad.md` 存在时，priority section 内容出现在 agent 首轮 context 中
- loop.json stories 全部 `passes: true` 且 stdout 含 `<promise>DONE</promise>` 时，Stop hook exit 0

---

### Step 4a — Non-Claude Adapters (DEFERRED to post-MVP)

> rev3 范围收窄：Codex / Cursor / OpenCode / Kimi / Gemini adapter 架构见 rev2，待 Claude Code MVP 验证后实现。3-archetype 设计和 capabilities.schema.json 保留作为未来扩展蓝图。

---

### Step 4 (MVP) — Claude Code Smoke + Verification (M, 1d)

**Files**
- `tests/smoke/run-claude.sh` — Claude Code 端到端 smoke 脚本
- `tests/smoke/claude.expected` — 期望输出（timestamp 归一化后）
- `tests/smoke/normalize.sh` — timestamp / pid / issue-id 归一化
- `install.sh` — Claude Code 插件安装（`~/.claude/plugins/` 或 settings.json hooks 注册）
- `uninstall.sh` — 清理 hooks + state 目录

**Smoke 场景 1 — 正常完成路径**
```
install.sh
→ 创建 dummy multica issue（mock multica server 或真实 test workspace）
→ claude -p --bypassPermissions --disallowedTools AskUserQuestion \
    "$(multica-smoke build-prompt <issue_id>)"
→ 验证：
  - stdout 含 <promise>DONE</promise>
  - .multica/state/<issue_id>/loop.json 存在且所有 stories passes=true
  - multica issue comment list 包含 verification 证据 comment
  - multica issue status == done
```

**Smoke 场景 2 — HITL blocked 路径**
```
→ 创建需要外部凭据的 dummy issue（故意触发 HITL）
→ 运行 claude daemon
→ 验证：
  - multica issue status == blocked
  - comment 含 [HITL] 前缀 + question_id
  - 外部写入回复 comment
  - on_comment 触发重新唤醒（验证 multica daemon 触发新任务）
  - 最终 status == done
```

**Smoke 场景 3 — Persistence loop 续跑**
```
→ 创建 multi-story issue（3 个 stories）
→ 第 1 轮运行：完成 story 1，Stop hook 触发（未输出 <promise>DONE</promise>）
→ 第 2 轮运行（模拟 daemon 重新唤醒）：续跑 story 2+3
→ 验证：
  - loop.json iteration 从 1 增到 2
  - 所有 stories passes=true 后输出 <promise>DONE</promise>
  - deslop pass 触发（log 中有 [deslop] 标记）
  - regression verify 通过
```

**Smoke 场景 4 — Verification Iron Law**
```
→ 创建故意有 failing test 的 issue
→ 验证 agent 不输出 <promise>DONE</promise>（Iron Law 阻止）
→ 验证 comment 包含真实的测试输出 + exit code
→ 验证 agent 尝试修复而非虚报完成
```

**Acceptance**
- `tests/smoke/run-claude.sh` 4 个场景全部绿
- normalize.sh 后 diff 与 expected 一致
- 无 `multica issue comment` 中出现 "should work" / "probably" 等 anti-pattern 词汇
- install + uninstall 幂等（install → install → uninstall → install 全绿）
- `shellcheck install.sh uninstall.sh tests/smoke/*.sh` 无 error

**Acceptance**
- 4 个 adapter 在干净容器中各跑一次 `install.sh && smoke && uninstall.sh && install.sh`（幂等性），全绿
- Kimi smoke 验证的是 **ACP-injected system prompt 的 sha256**，不是磁盘文件 sha256
- OpenCode `opencode.json` 备份还原可逆（uninstall 后 diff 与原文件一致）
- 每个 adapter 输出明确 archetype 字段

---

### Step 4b — Other Harness Adapters (DEFERRED to post-MVP)

> Gemini / Codex / Cursor / OpenCode / Kimi 的 adapter 规范见 rev2 存档。待 Claude Code MVP 验证通过后实施。

---

### Step 5 (MVP) — ADR + Release Doc (S, 0.5d)

**Files**
- `docs/adr/0001-claude-code-mvp.md`
- `CHANGELOG.md`
- `docs/install-multica.md`
- `KNOWN-LIMITATIONS.md` — post-MVP harness 扩展路径、当前限制

**ADR Sections**
1. Decision — Claude Code MVP first；AGENTS.md as source of truth；3-archetype 设计保留为扩展蓝图
2. Drivers — daemon-first 非交互；verification Iron Law 防虚报；PRD story tracking 防丢进度
3. Framework synthesis — OMC ralph（PRD loop + deslop）、Superpowers（verification + debug）、oh-my-openagent（完成信号协议）、GSD（context rot 防护）、gstack（taste memory）
4. Consequences — 仅 Claude Code；其他 harness 待扩展；learnings.jsonl 格式需与 multica 团队对齐
5. Follow-ups — 扩展到 Codex/Cursor/Gemini/Kimi；capability 自动探测；i18n

**Acceptance**
- ADR ≥ 5 sections，framework synthesis 一节明确列出每个框架贡献
- CHANGELOG 列出 0.1.0 入口
- `docs/install-multica.md` 包含 ≥2 种安装方式 + 版本检测命令

---

## 6. Success Criteria（Claude Code MVP）

**核心验收**
- [ ] 4 个 smoke 场景全部绿（正常完成 / HITL blocked / persistence loop 续跑 / verification Iron Law）
- [ ] `<promise>DONE</promise>` 协议工作：未输出时 Stop hook exit 2（block），输出后 exit 0（allow）
- [ ] PRD story tracking：loop.json stories 全部 `passes: true` 才允许完成，deslop pass 有记录
- [ ] Verification Iron Law 生效：有 failing test 时 agent 不虚报完成，comment 包含真实证据
- [ ] Systematic debug ≥3次规则：第 3 次修复失败时 agent 写 HITL comment 而非继续尝试
- [ ] HITL 路径在 daemon 模式下不卡死：blocked → comment → on_comment → 重新唤醒 → done
- [ ] Notepad priority section 在 session-start 时被注入 agent context
- [ ] Stop hook 节流：60s 内不重复写 checkpoint comment（dedup hash 生效）
- [ ] 并发安全：5 进程同一 issue，1 个成功，4 个 `[lock-contention]`

**工程质量**
- [ ] AGENTS.md ≤ 150 行（context rot 防护）
- [ ] CLI 命令字面量全部用 anchor，`grep -rE "multica issue" AGENTS.md skills/` 返回 0
- [ ] `shellcheck hooks/*.sh` 无 error
- [ ] install + uninstall 幂等
- [ ] cli-outward.md ABI 文档存在且 CLI 命令与真实 binary 一致

**框架精髓落地验证**
- [ ] verification.md 包含 Iron Law + 5步 Gate + 合理化防范表（可 grep 到关键词）
- [ ] systematic-debug.md 包含 4 阶段 + ≥3次规则（可 grep 到关键词）
- [ ] persistence-loop.md 包含 PRD story schema + `<promise>DONE</promise>` 协议
- [ ] parallel-exec.md 包含两阶段 review 顺序（spec compliance → code quality）
- [ ] session-start hook 加载 notepad + learnings.jsonl
- [ ] 总代码 + 文档 ≤ 2000 行（MVP 比 full 精简）

---

## 7. Risks

| # | Risk | Likelihood | Impact | Mitigation |
|---|------|-----------|--------|-----------|
| R1 | Cursor `.mdc` frontmatter schema 漂移 | M | M | render 脚本固定 schema 版本；smoke 校验；manual signed 强制重跑 |
| R2 | OpenCode `opencode.json` 合并破坏用户配置 | M | H | 用 `jq` patch + 备份；uninstall 还原 |
| R3 | **Kimi ACP API 变更** (替换原 R3) | M | H | smoke 用 sentinel digest 直接验证 ACP 注入；ABI doc 锁定 ACP schema 子集；提供 `--system-prompt-file` CLI 降级路径并写入 KNOWN-LIMITATIONS |
| R4 | Claude Code hooks 路径在 Codex/Gemini 被错误激活 | L | H | hooks 只放在 `hooks/`，AGENTS.md 不引用；adapter install 不拷贝 hooks；safe-exec 是唯一统一拦截层 |
| R5 | `multica` CLI 跨 harness 行为不一致 | M | H | cli-outward.md 锁定子集；CI 用真实 multica binary diff guard CLI 文档 |
| R6 | Daemon 模式下持久化循环写 disk 频率过高 | L | M | 状态文件去重 + ttl + 60s mtime 节流 |
| R7 | 多个 worker 同时处理同一 issue | M | H | per-issue subdir + flock + stale lock recovery（Step 3 决策） |
| R8 | capabilities/* 与真实 harness 行为漂移 | M | M | smoke 增加 capability assertion；每次 harness 升级强制重跑 |
| R9 | ABI 文档与真实 binary 漂移 | M | H | `tools/refresh-cli-reference.sh` + CI exit-code diff guard |

---

## 8. Pre-mortem (DELIBERATE mode)

**Scenario A — 6 个月后**
插件铺开到 200 用户，Cursor 升级了 `.mdc` schema，渲染脚本失效；用户拿到 silent broken rules。根因：未把 render 脚本固定到 cursor 版本。
**Mitigation now**：render 脚本输出 `# generated for cursor>=X.Y` 注释；smoke 校验加 schema check；manual signed 强制重跑。

**Scenario B — Daemon 长跑泄漏**
Claude Code Stop hook 在 daemon 模式被高频触发，每个 issue 写 100+ checkpoint comment，淹没 issue。根因：未做去重。
**Mitigation now**：stop.sh 用 `state file mtime > 60s` 节流；comment 模板含 dedup hash。

**Scenario C — AGENTS.md 漂移 + Kimi 静默失败**（rev2 扩展）
有人在 CLAUDE.md 加了一条与 AGENTS.md 冲突的指令；同时 Kimi daemon 升级后 `opts.SystemPrompt` 字段被改名为 `opts.System`，但因为 Kimi smoke 之前只 sha256 磁盘文件（rev1 错误方案），没人发现 system prompt 实际没传进去。根因：缺乏 ABI 锁 + 错误的 smoke verification。
**Mitigation now**：(1) `tools/check-no-conflict.sh` 在 CI 阻止冲突；(2) Kimi smoke 用 sentinel digest echo 直接验证 ACP 注入；(3) daemon-inward.md 锁定 SystemPrompt 字段名，字段变更必须升级 ABI。

---

## 9. Expanded Test Plan (DELIBERATE mode)

| Layer | What | How |
|-------|------|-----|
| Unit | 渲染脚本（cursor/anchors） | golden file 对比 |
| Unit | hooks shell | `bats` 测 stop.sh idempotence + pre-tool.sh proxy to safe-exec |
| Unit | safe-exec wrapper deny list | `bats` 测每条 deny pattern 单跑 |
| Unit | capabilities JSON schema | `ajv validate` × 6 harness |
| Integration | adapter install/uninstall 幂等 | 在干净 docker container 跑 install→install→uninstall→install |
| Integration | multica CLI 三件套 + safe-exec | mock multica server |
| Integration | concurrency flock | 5 并发跑同 issue，断言 1 成功 + 4 lock-contention |
| Integration | Kimi ACP system prompt 注入 | spawn kimi daemon，ACP client 注入，sentinel echo 验证 |
| E2E | 6 × smoke matrix | tests/smoke/run-all.sh（12/12 auto + Cursor signed） |
| E2E | HITL 闭环 | 故意制造 blocked → 外部 comment → 恢复 |
| E2E | capability missing 降级 | 注入 stub capabilities，验证 `[capability=missing:X]` comment |
| Observability | 每个 harness 在 `.multica/logs/<harness>.log` 留心跳 | grep 验证 |
| Drift guard | AGENTS.md hash + cli-reference.lock | CI fail-on-diff |
| Drift guard | CLAUDE.md/GEMINI.md vs AGENTS.md 关键词冲突 | `tools/check-no-conflict.sh` |

---

## 10. ADR (Embedded Summary — 完整版见 docs/adr/0001)

- **Decision**: 采用「AGENTS.md as single source + thin per-harness adapters across **3 archetypes** + Claude Code 增强层」三层结构
- **Drivers**: (1) 6 harness 异构能力差距大；(2) daemon-first 无人值守；(3) 降级路径必须存在；(4) 漂移防护
- **Alternatives considered**:
  - A: 每 harness 独立 skill 树 — 内容漂移风险高
  - B: 运行时翻译层（一个进程把 AGENTS.md 翻译给当前 harness） — 引入额外依赖、与 multica daemon 职责重叠
  - C: AGENTS.md + multi-archetype adapters（**选中**）
- **Why chosen (rev2)**: 见下方 RALPLAN-DR
- **Consequences**: 必须维护 `capabilities.schema.json`；Kimi adapter 是 ACP launcher 而非 cp；adapter 安装可逆要求 backup；需要 `multica safe-exec` 兜底
- **Follow-ups**: i18n、telemetry、版本协商、capability 自动探测

---

## RALPLAN-DR Summary (rev2)

### Principles (5)
1. **AGENTS.md is single source of truth** — adapter 不复制内容，只做格式转换或 system-prompt 注入
2. **Daemon-first, human-second** — 任何 skill 必须能无人值守执行；HITL 只通过 comment + blocked，超时唯一 owner 是 daemon reaper
3. **Degrade observably, do not fail** — Claude Code 独有能力（hooks/advanced skills）在其它 harness 通过 `capabilities/*.json` **可观测**地降级
4. **Two ABIs, both versioned** — `cli-outward` (plugin→multica CLI) 与 `daemon-inward` (daemon→harness) 都是冻结合约
5. **No interactive gating** — 借鉴 Superpowers verification/debug，但去掉 brainstorming 硬门控；销毁性命令统一走 `multica safe-exec`

### Decision Drivers (top 3)
1. **Harness 异构 + 3 archetype 是结构性事实** — 不是「最弱 harness 决定上限」那么简单，而是 file-loaded / sysprompt-injected / config-embedded 各有自己的注入路径
2. **Daemon 模式（`claude -p --bypassPermissions` / Kimi ACP）是主力场景** — 无人值守要求所有交互异步化，且 ACP 不读盘的 harness 必须有 launcher
3. **维护成本 / 漂移风险 / 可观测性** — 6 个 harness 不能各自演化，必须有单一真相 + CI 防漂移 + capability 矩阵

### Viable Options

#### Option A — AGENTS.md + multi-archetype adapters（**推荐**）
- Pros: 单一真相、维护性高、降级清晰、capability 可观测、ABI 可版本化
- Cons: adapter 安装脚本复杂、Cursor `.mdc` 需要生成、Kimi 需要 daemon launcher、Claude Code 增强需要独立测试、需要维护 capabilities schema

#### Option B — 运行时翻译层（一个 daemon 把 AGENTS.md 翻译给当前 harness）
- Pros: 所有 harness 行为完全一致；可加热重载
- Cons: 引入新进程依赖、与 multica daemon 职责重叠；翻译层本身需要 ACP 接入 Kimi/Gemini（解决不了「不读盘」的根问题，只是把 launcher 上移到自己进程内）；新增故障面

#### Option C — 每 harness 独立 skill 树
- Pros: 各 harness 可独立调优、上手快
- Cons: 内容漂移不可避免、6 倍维护成本、ADR 责任分散、违反共识原则 #1

### Recommendation (rev2 — Option A 选型理由重写)

**Option A**。**修正后理由**：

1. **3 archetype 是 harness 生态的客观事实**，不是设计缺陷 —— Option A 通过 capabilities schema **显式建模**这一事实，而非掩盖。rev1 错误地把 Kimi 当作「文件 cp 派」，rev2 承认 Kimi 走 ACP `opts.SystemPrompt` 注入（`kimi.go:270-279`），归入 system-prompt-injected archetype。这反而**强化**了 Option A：因为「AGENTS.md as content + 多路径注入」比「AGENTS.md as universal disk file」更普适。
2. **降级可观测**而非隐式：`capabilities/*.json` 让 workflow skill 在能力缺失时显式 emit `[capability=missing:X]` comment，而不是「悄悄不做」。
3. **两条 ABI（cli-outward / daemon-inward）让契约可版本化**：上一版本里 ABI 是隐式的，rev2 显式锁定后，Kimi ACP 字段变更等漂移可以被 CI 拦住。
4. **`multica safe-exec` 统一销毁性命令拦截**：销毁性 guard 不再是 Claude Code 私有的 hook，而是所有 harness 必经的二进制层；这让 Option A 在 Codex/Cursor/OpenCode/Kimi 上也有等价的 safety floor。
5. **Option B 解决不了根问题**：Kimi 不读盘是 ACP 协议层的事实，Option B 的翻译进程也得自己实现 ACP launcher，等于把 Option A 的 launcher 上移一层，没有净收益，反而新增故障面。
6. **Option C 6 个月内必定漂移**，且在 multi-archetype 现实下 6 倍维护成本变 18 倍（archetype × harness）。

**显式排除**：
- B 因为新增长跑进程 + 与 multica daemon 职责重叠 + 不解决 ACP 注入根问题
- C 因为违反原则 #1 + multi-archetype 下维护成本爆炸

---

## Open Questions (also persisted to .omc/plans/open-questions.md)

- [ ] `multica` CLI 的 `issue comment` 幂等性细节（rev1 已部分回答：cli-outward.md 要求 `--idempotency-key`；待 multica 团队确认实现）
- [ ] Cursor `.mdc` 的 frontmatter `globs` 字段在最新版本是否仍支持？需要锁定 cursor 版本下限
- [ ] OpenCode 的 `opencode.json` 是否有官方 merge 规范，还是只能用 `jq` 自行 patch？
- [ ] Gemini extension 的 distribution 渠道（registry vs sideload）哪个稳定？
- [ ] Kimi-CLI ACP `opts.SystemPrompt` 字段是否在未来 minor 版本稳定？（已在 ABI doc 锁定当前字段名，待 Kimi 团队确认 SemVer 政策）
- [ ] `multica safe-exec` 二进制是否随 multica CLI 主包发布？还是需要单独安装？
- [ ] `capabilities/*.json` 的自动探测路径（启动时由 daemon 写入 env，还是 adapter install 时静态写入）？

**已迁出（rev2 决策）**：
- ~~多 issue 并发时 `.multica/state/` 的目录布局？~~ → Step 3 决策：per-issue subdir + flock
- ~~hooks 节流阈值？~~ → 固定 60s mtime
- ~~AGENTS.md 漂移 CI 检测方式？~~ → hash diff + 关键词冲突双轨（`tools/check-no-conflict.sh`）

---

## v0.2.0 Roadmap — Squad-Aware Mode

### 背景

Multica Squads（小队）是一个多态 assignee 路由层：issue 分配给 squad → leader agent 被唤醒 → leader 判断谁最适合 → @mention 成员 → 成员执行。

Multica daemon 启动 leader 时会注入三段 briefing：
1. **Squad Operating Protocol**（固定系统规则）
2. **Squad Roster**（成员花名册 + @mention 链接）
3. **Squad Instructions**（用户自定义指令）

MVP v0.1.0 假设 agent 独立完成整个任务。Squad 模式下 leader 做路由决策，member 做执行。插件需要感知这个区别。

### 并发模型（源码研究结论，agent.sql:206-240 + daemon.go:1752）

**这是 Squad 设计的基础，必须理解清楚。**

```
同一 workspace 内的并发规则：
  Agent A + Issue #1 ──── 运行中
  Agent A + Issue #2 ──── 同时运行 ✓（不同 issue，允许并发）
  Agent A + Issue #1 ──── 阻止！（同一 issue + 同一 agent，强制串行）

  全局上限：max_concurrent_tasks = 6（daemon semaphore，所有 agent 共享）

跨 workspace：
  完全隔离，agent 硬绑定到 workspace，不存在跨 workspace 共享
```

**三层并发控制（源码研究，task.go:767 + agent.sql:206 + daemon.go:1752）**：

**层 1：per-agent `max_concurrent_tasks`（agent 级别，最关键）**
```go
// task.go:767 — 每次 claim 前检查
running, _ := s.Queries.CountRunningTasks(ctx, agentID)
if running >= int64(agent.MaxConcurrentTasks) {
    return nil, nil // No capacity — 不 claim，等待
}
```
- 每个 agent 独立计数，默认上限 **6**
- 同一个 agent 被分配 N 个不同 issue → 最多同时跑 6 个，第 7 个排队

**层 2：per-(agent, issue) 串行（SQL 层）**
- 同一个 agent + 同一个 issue → 强制串行，防重复执行

**层 3：daemon 全局 semaphore**
- daemon 进程全局 `MaxConcurrentTasks`（默认 6），所有 runtime 共享

**核心结论**：
1. **子 issue 分配给同一个 agent** → 受 per-agent `max_concurrent_tasks` 限制，默认最多 6 个并发，第 7 个排队
2. **子 issue 分配给不同 agent** → 完全并行，互不干扰（每个 agent 独立计数）
3. **同一 issue + 同一 agent** → 强制串行
4. **跨 workspace** → 完全隔离，agent 硬绑定到 workspace

**对 Squad leader 分配策略的直接影响**：
- 分配给**不同 member agent** 的子 issue → 真正并行（推荐，每个 member 独立计数）
- 分配给**同一 member agent** 的多个子 issue → 最多并发 6 个（受该 agent 的 max_concurrent_tasks 限制）
- 同一 issue 上连续 @mention 同一个 agent → 串行（SQL 层锁）
- **最佳实践**：Squad 里不同 member 各自负责不同子任务，这才是真正的并行。把所有子任务都堆给同一个 member 只能拿到 6 个并发，还不如直接把 max_concurrent_tasks 调大

---

### 核心设计思路

**启动时角色检测**（在 AGENTS.md / session-start hook 中）：
```bash
if [[ -n "$MULTICA_SQUAD_ID" && "$MULTICA_IS_LEADER" == "true" ]]; then
  # Leader 路径：路由 + 分配，不直接执行
elif [[ -n "$MULTICA_SQUAD_ID" ]]; then
  # Member 路径：执行，但 HITL 优先上报 leader
else
  # 单 agent 路径：现有 MVP 行为
fi
```

### 可以交给 Leader 的判断

| 判断类型 | MVP 现在的处理 | Squad Leader 可以做的 |
|---------|--------------|---------------------|
| 任务分解 | 执行 agent 自己拆 stories | Leader 读 roster，按成员能力分配 stories |
| ≥3次修复失败 | 直接 HITL 给人类 | 先 @mention leader，leader 决定换人还是上报人类 |
| Verification 失败 | 循环回 execute | Leader 决定同一成员继续 or 换更擅长的成员 |
| HITL 分级 | 所有 HITL 直接到人类 | 轻量决策 → leader；架构级 → 人类 |
| Story 并行分配 | 串行或 subagent（单 session） | Leader @mention 多个成员，真正并行（各自独立 daemon session） |

### 新增文件（v0.2.0）

**`skills/core/squad-workflow.md`**（leader 路径）
- 如何读取 roster：从 briefing 里的 `## Squad Roster` 解析（已注入 Instructions，不需要额外 CLI）
- 任务分配的两种策略（**核心决策，影响是否真正并行**）：
  - **策略 A：子 issue 分配**（推荐，真正并行）
    ```
    multica issue create --title "子任务：..." --assignee-id <member-uuid> --status todo
    ```
    不同 issue_id → 数据库层允许多个 member 真正并行运行
  - **策略 B：@mention 分配**（适合串行或顺序依赖的任务）
    ```
    [@Name](mention://agent/<uuid>) 请处理 X
    ```
    同一 issue_id → 同一个 agent 上的任务强制串行，适合有先后依赖的步骤
- 何时选策略 A vs B：
  - 任务相互独立、可并行 → 策略 A（子 issue）
  - 任务有顺序依赖 → 策略 B（@mention，等前一个完成再触发下一个）
  - 任务太小不值得开子 issue → 策略 B
- 如何跟踪子 issue 完成状态：`multica issue list --project <id>` 或监听 comment 回报
- 如何汇总结果写回父 issue

**`skills/core/squad-member-workflow.md`**（member 路径）
- 收到 @mention 后如何提取任务上下文
- HITL 分级：`[HITL:leader]` comment @mention leader vs `[HITL:human]` 上报人类
- 完成后如何回报 leader（@mention + 结果摘要）

**`hooks/session-start.sh` 扩展**
- 检测 `$MULTICA_SQUAD_ID` / `$MULTICA_IS_LEADER` 环境变量
- Leader session：注入 roster 信息到 Priority Context
- Member session：注入"当前被分配的任务来自 leader @mention"上下文

**`capabilities/claude-code.json` 扩展**
```json
{
  "squad-leader": "native",
  "squad-member": "native"
}
```

### HITL 两级分级协议

```
Member 遇到决策困难时：
  → 写 [HITL:leader] comment，@mention leader UUID
  → 设 blocked（等 leader 的 on_comment 唤醒）
  → Leader 收到通知，判断：
      简单决策 → 直接回复 comment，member 继续
      架构级问题 → 写 [HITL:human] comment，@mention 人类成员
      换人 → @mention 另一个成员接手
```

### Smoke 场景补充（v0.2.0）

场景 5 — Leader 路由验证：
- 创建 squad issue，mock squad roster（leader + 2 members）
- 验证 leader 写分配 comment（含 @mention member UUID）
- 验证 member 被唤醒后执行正确的子任务

场景 6 — Squad HITL 两级分级：
- Member 触发 ≥3次修复规则
- 验证先写 `[HITL:leader]` 而非直接 `[HITL:human]`
- 验证 leader 回复后 member 能继续

### 依赖的 Multica 环境变量（待确认）

- [ ] `$MULTICA_SQUAD_ID` — 当前 issue 所属 squad ID（daemon 注入）
- [ ] `$MULTICA_IS_LEADER` — 当前 agent 是否是 squad leader（daemon 注入）
- [ ] `$MULTICA_SQUAD_ROSTER` — roster JSON（或通过 CLI 查询）

**源码研究结论（无需确认，已从代码得出）**：

**1. 角色识别方式**：不是环境变量，是通过 Instructions 文本检测。
```go
// daemon.go:2260
IsSquadLeader: strings.Contains(instructions, "## Squad Operating Protocol"),
```
daemon 检测 `resp.Agent.Instructions` 是否包含 `"## Squad Operating Protocol"` 字符串来判断是否是 leader。**插件不需要读环境变量，只需在 session-start hook 里检测 AGENTS.md / Instructions 是否含这个标记。**

**2. Leader briefing 注入路径**：通过 `--append-system-prompt`（claude 的 `AgentInstructions` 字段），不是环境变量。briefing 内容包含：
- `## Squad Operating Protocol`（固定规则，含 `multica squad activity` 命令）
- `## Squad Roster`（成员花名册，含完整 `[@Name](mention://agent/<uuid>)` markdown）
- `## Squad Instructions`（用户自定义，可选）

**3. Leader 的核心工作流**（从 runtime_config.go:373-380 得出）：
- Assignment-triggered：读 issue → 设 in_progress → **判断委派谁** → 写 comment @mention → `multica squad activity <id> action --reason "..."` → 设 in_review
- Comment-triggered（收到成员回报）：读新 comment → 决定是否需要行动 → 若 no_action：只调 `multica squad activity <id> no_action --reason "..."` 然后**静默退出**（不写任何 comment）

**4. Member 的识别**：Member agent 启动时没有 `## Squad Operating Protocol` 在 Instructions 里，但 runtime_config 对 member 注入了 mention 规则（避免回复时 @mention 触发循环）。Member 自己不需要特殊检测，只需按正常执行流程工作。

**5. `multica squad activity` 命令**：Leader 每次 turn 结束时必须调用，outcome 值：`action` / `no_action` / `failed`。这是强制的，不是可选的。插件的 squad-workflow.md 必须包含这个约束。

**6. 子 issue 委派 vs @mention 委派**（runtime_config.go:392）：
- `--status todo` + agent assignee = 立即触发（assignment IS the trigger）
- @mention = 也触发
- 两个不能同时用于同一工作，否则 agent 执行两次

**v0.2.0 设计修正**：
- 删除 `$MULTICA_IS_LEADER` 环境变量方案
- session-start hook 改为：检测 `$MULTICA_PLUGIN_ROOT/skills/advanced/persistence-loop.md` + grep Instructions 是否含 `## Squad Operating Protocol`
- `squad-workflow.md` 核心约束：每 turn 必须调 `multica squad activity`，no_action 时静默退出不写 comment

---

## v0.3.0 Roadmap — 可靠性提升 + Subagent Dispatch

### 背景：推动方式的可靠性问题

深度研究 GSD（get-shit-done）后发现，agent 工作流的推动可靠性差异很大：

| 推动方式 | 可靠性 | 例子 |
|---------|--------|------|
| 程序 spot-check（文件存在性）| 高 | GSD 用 SUMMARY.md 存在 + git commit 检测完成 |
| shell 脚本强制（grep/flock）| 高 | stop.sh 的 `<promise>DONE</promise>` 检测 |
| 环境变量注入 | 高 | session-start 注入已知值到 context |
| LLM 读 skill 文字 + 执行命令 | 中 | verification Gate Function（执行命令看输出）|
| LLM 纯纪律（文字约定）| 低 | squad activity 每 turn 必调用、3-strike 计数 |

**当前插件的主要可靠性缺口**（v0.1.0 + v0.2.0 都有）：
- 3-strike 计数：LLM 靠 `metadata.set` 自己记，容易出错
- squad activity 强制：stop.sh 只是事后写 warning，不直接修复
- delegation 决策：leader 选策略靠读 skill 文字，无程序追踪
- 模型路由：skill 文字说"haiku/sonnet/opus"，LLM 自己判断

### GSD 对我们的启发（深度研究结论）

**GSD 真正做的关键设计**：
1. **文件系统是 agent 间通信总线**：PLAN.md/SUMMARY.md 有严格的 frontmatter schema，程序 parse 而非 LLM 读文字
2. **Spot-check 优先于 marker**：orchestrator 看 git commit + SUMMARY.md 存在，不只依赖 LLM 写标记
3. **模型路由是程序决定**：`gsd-sdk query resolve-model <agent>` 返回 opus/sonnet/haiku，不让 LLM 猜
4. **Wave 依赖是程序解析**：PLAN.md frontmatter 的 `depends_on` 字段，程序算依赖图
5. **Context budget 程序监控**：PostToolUse hook 读 token 计数，≤35% 注入 WARNING，≤25% 注入 CRITICAL

### v0.3.0 核心交付（4 个高 ROI 可靠性提升）

**P0 — 3-strike 计数程序化**

现状：LLM 靠 `metadata.set` 自己记 bounce 次数，容易忘或记错。

修复方案：
- `hooks/session-start.sh` 从 `.multica/state/<issue_id>/hitl-bounces.json` 读取计数
- 格式：`{"<question_id>": {"count": 2, "last_at": "<ISO8601>", "tier": "leader"}}`
- session-start 注入到 additionalContext：`"HITL bounce count for <question_id>: 2/3"`
- LLM 看到明确数字，不用自己数
- member skill 写 bounce 时也更新文件（而非只靠 metadata.set）

**P0 — squad activity 调用强制化**

现状：stop.sh 检测到跳过时只写 warning 文件，下次 session 才提示。

修复方案：
- stop.sh 检测 leader 跳过 activity 时，**直接调用** `multica squad activity <id> failed --reason "activity-not-recorded-by-agent"`
- 让 multica server 端留下记录，不依赖 LLM 在下次 session 看到 warning 再处理
- 同时保留 squad-audit-warning 文件，让 session-start 也能提示

**P1 — subagent dispatch 规范**（借鉴 GSD 的 agent tier 设计）

新增 `skills/advanced/subagent-dispatch.md`，规定：

模型路由规则：
```
Task(subagent_type="oh-my-claudecode:executor", model="haiku")
  → 机械实现（单文件、明确规范、无判断）

Task(subagent_type="oh-my-claudecode:executor", model="sonnet")
  → 标准实现（多文件协调、需要判断）

Task(subagent_type="oh-my-claudecode:code-reviewer", model="opus")
  → 架构 review、安全检查

Task(subagent_type="oh-my-claudecode:debugger", model="sonnet")
  → 调试（根因分析）
```

Fresh context 原则（来自 GSD）：
- subagent 不继承主 session 的对话历史
- prompt 必须包含完整的任务上下文（不能说"参考 issue 做 X"）
- subagent 输出结果写入文件（SUMMARY.md 风格）或 multica comment，不依赖 return value

**P1 — 模型路由从 skill 文字变成环境变量注入**

`hooks/session-start.sh` 读 `capabilities/claude-code.json` 中的模型配置（待新增字段），
注入：
```bash
MULTICA_MODEL_FAST=haiku      # 机械任务
MULTICA_MODEL_STD=sonnet      # 标准任务
MULTICA_MODEL_DEEP=opus       # 复杂/review 任务
```

subagent-dispatch.md 引用这些变量而非硬编码模型名，未来升级模型只改 capabilities JSON。

**P2 — Context budget 感知（借鉴 GSD context-monitor）**

`hooks/session-start.sh` 扩展（或新增 pre-tool hook）：
- 读取 Claude Code 的 context usage 指标（如有）
- 注入 context 状态到 additionalContext：
  - `>35%` 剩余：正常
  - `≤35%`：`[context-warning] checkpoint before new work`
  - `≤25%`：`[context-critical] summarize and blocked`
- `multica-workflow.md` 新增规则：收到 context-critical 时写 checkpoint comment + blocked

### 新增文件

| 文件 | 内容 |
|------|------|
| `skills/advanced/subagent-dispatch.md` | subagent 派发规范：模型路由 + fresh context 原则 + 输出格式 |
| `.multica/state/<issue_id>/hitl-bounces.json` | 3-strike 计数的程序存储（运行时生成，非静态文件）|

### 修改文件

| 文件 | 修改内容 |
|------|---------|
| `hooks/stop.sh` | leader 跳过 activity 时直接调用 `multica squad activity failed` |
| `hooks/session-start.sh` | 读 hitl-bounces.json 注入计数 + 注入模型环境变量 |
| `skills/core/squad-member-workflow.md` | bounce 计数写文件（不只靠 metadata.set）|
| `capabilities/claude-code.json` | 新增 model_routing 字段 |

### 可靠性改进对比

| 机制 | v0.2.0 | v0.3.0 |
|------|--------|--------|
| 3-strike 计数 | LLM metadata.set（低）| 文件 + session-start 注入（高）|
| squad activity 强制 | 事后 warning（低）| stop.sh 直接调用（高）|
| 模型路由 | skill 文字（低）| 环境变量注入（高）|
| subagent dispatch | parallel-exec.md 文字（低）| subagent-dispatch.md 明确规范（中）|
| context budget | 无 | hook 监控 + workflow 规则（中）|


---

## v0.4.0 Roadmap — 知识管理升级（去重 + 多机协调）

### 背景：研究来源

深度研究了三个开源项目的知识管理机制：
- **Hermes Agent**（NousResearch）：Curator agent + skill lifecycle（active→stale→archived）+ dialectic reasoning 去重
- **Graphify**（safishamsi）：三层去重（精确/MinHash/Union-Find）+ stat-based 增量缓存 + `build_merge` 永远增量不替换
- **LLM Wiki**（Karpathy 模式）：三层架构（Raw→Wiki→Reference Graph）+ stale_since 因果链传播 + Lint 机制

### 核心设计原则（三个项目共同验证）

1. **不用 TTL，用因果链** — 知识过时是因为依赖的事实变了，不是因为时间到了
2. **写入时不强去重，整理时批量去重** — 实时去重影响写入；离线 curate 更安全
3. **Confidence 是权重，不是删除信号** — 低 confidence 归档而不删除
4. **程序检测 + LLM 决策分离** — 程序发现 stale，LLM 决定是更新还是删除

### 关键发现：多机协调问题

当前 `.multica/` 目录下的所有知识文件（`learnings.jsonl`、`notepad.md`）**都在本地机器**。

Multica daemon 每次 claim task 可能分配给不同机器，知识文件无法自动跨机器同步：

```
机器 A（Agent 处理 Issue #42）→ 写 learnings.jsonl
机器 B（下次 claim Issue #42）→ 文件不存在，知识丢失
```

**三条解决路径**：

| 路径 | 方式 | 代价 | 依赖 |
|------|------|------|------|
| A | Multica issue comment（已有）| 非结构化 | 无 |
| B | Git commit `.multica/learnings.jsonl` | stop.sh 加 commit 步骤 | 项目有 git |
| C | multica knowledge set/get API | 最干净 | multica 上游支持 |

**v0.4.0 采用路径 B**：stop.sh 完成路径加 git commit learnings，代价最小。
路径 C 记为 open question，等 multica 上游计划。

注：`loop.json` 跨机器问题相对小（daemon 有 `PriorWorkDir` session 复用逻辑）。

### v0.4.0 交付内容

**P0 — learnings 去重（借鉴 Graphify build_merge + Hermes Curator）**

新增 `tools/curate-memory.sh`：
- 按 key 去重：同一 key 只保留最新一条（append-only 读时去重）
- Confidence 衰减：>90天未更新 -2，>180天 -4
- 归档：confidence < 3 的条目移到 `.multica/learnings-archive.jsonl`
- 原子写（mktemp + mv）

**P0 — staleness 检测（借鉴 Graphify stat-based + LLM Wiki stale_since）**

`hooks/session-start.sh` 注入前检测：
- 读 learning 的 `files` 字段，检查源文件 mtime
- 源文件不存在或比 learning 更新 → confidence -= 2（该 learning 可能过时）
- 注入时标注：`[possibly stale] test-thread-config (conf:5) ...`

**P0 — learnings git commit（解决多机协调）**

`hooks/stop.sh` 完成路径（输出 `<promise>DONE</promise>` 后）：
```bash
if [[ -f "${MULTICA_WORKDIR}/.multica/learnings.jsonl" ]]; then
  git -C "$MULTICA_WORKDIR" add .multica/learnings.jsonl 2>/dev/null || true
  git -C "$MULTICA_WORKDIR" diff --cached --quiet || \
    git -C "$MULTICA_WORKDIR" commit -m "chore(knowledge): update learnings [skip ci]" 2>/dev/null || true
fi
```

**P1 — 写入时程序强制（替代 LLM 纪律）**

借鉴 LLM Wiki 的「ingest 后必须更新 overview」强制规则：

stop.sh 完成路径加一步：调用 haiku subagent 做 memory consolidation：
```bash
# 仅在有新 comment 时触发（避免每次都付费）
if [[ <本轮有新 comment> ]]; then
  Task(model="haiku", prompt="读本轮执行的 issue comment，
    提取有价值的经验写入 .multica/learnings.jsonl，
    格式：{ts,skill,type,key,insight,confidence,files}
    只写确定有价值的经验，不确定的跳过")
fi
```

**P1 — notepad Working Memory prune**

stop.sh 完成路径：清理 7 天前的 Working Memory 条目（现有字段已有 timestamp，只是没有执行清理）：
```bash
awk -v cutoff="$(date -d '7 days ago' +%Y-%m-%dT)" '
  /^## Working Memory/ { section=1 }
  /^## / && !/Working Memory/ { section=0 }
  section && /^\[20/ { if (substr($0,2,19) < cutoff) next }
  { print }
' .multica/notepad.md | atomic_write .multica/notepad.md
```

**P2 — Open Question：multica knowledge API**

向 multica 上游提议新增：
- `multica knowledge set <workspace_id> <key> <value>` — 服务端 KV 存储
- `multica knowledge get <workspace_id> <key>` — 跨机器读取
- `multica knowledge list <workspace_id>` — 列出所有 key

这样 learnings 可以从 git 文件升级为服务端 API，彻底解决多机协调问题，且不依赖项目有 git repo。

### 新增文件

| 文件 | 内容 |
|------|------|
| `tools/curate-memory.sh` | learning 去重 + confidence 衰减 + 归档 |

### 修改文件

| 文件 | 修改内容 |
|------|---------|
| `hooks/stop.sh` | 完成路径：git commit learnings + notepad prune + memory consolidation subagent |
| `hooks/session-start.sh` | learnings 注入前做 staleness 检测，标注可能过时的条目 |

