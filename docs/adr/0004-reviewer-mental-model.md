# ADR-0004: Reviewer Mental Model — Signals Over Internals

**Status:** Accepted | **Date:** 2026-06-11 | **Relates to:** REQ-10-01, REQ-10-03

## Context

Reviewers should be able to act on an issue timeline without understanding hooks,
loop.json, or phase internals. v2.3.0's multi-session model makes the comment trail
the *entire* interface: every session exit lands on a signal a human can answer.

## Decision

The reviewer-facing contract is exactly three rules, documented in HUMAN-GUIDE §4:

1. **Every agent comment that needs you starts with a bracketed signal**
   (`[spec:vN]`, `[demo:vN]`, `[breakdown:vN]`, `[verify-failed]`, `[result]`,
   `[HITL]`). Anything else (`[checkpoint*]`, `[verification]`, `[phase]`) is
   informational.
2. **Your reply is also a signal** (`[proceed]`, `[revise: ...]`,
   `[looks-right]`, `[wrong: ...]`, `[retry]`, `[abort]`) — one per line, feedback
   inside the brackets (that text becomes the captured learning).
3. **No reply needed = no signal addressed to you.** Silence never blocks the
   pipeline except at the designed checkpoints (spec, demo, result, HITL).

The "You see X → do Y" table in HUMAN-GUIDE §4 is the canonical lookup and must be
updated whenever a signal is added to the grammar in §2.

## Consequences

- Documentation duty travels with grammar changes: a new signal without a §4 table
  row is a docs regression.
- Reviewer docs deliberately omit hook/loop.json internals; those live in §5
  (operators) and the skills.
