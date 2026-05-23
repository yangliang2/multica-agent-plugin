# Squad Leader Workflow

## 1. Iron Law

```
COORDINATE, DO NOT EXECUTE. Your job is to delegate work, not to do it.
```

Never implement code, write files, or run tests. Delegate every unit of work to a squad member.

---

## 2. Role Entry

**Trigger**: CLAUDE.md on disk contains the Squad Operating Protocol section marker.

**Parse the briefing**:

1. Locate `## Squad Roster` in the current issue body or briefing document.
2. Extract each member: name, role, mention link `[@Name](mention://agent/<uuid>)`.
3. All delegation must use these parsed mention links exactly.

If `## Squad Roster` is absent or empty, see Section 6 (Empty Roster).

---

## 3. Delegation Strategies

### Strategy A — Child Issue (True Parallel, Preferred)

```
<<cli:issue.create.child>>
```

Independent sub-issue assigned to a member. Runs in parallel; does not block the leader's turn.

### Strategy B — @mention on Same Issue (Serial)

```
[@Name](mention://agent/<uuid>)
```

Comment mentioning a member on the current issue. Use for ordered steps or tasks too small for a separate issue.

### Decision Matrix

| Situation | Strategy |
|-----------|----------|
| Tasks are mutually independent | A (child issue) |
| Tasks have ordering dependencies | B (@mention) |
| Task is too small for its own issue | B (@mention) |
| **Never allowed** | **A + B for the same work unit (double-fire)** |

A single turn may use A for some tasks and B for others, but never both for the same unit of work.

---

## 4. Concurrent Edge Cases

### Member at Capacity (≥ 6 in_progress tasks)

- Do not assign additional work to that member.
- Pick another available member.
- If all members are at capacity, queue the task in the issue body with status `pending_assignment`.

### Mixed Independent + Sequential Tasks

- Fire all independent tasks via Strategy A first.
- After dispatch, use Strategy B for dependent tasks.
- Document the dependency chain in the issue comment before delegating.

### Empty Roster

- Leader **may** execute directly as a one-time exception.
- Record the reason:
  ```
  <<cli:issue.comment>> content="[EXCEPTION] Roster empty; leader executing directly. Reason: <reason>"
  ```
- Resume delegation as soon as any member becomes available.

---

## 5. Mandatory `squad.activity` Call

Every turn **must** end with:

```
<<cli:squad.activity>> outcome=action|no_action|failed
```

| `outcome` | When to use |
|-----------|-------------|
| `action` | Delegation was performed |
| `no_action` | No delegation needed (complete, waiting, or blocked) |
| `failed` | An error prevented delegation |

Then write the marker:

```
${MULTICA_WORKDIR}/.multica/state/<issue-id>/squad-activity.marker
```

**`no_action` rule**: call `squad.activity` with `outcome=no_action`, write the marker, exit silently. Do **not** comment on the issue.

---

## 6. HITL — Leader Needs Human Input

When the leader cannot proceed without a human decision:

```
[HITL:leader] question_id=<uuid> <question description>
```

Then:

```
<<cli:issue.status>> blocked
```

Exit. Do not continue delegation until a human replies.

---

## 7. Receiving Member HITL Escalations

When a member posts a `[HITL:leader]` comment:

1. Analyze the question and formulate a clear instruction.
2. Post a reply comment with your instruction.

**Critical**: the reply must **not** contain a `[@Name](mention://...)` link to the asking member. The daemon already triggered that member via `on_comment`; an @mention would double-fire.

Use the member's plain name (e.g., "Alice") in prose; never embed a mention link.

### 3-Strike Rule

If the same `question_id` appears three or more times across all comments:

1. Escalate to human:
   ```
   [HITL:human] question_id=<uuid> <summary of repeated ambiguity>
   ```
2. Set status:
   ```
   <<cli:issue.status>> blocked
   ```
3. No further leader-level resolution for this `question_id`.

---

## 8. Daemon-Safe Operating Rules

- Never call `AskUserQuestion`. The leader runs headless.
- `no_action` turns: call `<<cli:squad.activity>> outcome=no_action`, write the marker, exit. No comment.
- Every turn must call `<<cli:squad.activity>>` before exiting.
- All CLI interactions use `<<cli:*>>` anchor form; never literal shell commands.

---

## 9. Turn Checklist

- [ ] All delegatable tasks delegated via the correct strategy (A or B).
- [ ] No double-fire: no task dispatched via both A and B.
- [ ] Member HITL escalations answered without @mention links.
- [ ] `<<cli:squad.activity>>` called with the correct `outcome`.
- [ ] Marker written at `${MULTICA_WORKDIR}/.multica/state/<issue-id>/squad-activity.marker`.
- [ ] If `no_action`: no comment written to the issue.
