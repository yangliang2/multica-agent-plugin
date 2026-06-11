# ADR-0005: Operator Intervention Points

**Status:** Accepted | **Date:** 2026-06-11 | **Relates to:** REQ-10-02

## Context

The v2.3.0 loop is designed to be self-recovering (graceful context handoff,
verify retries, HITL replay, squad checkpoints). Operators need a short, closed
list of the states that genuinely require a human — everything else should be
left alone to converge.

## Decision

Exactly four intervention triggers, documented with remedies in HUMAN-GUIDE §5:

| Trigger | Signal | Remedy |
|---------|--------|--------|
| Iteration cap hit | `[loop-exhausted]` | Fix blocker, post `[retry]` (resets counter, re-enqueues) |
| Repeated failure / aged HITL | `[loop-stuck]` | Answer the question or re-scope the issue |
| Thrash (iteration ↑, `progress.pct` frozen) | none (read loop.json) | Steering comment or `[abort]` |
| Abnormal exit (`blocked`, no `[HITL]`) | none | Check `hook-errors.log`, `multica issue rerun` |

Squad leaders additionally follow the stuck-member checklist (HUMAN-GUIDE §5);
member silence is surfaced automatically by the leader's stop-hook checkpoint
(`[checkpoint] squad-stuck`, ADR-0003) — operators react to that comment rather
than polling.

Everything not in this table is explicitly **not** an intervention point:
`[checkpoint*]` comments, context handoffs, verify retries 1–2, and HITLs younger
than the timeout are normal operation.

## Consequences

- `tools/loop-status.sh` is the only tool an operator needs for diagnosis; if a
  future health dimension can't be read from it (or the issue timeline), extend
  the tool rather than documenting raw file spelunking.
- Auto-recovery changes (e.g. new handoff types) must update the §5 table to keep
  the "leave it alone" set accurate.
