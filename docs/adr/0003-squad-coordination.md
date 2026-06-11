# ADR-0003: Squad Coordination via Issue Metadata

**Status:** Accepted | **Date:** 2026-06-11 | **Relates to:** REQ-04-03, REQ-04-04

## Context

Squad members and leaders may run on different machines. There is no shared
filesystem; the only state channels every agent can reach are multica issue
metadata and issue comments. v2.3.0 needs (a) a member↔leader state exchange and
(b) a leader-side checkpoint that detects stuck members without polling files.

## Decision

### Member state schema (issue metadata)

Each child issue carries, in addition to the linking keys from ADR-0002
(`parent_id`, `epic_id`, `squad_id`, `blocks:`):

| Key | Written by | Value |
|-----|-----------|-------|
| `member_status` | member, before any terminal status change | JSON: `{"status": "done" \| "blocked" \| "in_progress", "updated_at": "<ISO8601>", "summary": "<one line>"}` |

Members write `member_status` BEFORE setting issue status, so the leader's
checkpoint never observes a terminal status without the explanatory metadata.

### Leader checkpoint (program-enforced, stop hook)

At every leader session end, `hooks/stop.sh` (`squad_children_checkpoint`):

1. Reads `loop.json.child_issues` (recorded by the leader at child creation).
2. Fetches each child's status (`issue get`) and recent comments (`comment list`).
3. **All children `done`** → sets `loop.json.phase=result` and posts
   `[phase] execute→result`.
4. **Stuck detection** — a non-done child whose latest comment is older than
   `loop.json.squad_stuck_threshold_minutes` (default 120) relative to the
   *newest server timestamp seen across all children* → posts
   `[checkpoint] squad-stuck` naming the stuck members, rate-limited to one
   comment per hour.

### Clock-source rule

Stuck elapsed time is computed exclusively from server-side `created_at`
timestamps compared against each other. The local system clock is never part of
the comparison: in multi-machine deployments local clocks can skew by minutes,
which would produce false stuck alerts. A child with no comments at all is not
judged (no server-time evidence either way).

## Consequences

- The checkpoint only sees children listed in `loop.json.child_issues`; children
  created outside the planning flow must be appended there manually.
- The reference clock is "newest comment anywhere in the squad" — if the entire
  squad is silent, no stuck alert fires (by design: a uniformly idle squad is a
  scheduling state, not a member failure).
- All checkpoint actions are fail-soft: CLI or parse failure logs to
  `hook-errors.log` and never blocks the session exit.
