# ADR 0001 — Claude Code MVP as Initial Target Harness

**Status:** Accepted  
**Date:** 2026-05-23  
**Deciders:** multica-agent-plugin team

---

## 1. Decision

**Adopt Claude Code as the sole supported harness for the 0.1.0 MVP.**

`AGENTS.md` is the single source of truth for agent behavior contracts.
All other files (`CLAUDE.md`, skills, hooks) are additive affordances layered
on top of `AGENTS.md`; they must not contradict it.

Post-MVP harness adapters (Codex, Cursor, Gemini, Kimi) will target the same
`AGENTS.md` contract and supply harness-specific shims without touching core
skill logic.

---

## 2. Drivers

### 2.1 Daemon-First, Non-Interactive Runtime

Multica runs agents headlessly. Claude Code's hook system (Stop, PreToolUse,
SessionStart) provides the only available mechanism for enforcing loop
continuation and injecting session context without requiring interactive
prompts. No other harness in scope offers an equivalent hook surface today.

### 2.2 Verification Iron Law — Preventing False Completion Reports

Daemon agents have no human reviewer watching turn-by-turn output. Without an
enforced verification gate, agents self-report completion speculatively.
Claude Code's Stop hook allows the persistence loop to block session exit until
the `<promise>DONE</promise>` signal is emitted, turning the Iron Law from a
guideline into a structural constraint.

### 2.3 PRD Story Tracking — Preventing Progress Loss

Multi-session tasks in a daemon context are interrupted by restarts, compaction,
and timeouts. Without durable story state, progress is lost silently. The
`loop.json` schema combined with the Stop hook's checkpoint-comment mechanism
provides resumability and auditable iteration history that other harnesses
cannot replicate at the hook level without custom server-side infrastructure.

---

## 3. Framework Synthesis

The design distills contributions from five frameworks into a coherent plugin:

### 3.1 OMC ralph — PRD Story Tracking + Stop Hook + Deslop Pass

ralph introduced the self-referential loop: decompose into stories, implement,
verify story-by-story, block exit until all stories pass. This plugin maps that
pattern onto `loop.json` + `hooks/stop.sh`. The deslop pass (removing
speculative comments, over-defensive guards, redundant annotations) is taken
directly from ralph's cleanup phase and embedded in `skills/advanced/persistence-loop.md`
Step 6.

### 3.2 Superpowers — Verification Iron Law + 5-Step Gate + Systematic Debug 4 Phases + ≥3 Rule

Superpowers contributed the non-negotiable verification discipline:
- **Iron Law**: no completion claim without fresh command evidence.
- **5-Step Gate Function**: IDENTIFY → RUN → READ → VERIFY → CLAIM.
- **Systematic Debug 4 Phases**: root cause investigation → pattern analysis → hypothesis/test → implementation.
- **≥3 Rule**: after three failed fix attempts, mandatory HITL escalation instead of continued guessing.

These are encoded verbatim in `skills/core/verification.md` and
`skills/core/systematic-debug.md` with daemon-safe adaptations (no interactive
prompts; evidence written to issue comments, not agent memory).

### 3.3 oh-my-openagent — Completion Signal Protocol `<promise>DONE</promise>`

oh-my-openagent defined the explicit completion signal: an agent must emit the
literal byte sequence `<promise>DONE</promise>` to signal genuine task
completion. This plugin adopts the signal verbatim in `skills/advanced/persistence-loop.md`
and wires it to the Stop hook scan in `hooks/stop.sh`. The hook cross-checks
`loop.json` active state so the signal cannot be faked without also updating
story state.

### 3.4 GSD — Context Rot Protection (AGENTS.md ≤ 150 Lines, Skill On-Demand Loading)

GSD established that context windows bloat fatally when all knowledge is
front-loaded. This plugin enforces:
- `AGENTS.md` hard cap of 150 lines (verified by smoke Scenario 1).
- Skills loaded on demand via the Skills Index rather than inlined into `AGENTS.md`.
- Session context injected selectively by `hooks/session-start.sh` (≤500 chars
  priority context, top-20 learnings filtered by recency and confidence).

### 3.5 gstack — Taste Memory (learnings.jsonl, Cross-Session Project Knowledge)

gstack introduced the persistent learning store: a JSONL file that accumulates
observations, fixes, constraints, and patterns with confidence scores across
sessions. This plugin implements the store at `.multica/learnings.jsonl` with
the schema defined in `CLAUDE.md`. `hooks/session-start.sh` injects the 10 most
recent entries plus all entries with `confidence >= 7` as advisory context at
session start, providing durable project memory without inflating AGENTS.md.

---

## 4. Consequences

### 4.1 Scope Constraint

This release supports **Claude Code only**. Operators using other harnesses
will see degradation notices in advanced skills and must implement continuation
and context injection manually.

### 4.2 Post-MVP Extension Path

Harness adapters will be introduced in subsequent minor versions:

| Version | Harness | Mechanism |
|---------|---------|-----------|
| v0.2.0 | Codex | CLI hook adapter; loop.json + exit-code protocol |
| v0.3.0 | Cursor | IDE extension context injection; no Stop hook equivalent |
| v0.4.0 | Gemini Code Assist | Google Cloud context; auth shim required |
| v0.5.0 | Kimi | Locale handling; i18n pass on skills |

Each adapter must satisfy the same `AGENTS.md` contract. Skills must not be
forked per harness; harness-specific behavior lives in adapter shim files only.

### 4.3 Tooling Dependency

Install and uninstall require `python3` for JSON merging. Environments without
Python 3 must perform manual `settings.json` editing. This dependency will be
removed in v0.2.0 using a pure-shell JSON approach.

---

## 5. Follow-Ups

1. **Other harness adapters** — Design the adapter interface so each harness
   can implement Stop-equivalent blocking and context injection without modifying
   core skill files. Target: v0.2.0 (Codex).

2. **Capability auto-detection** — `capabilities/claude-code.json` is currently
   maintained manually. Automate detection at install time by probing the active
   harness and writing the capability matrix programmatically.

3. **i18n** — Skill files currently mix English and Chinese. Decide on a single
   authoring language and provide translation scaffolding before v1.0.0.

4. **Pure-shell JSON merge** — Replace the `python3` requirement in `install.sh`
   and `uninstall.sh` with a portable shell implementation.

5. **Learnings compaction** — Define a compaction strategy for `.multica/learnings.jsonl`
   (e.g., merge duplicate keys, prune entries below a confidence threshold)
   before the file grows unbounded in long-running projects.
