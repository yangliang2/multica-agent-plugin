<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-06-07 | Updated: 2026-06-07 -->

# skills/core

## Purpose
Always-active workflow skills loaded at every Multica agent session. These define the normative contracts for the 5-phase state machine, HITL protocol, verification Iron Law, systematic debugging, and Squad coordination.

## Key Files

| File | Description |
|------|-------------|
| `multica-workflow.md` | 5-phase state machine (discover → plan → execute → verify → report) with CLI call sequences, exit conditions, and loop.json checkpoint protocol. The most-read skill in the repo. |
| `hitl-protocol.md` | Human-in-the-loop protocol — qualifying conditions, `[HITL]` comment template, `blocked` lifecycle, and Squad escalation path (`[HITL:leader]` before `[HITL:human]`). |
| `verification.md` | Verification Iron Law — rules for what counts as verified evidence before claiming `done`. Agents must satisfy this before setting status to `done`. |
| `systematic-debug.md` | Structured debugging skill — hypothesis-driven root-cause analysis, bisect strategy, and evidence collection protocol. |
| `squad-leader-workflow.md` | Squad Leader protocol — role detection, delegation via roster, `<<cli:squad.activity>>` call cadence, and member escalation handling. |
| `squad-member-workflow.md` | Squad Member protocol — triggered by leader @mention, work scope boundaries, and `[HITL:leader]` escalation path. |

## For AI Agents

### Working In This Directory
- These skills are normative: changing them affects ALL Multica agent sessions.
- CLI calls must use `<<cli:*>>` anchors only — never raw `multica ...` literals.
- When adding a new phase or protocol step, update `multica-workflow.md` AND `capabilities/claude-code.json` if it requires a new harness capability.

### Common Patterns
- Skills reference each other by filename: `(see hitl-protocol.md)`.
- Harness-specific degradation notice pattern: `> **Degradation notice:** When running outside Claude Code, this skill is a no-op.`

## Dependencies

### Internal
- `capabilities/claude-code.json` — thresholds (`hitl_timeout_hours`, `loop_max_iterations`) read at runtime
- `docs/abi/cli-outward.md` — anchor resolution reference

<!-- MANUAL: -->
