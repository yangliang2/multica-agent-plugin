# hitl-protocol — Human-in-the-Loop Protocol

This skill defines when and how an agent requests human intervention inside a Multica issue.

AskUserQuestion is **disabled**. The only sanctioned HITL path is: write a comment, set `blocked`, exit.

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
[HITL] question_id=<uuid>

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

## Multi-HITL Threads

If a single task requires multiple HITL events across separate blocked cycles:
- Each event gets its own unique `question_id`.
- On resume, the agent searches comments for the most recent `[HITL]` comment matching its
  current `question_id` context (stored in metadata via `<<cli:issue.metadata.set>>`).
- Do not re-raise a HITL question that has already been answered in a prior comment.

---

## Daemon-Safe Notes

- No synchronous wait for human input is permitted in any form.
- The blocked state is owned by the daemon; the agent's only job is to set it and exit.
- On_comment reactivation is guaranteed by the daemon; no polling by the agent is needed.
- If the agent is restarted and finds status is already `blocked` with an open HITL comment,
  it should wait for the human reply rather than posting a duplicate question.
- The daemon reaper is the sole arbiter of how long a blocked issue may remain open.
