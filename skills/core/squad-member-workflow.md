# squad-member-workflow — Squad Member Execution Protocol

A squad member is triggered by a leader's @mention and executes a delegated subtask. A member implements; the leader plans.

AskUserQuestion is **disabled**. All blocking questions go through the two-tier HITL protocol below.

---

## Phase 0: Context Extraction (on @mention trigger)

**Entry**: Daemon delivers `on_comment` event containing an @mention of this agent.

**Actions**:
1. Fetch the triggering thread: `<<cli:issue.comment.list.thread>>`. Locate the leader's delegation comment.
2. Extract from the delegation comment:
   - **Task description** — what to implement
   - **Constraints** — scope limits, forbidden approaches, required patterns
   - **Dependencies** — prior work or artifacts this task depends on
3. Fetch issue context: `<<cli:issue.get>>` — read `title`, `description`, `status`, `assignee`, `metadata`.
4. If the delegation is ambiguous or a required dependency is incomplete, escalate via Tier 1 HITL before proceeding.

**Exit**: Task, constraints, and dependencies are unambiguously understood. → Phase 1.

---

## 5-Phase Workflow

Execute the standard multica 5-phase workflow (see `skills/core/multica-workflow.md`) with the member rules below layered on top.

### Phase 1: discover
- `<<cli:issue.get>>` — issue background
- `<<cli:issue.comment.list>>` — prior agent commentary, human replies, dependency outputs
- Identify: what exists, what is missing, what the leader expects as output

### Phase 2: plan
- Draft a concise plan scoped to the delegated subtask only
- Post as comment: `<<cli:issue.comment.add>>`
- Set status `in_progress`: `<<cli:issue.status>>`

### Phase 3: execute
- Implement each step in the local workspace
- Post interim progress for steps taking >60s: `<<cli:issue.comment.add>>`
- On ambiguity or missing credential: stop and apply Tier 1 HITL

### Phase 4: verify

**Verification Iron Law**: NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE.

1. Identify the verification command that proves the claim.
2. Run it fresh this turn — no cached results.
3. Read full output; check exit code; count failures.
4. Post verification result: `<<cli:issue.comment.add>>`

Format:
```
[verification] exit_code=0 command="<cmd>" output_hash=<sha256 first 8 chars>
<key output excerpt, ≤10 lines>
```

Do not proceed to Phase 5 until verification evidence is written to a comment.

### Phase 5: report
See "Completion Reply Rules" below.

---

## Two-Tier HITL Protocol

### Tier 1 — Escalate to Leader (default path)

Use when blocked by ambiguity, missing context, or a conflict the member cannot resolve alone.

**Pre-check**: confirm a leader is present in the issue roster. If no leader, skip to Tier 2.

**Steps**:
1. Generate a stable `question_id`: `<issue_id>-<short-hash-of-question-summary>`. Reuse the same ID on every bounce for the same question.
2. Store `question_id` and bounce count: `<<cli:issue.metadata.set>>`
3. Post the HITL comment (must include the leader's mention link from the roster):

```
[HITL:leader] question_id=<question_id>

[@LeaderName](mention://agent/<leader-uuid>)

**Question:** <one clear, specific question>

**Context:**
<2-5 sentences: what the member was doing, what was found, why it is blocked>

**Options (if applicable):**
- Option A: <description and trade-off>
- Option B: <description and trade-off>

**To unblock:** Reply to this comment with your choice or the missing information.
```

`<<cli:issue.comment.add>>`

4. Set status `blocked`: `<<cli:issue.status>>`
5. EXIT PROCESS IMMEDIATELY.

### Tier 2 — Escalate to Human

**Conditions (any one sufficient)**:
- Same `question_id` bounced 3 times without resolution (3-strike rule)
- Architectural decision beyond the leader's authority
- Requires a credential, secret, or external system access only a human can provide
- Task or prior human comment explicitly requires human sign-off
- No leader is present in the roster

**Steps**:
1. Post the HITL comment (no agent mention — human is the audience):

```
[HITL:human] question_id=<question_id>

**Question:** <one clear, specific question>

**Context:**
<2-5 sentences explaining the block>
Leader was consulted but could not resolve: <brief summary, or "no leader in roster">

**Options (if applicable):**
- Option A: <description and trade-off>
- Option B: <description and trade-off>

**To unblock:** Reply to this comment with your choice or the missing information.
```

`<<cli:issue.comment.add>>`

2. Set status `blocked`: `<<cli:issue.status>>`
3. EXIT PROCESS IMMEDIATELY.

---

## 3-Strike Rule (per question_id)

The member maintains an independent bounce counter per `question_id` in issue metadata, separate from any leader counter.

**Tracking**:
- Key: `hitl_bounces_<question_id>`
- Value: integer count of unresolved raises
- Storage: `<<cli:issue.metadata.set>>`

**On each new blocked/resume cycle for the same `question_id`**:
1. Read current count: `<<cli:issue.metadata.set>>` (read `hitl_bounces_<question_id>`)
2. Increment and write back.
3. If count reaches 3: skip `[HITL:leader]` — post `[HITL:human]` directly.

**question_id stability**: generate the `question_id` once on first raise (`<issue_id>-<hash-of-question-summary>`). Reuse the exact same ID on every subsequent bounce. Never regenerate.

---

## Completion Reply Rules

After Phase 4 verification passes:

1. Write a final summary comment: what was done, artifacts produced, caveats.
   `<<cli:issue.comment.add>>`

   **Wording constraint**:
   - Plain text such as "Task completed." or "Subtask complete. Output: <artifact>."
   - **Do NOT include any `[@Name](mention://...)` link in this comment.** Mentioning the leader (even as thanks) re-triggers the leader.
   - No greeting or sign-off containing a mention link.

2. Set final status:
   - `<<cli:issue.status>> done` — task self-contained and fully resolved
   - `<<cli:issue.status>> in_review` — task produces an artifact requiring leader review

---

## Daemon-Safe Notes

- Do not use AskUserQuestion in any form.
- Do not @mention the leader in a completion comment — re-triggers the leader.
- Do not implement sleep, polling loops, or any blocking wait for replies.
- Do not hold locks or open connections across a `blocked` exit.
- The daemon reaper owns all timeout enforcement; do not implement timeouts here.
- On restart after `blocked`, re-read comments to find the reply before proceeding.
- If restarted while status is already `blocked` with an open HITL comment, wait for the reply rather than posting a duplicate (check comment history first).
- The Verification Iron Law applies without exception: never claim completion without running and writing fresh verification evidence in the current turn.
