# hitl-protocol — Human-in-the-Loop Protocol

This skill defines when and how an agent requests human intervention inside a Multica issue.

AskUserQuestion is **disabled**. The only sanctioned HITL path is: write a comment, set `blocked`, exit.

HITL uses `[HITL]` as its signal prefix, separate from the phase signals defined in `docs/HUMAN-GUIDE.md §2 Comment Protocol`. Phase signals (`[phase]`, `[checkpoint:N]`, `[verification]`, `[result]`, etc.) are emitted by the workflow state machine; `[HITL]` is emitted only when the agent cannot proceed without human input.

---

## When to Trigger HITL

Trigger HITL when the agent cannot proceed without human input. Minimum qualifying conditions
(at least one must be true):

1. **Decision uncertainty** — the correct action has two or more mutually exclusive options
   and the task description does not resolve the ambiguity.

2. **Missing external credential** — a required secret, token, API key, or access permission
   is absent from the environment and cannot be safely inferred.

3. **Destructive operation after 3-strike failure** — the agent has attempted the same fix
   3 or more times without forward progress, and the next step risks data loss, irreversible
   state change, or production impact.

4. **Explicit human approval required** — the task description or a prior human comment
   explicitly mandates human sign-off before a specific step.

Do NOT trigger HITL for:
- Ambiguities that can be resolved by re-reading the issue or prior comments.
- Temporary network errors or transient test flakes (retry up to 3 times first).
- Style preferences with a reasonable default.

---

## Comment Template

When triggering HITL, post exactly one comment using this template:

```
[HITL] phase=<current_phase> question_id=<uuid>

**Question:** <one clear, specific question — single sentence preferred>

**Context:**
<2-5 sentences explaining what the agent was trying to do, what it found, and why it is blocked>

**Options (if applicable):**
- Option A: <description and trade-off>
- Option B: <description and trade-off>

**To unblock:** Reply to this comment with your choice or the missing information.
The agent will resume automatically when the daemon delivers the reply.
```

Rules for the template:
- `question_id` must be a UUID v4 generated fresh for each HITL event.
- The question must be answerable in a single reply — no multi-step interrogations.
- Options are optional; include only when the choice set is finite and known.
- Do not include secrets, tokens, or credentials in the comment body.

CLI call: `<<cli:issue.comment.add>>`

After posting [HITL] comment and setting blocked, pin the question to metadata:
`<<cli:issue.metadata.set>>` --key blocked_reason --value "[HITL:question_id=<uuid>] <one-line question summary>"

This allows the next agent session to immediately read the blocking reason from metadata
without scanning comment history.

---

## Blocked Status Machine

```
agent detects block condition
        │
        ▼
generate question_id (uuid v4)
        │
        ▼
write [HITL] comment  ──► <<cli:issue.comment.add>>
        │
        ▼
set status = blocked  ──► <<cli:issue.status>>
        │
        ▼
EXIT PROCESS IMMEDIATELY
        │
        (daemon holds issue in blocked state)
        │
        ▼
human posts reply comment
        │
        ▼
daemon emits on_comment event
        │
        ▼
agent process restarted by daemon
        │
        ▼
Phase 1 discover: fetch issue + comments
        │
        ▼
On resume after blocked: first read <<cli:issue.metadata.list>> — if blocked_reason is set,
that is the prior HITL question. Find the human reply in comments before proceeding.
        │
        ▼
locate [HITL] comment by question_id, read human reply
        │
        ▼
resume from blocked phase with human input
```

---

## Timeout Responsibility

**The agent must never implement its own timeout.** The agent exits immediately after setting
`blocked`. Timeout enforcement — including re-notifying the human or escalating stale blocked
issues — is the exclusive responsibility of the **multica daemon reaper**.

Specifically prohibited:
- `sleep N && multica issue status ...` in any script.
- Polling loops that check if the issue is still blocked.
- Any cron, at-job, or deferred callback inside the agent process.

If the daemon reaper does not fire, that is a daemon configuration issue, not an agent issue.

---

## HITL State Tracking (loop.json) — v2.3.0

