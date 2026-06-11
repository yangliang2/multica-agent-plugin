# ADR-0002: Child Issue Linking for Planning Mode Breakdowns

**Status:** Accepted | **Date:** 2026-06-11 | **Relates to:** REQ-04-01, REQ-04-02

## Context

Planning mode (v2.3.0) decomposes a macro issue (epic/initiative/roadmap) into child
issues after the user approves a `[breakdown:vN]` comment. Squad members may run on
different machines with no shared filesystem, so the parent/child relationship and
inter-task dependencies must live entirely in multica issue metadata — the only state
store all agents can reach.

## Decision

Each child issue created via `<<cli:issue.create.child>>` carries three metadata keys
plus dependency links:

| Key | Value | Purpose |
|-----|-------|---------|
| `parent_id` | The breakdown issue's ID | Members fetch parent context (roster, leader status) without filesystem access |
| `epic_id` | The epic issue's ID (= `parent_id` unless the parent is itself a child of an epic) | Cross-cutting queries: "all tasks in this epic" |
| `squad_id` | Squad identifier from the runtime roster | Activity attribution and capacity checks |
| `blocks:` | Sibling child issue IDs this task blocks | Encodes the breakdown's dependency column; the daemon schedules accordingly |

Set via `<<cli:issue.metadata.set>>` immediately after creation, before any member
assignment, so the metadata is present on the member's very first `<<cli:issue.get>>`.

## Rationale

- **Metadata over shared files:** `.multica/state/` is per-workdir; child issues may be
  claimed by agents on other machines. Issue metadata is the only universally readable
  channel (REQ-04-03 builds member↔leader state exchange on the same channel).
- **`blocks:` from the breakdown table:** the dependency column in `[breakdown:vN]` is
  the human-reviewed source of truth; copying it into `blocks:` links means the
  approved plan and the scheduler's view cannot drift.
- **Daemon-driven backlinks:** the daemon auto-notifies the parent when a child is
  done (verified in multica source, see CHANGELOG 1.0.0 research notes) — the leader
  does not write manual backlink comments.

## Consequences

- Leaders must not create child issues before the user posts `[proceed]` — metadata is
  written only once, at creation time.
- A revised breakdown after children exist requires manual reconciliation (out of
  scope for v2.3.0; revisions are expected before approval, not after).
