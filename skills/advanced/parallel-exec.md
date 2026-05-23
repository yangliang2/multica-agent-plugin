# Parallel Execution

Two-stage review workflow for implementation tasks. Each task gets a fresh subagent for
implementation, followed by spec compliance review, then code quality review — in that order.

Distilled from Superpowers subagent-driven-development.

> **Degradation notice:** When parallel execution is not natively available in the current
> harness, execute tasks sequentially in the current session. The two-stage review
> sequence and model routing remain the same; only the concurrency changes.

---

## When to Use

- You have a decomposed implementation plan with 2+ independent tasks
- Tasks can be assigned to fresh subagents with self-contained context
- You want high-quality output with structured review gates (not just "do your best")
- Tasks should NOT inherit the current session's accumulated context

---

## Core Principle

Fresh subagent per task + two-stage review (spec compliance first, then code quality) = high quality, fast iteration.

Subagents receive only what they need. Never let them inherit the orchestrator's full session
context. Precisely craft their instructions and the files they need access to.

---

## Model Routing

Use the least powerful model that can handle each role.

| Task type | Model | Signal |
|-----------|-------|--------|
| Mechanical implementation (1–2 files, complete spec) | haiku | Isolated function, clear spec, no judgment needed |
| Integration / judgment (multi-file, pattern matching, debugging) | sonnet | Touches 3+ files, requires understanding of system context |
| Architecture, design, review | opus | Cross-cutting concerns, security, non-obvious tradeoffs |

**Escalation rule:** When a haiku task produces an implementation that fails the spec
review more than once, escalate to sonnet for the retry. When a sonnet task fails
twice, escalate to opus.

---

## Two-Stage Review Flow

The review sequence is fixed and must not be reordered:

```
1. Dispatch implementer subagent
        ↓
2. Dispatch spec compliance reviewer  ← first
        ↓ (reject → implementer fixes, re-review)
3. Dispatch code quality reviewer     ← second
        ↓ (reject → implementer fixes, re-review)
4. Mark task complete
```

**Stage 1 — Spec Compliance Review**

The spec reviewer answers one question: does the implementation satisfy every
requirement in the task specification?

Reviewer checklist:
- All specified inputs produce specified outputs
- All required files exist at specified paths
- All required interfaces are implemented with correct signatures
- No specified behavior is missing or silently skipped

If ANY item fails: return the failing items to the implementer. Do not proceed to
Stage 2 until Stage 1 passes.

**Stage 2 — Code Quality Review**

The quality reviewer answers one question: is the implementation safe to ship?

Reviewer checklist:
- No obvious correctness bugs (off-by-one, null deref, wrong logic)
- No hardcoded secrets, credentials, or environment-specific paths
- Error paths are handled (no silent swallows of meaningful failures)
- No deslop violations: no unnecessary comments, no over-defensive guards,
  no redundant type annotations (see `skills/advanced/persistence-loop.md` deslop section)
- Test coverage exists for the new behavior (or a clear reason why it is impractical)

If ANY item fails: return the failing items to the implementer with specific line
references. Do not mark the task complete.

---

## Per-Task Execution Protocol

For each task in the plan:

1. **Prepare subagent context.** Extract only what the subagent needs: the task spec,
   relevant file excerpts, and any constraints from the issue. Do not pass the full
   session history.

2. **Dispatch implementer.** Provide: task spec, file paths to create/modify, test
   command to run, any codebase patterns the implementation must follow.

3. **Implementer self-verifies.** Before returning, the implementer must run the
   relevant tests and confirm they pass. It must not return "I think it works."

4. **Dispatch spec compliance reviewer** (Stage 1). Provide: original task spec,
   diff or list of changed files, test output from the implementer.

5. **If spec review fails:** return failing items to implementer, loop back to step 2.
   Use escalation rule if failing repeatedly.

6. **Dispatch code quality reviewer** (Stage 2). Provide: same diff/changed files,
   spec review approval.

7. **If quality review fails:** return failing items to implementer, loop back to step 2.

8. **Mark task complete** in loop state (set story `passes: true`).

---

## Final Review

After all individual tasks are complete:

Dispatch a final code reviewer subagent (opus) to assess the full implementation as
a whole. This reviewer checks:
- No unintended interactions between tasks
- Consistent style and conventions across all changed files
- No cross-task regressions

If the final reviewer raises issues, create new stories in `loop.json` and continue
via the persistence loop.

---

## Continuous Execution

Do not pause between tasks to ask for confirmation. Execute all tasks from the plan
without stopping. The only valid stop conditions are:

- BLOCKED status that cannot be resolved (missing credential, ambiguous spec)
- All tasks complete and final review passed
- `max_iterations` reached (see `skills/advanced/persistence-loop.md`)

Progress summaries between tasks waste time. The issue comments are the record.