Every HITL event is tracked in `loop.json` so resumption is mechanical, not archaeological:

- **On posting an `[HITL]` comment**, append to `loop.json.open_hitls`:
  `{"question_id": "<uuid>", "asked_at": "<ISO8601>", "tier": "leader" | "human"}`
- **On session resume**, `hooks/session-start.sh` automatically fetches recent comments,
  matches human replies to each open `question_id` (direct `question_id=` mention or a
  thread reply to the agent's `[HITL]` comment), injects the answers into context as
  "HITL Replies Detected", and moves each answered entry to `loop.json.resolved_hitls`
  with `answer` and `answered_at` fields. The agent does NOT need to scan comments itself.
- **Never re-post** a question whose `question_id` appears in `resolved_hitls`.

**Free-form replies:** the human's reply need not match an offered Option A/B. Any reply
is captured as the answer. If the reply is too unclear to act on, raise a NEW `[HITL]`
with a fresh `question_id` that quotes the unclear reply and asks a narrower question —
do not re-ask the same `question_id`.

---

## Multi-HITL Threads

If a single task requires multiple HITL events across separate blocked cycles:
- Each event gets its own unique `question_id`, tracked in `loop.json.open_hitls`.
- On resume, answered questions arrive in context via the session-start replay
  (see "HITL State Tracking" above); `blocked_reason` metadata remains the quick
  pointer to the most recent blocking question.
- Do not re-raise a HITL question that has already been answered in a prior comment.

---

## Daemon-Safe Notes

- No synchronous wait for human input is permitted in any form.
- The blocked state is owned by the daemon; the agent's only job is to set it and exit.
- On_comment reactivation is guaranteed by the daemon; no polling by the agent is needed.
- If the agent is restarted and finds status is already `blocked` with an open HITL comment,
  it should wait for the human reply rather than posting a duplicate question.
- The daemon reaper is the sole arbiter of how long a blocked issue may remain open.

---

## HITL Timeout Auto-Degradation

When `$MULTICA_HITL_TIMEOUT_HOURS` hours pass without a human reply to a
`[HITL]` comment, the session-start hook injects a `[HITL:timeout]` context
signal. On receiving this signal, the agent MUST:

1. Choose the most conservative available option from the original HITL question
2. Post a comment using this exact format:
   ```
   [HITL:timeout] Auto-degraded after <N>h without reply.
   Chose conservative option: <brief description of chosen option>
   If incorrect, reply to this comment to override.
   ```
3. Continue execution with that choice
4. Do NOT set `blocked` — the timeout resolution allows forward progress

If no clearly conservative option exists, post the comment and set `blocked`
with reason `hitl-timeout-no-safe-default`.

Default timeout: `$MULTICA_HITL_TIMEOUT_HOURS` hours (configurable via
`capabilities/claude-code.json` thresholds.hitl_timeout_hours).

**48h hard timeout (REQ-06-01):** if a `[HITL:human]` question remains unanswered
past `$MULTICA_HITL_HUMAN_TIMEOUT_HOURS` (default 48), session-start injects a
hard-timeout signal instead of the auto-degradation alert. The agent must post a
`[loop-stuck]` timeout notice, keep (or set) status `blocked`, and exit — no
conservative-option guessing at this stage. This guarantees a stalled issue leaves
a visible trace in the timeline instead of waiting silently forever.

---

## Squad HITL Routing

When escalating from a squad member, use two-tier routing:

**Tier 1 — escalate to squad leader first:**
```
[HITL:leader] ← This is routed to the squad leader, not to you.
If leader cannot resolve, you will receive a separate [HITL:human] notification.

phase=<current_phase> question_id=<uuid>

**Question:** <one clear, specific question>

**Context:** <2-5 sentences>
```

**Tier 2 — escalate to human (after 3 leader bounces, or leader unavailable):**
Use the standard `[HITL]` template from the Comment Template section above.

The `[HITL:leader]` prefix tells reviewers the comment is directed at the squad
leader and does not require their action yet. Reviewers will receive a separate
`[HITL:human]` notification if the leader cannot resolve it.
