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

If `## Squad Roster` is absent or empty, see Section 7 (Empty Roster).

---

## 3. Step 0: Capacity Check (before delegation)

Before choosing Strategy A or B, check member load:

For each candidate member:
```
<<cli:issue.list>> --assignee-id <member-uuid> --status in_progress --output json
```
Count the results. If count >= 6 (default `$MULTICA_LOOP_MAX_ITERATIONS` per agent):
- That member is at capacity — skip them for Strategy A
- Try another member, or fall back to Strategy B (@mention, serial)
- If ALL members at capacity: post `[HITL:human]` asking operator to wait or add capacity

| Member load | Decision |
|-------------|---------|
| < 6 in_progress | Can accept Strategy A child issue |
| ≥ 6 in_progress | Skip for Strategy A; try Strategy B or another member |
| All members full | `[HITL:human]` — cannot delegate now |

---

## 4. Delegation Strategies

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

## 5. Concurrent Edge Cases

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

## 6. Mandatory `squad.activity` Call

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

## 7. HITL — Leader Needs Human Input

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

## 8. Receiving Member HITL Escalations

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

## 9. Planning Mode (v2.3.0 — REQ-04-01/02)

**Trigger:** `loop.json.mode == "planning"` — set automatically at session start when
the issue title contains an epic keyword (`epic`, `initiative`, `roadmap`).

**Iron rule:** planning mode is pure decomposition. NO implementation, no file edits,
no test runs — only read-only exploration and breakdown authoring.

**Flow:**

1. **discover** — `<<cli:issue.get>>` + `<<cli:issue.comment.list>>`; explore the
   codebase read-only to understand scope and seams.
2. **breakdown** — post a `[breakdown:vN]` comment (vN increments on each revision):
   ```
   [breakdown:v1]
   | # | Child task | Effort | Depends on |
   |---|-----------|--------|------------|
   | 1 | <title>   | S/M/L  | —          |
   | 2 | <title>   | M      | 1          |
   ```
   Include a short dependency-graph note. Then **exit 0** — the user reviews asynchronously.
3. **await approval** — next session is triggered by the user's comment:
   - `[proceed]` → create child issues (step 4)
   - `[revise: <feedback>]` → incorporate feedback, post `[breakdown:vN+1]`, exit 0 again
4. **create children** — one `<<cli:issue.create.child>>` per breakdown row, with
   metadata: `parent_id` (this issue), `epic_id` (this issue or its epic), `squad_id`
   (from roster), and `blocks:` links following the dependency column. Assign members
   per the capacity check (Section 3). **Record every created child ID in
   `loop.json.child_issues`** — the stop hook's progress checkpoint (REQ-04-04) reads
   this list to detect stuck members and the all-done transition.
5. After creation, post `[phase] plan→execute` summary listing the child issue IDs,
   then coordinate per the normal leader workflow.

See `docs/adr/0002-child-issue-linking.md` for the linking schema rationale.

---

## 10. Reading Member State (REQ-04-03/04)

Member state lives in issue metadata and comments — never in shared files (members
may run on other machines):

- **Per-member status**: read `member_status` from each child issue's metadata
  (`<<cli:issue.metadata.list>>`). Members write it before marking done/blocked.
- **Automatic checkpoint**: the stop hook reads `loop.json.child_issues` at every
  leader session end and compares each child's latest comment timestamp against the
  newest server timestamp seen across all children (pure server-time comparison — no
  local clock). A child with no new activity for more than
  `loop.json.squad_stuck_threshold_minutes` (default 120) triggers a
  `[checkpoint] squad-stuck` comment naming the stuck members (rate-limited to one
  per hour). When ALL children report status `done`, the hook advances
  `loop.json.phase` to `result` and posts `[phase] execute→result`.
- Schema details: `docs/adr/0003-squad-coordination.md`.

---

## 11. Daemon-Safe Operating Rules

- Never call `AskUserQuestion`. The leader runs headless.
- `no_action` turns: call `<<cli:squad.activity>> outcome=no_action`, write the marker, exit. No comment.
- Every turn must call `<<cli:squad.activity>>` before exiting.
- All CLI interactions use `<<cli:*>>` anchor form; never literal shell commands.

---

## 12. Turn Checklist

- [ ] All delegatable tasks delegated via the correct strategy (A or B).
- [ ] No double-fire: no task dispatched via both A and B.
- [ ] Member HITL escalations answered without @mention links.
- [ ] `<<cli:squad.activity>>` called with the correct `outcome`.
- [ ] Marker written at `${MULTICA_WORKDIR}/.multica/state/<issue-id>/squad-activity.marker`.
- [ ] If `no_action`: no comment written to the issue.
