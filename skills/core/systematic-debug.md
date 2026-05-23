# Systematic Debugging

## Iron Law

```
NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST
```

If you have not completed Phase 1, you cannot propose fixes.

## The Four Phases

You MUST complete each phase before proceeding to the next.

### Phase 1 — Root Cause Investigation

**BEFORE attempting ANY fix:**

1. **Read Error Messages Completely**
   - Do not skip past errors or warnings
   - Read stack traces in full
   - Record line numbers, file paths, error codes exactly as shown

2. **Reproduce Consistently**
   - Can you trigger the failure reliably?
   - What are the exact steps?
   - Not reproducible → collect more data, do not guess

3. **Check Recent Changes**
   - Run `git diff` and review recent commits
   - Identify new dependencies, config changes, environmental differences
   - What changed that could cause this?

4. **Instrument Each Boundary in Multi-Component Systems**

   For systems with multiple components (CI → build → signing, API → service → database):

   ```
   For EACH component boundary:
     - Log what data enters the component
     - Log what data exits the component
     - Verify environment/config propagation
     - Check state at each layer

   Run once to gather evidence showing WHERE it breaks
   THEN analyze evidence to identify the failing component
   THEN investigate that specific component
   ```

   Record each boundary's data in a multica issue comment before moving to Phase 2.

5. **Trace Data Flow for Deep Call Stacks**
   - Where does the bad value originate?
   - What called this with the bad value?
   - Keep tracing upward until the source is found
   - Fix at the source, not at the symptom

### Phase 2 — Pattern Analysis

**Find the pattern before fixing:**

1. **Find Working Examples**
   - Locate similar working code in the same codebase
   - What works that resembles what is broken?

2. **Read Reference Implementation Completely**
   - Do not skim — read every line
   - Understand the pattern fully before applying it

3. **List Every Difference**
   - What differs between the working and broken implementations?
   - List each difference, however small
   - Do not assume "that cannot matter"

4. **Understand Dependencies**
   - What other components, settings, config, or environment does this need?
   - What assumptions does it make?

### Phase 3 — Hypothesis and Testing

**Scientific method:**

1. **Form a Single Hypothesis**
   - State clearly: "I think X is the root cause because Y"
   - Write it down explicitly before testing
   - Be specific, not vague

2. **Test with Minimum Change**
   - Make the SMALLEST possible change to test the hypothesis
   - One variable at a time
   - Do not bundle multiple fixes

3. **Verify Before Continuing**
   - Fix worked → proceed to Phase 4
   - Fix did not work → form a NEW hypothesis, do not add more fixes on top

4. **When You Do Not Know**
   - State "I do not understand X" explicitly
   - Do not proceed with a fix that relies on an assumption you cannot verify
   - Gather more data

### Phase 4 — Implementation

**Fix the root cause, not the symptom:**

1. **Write a Failing Test First**
   - Simplest possible reproduction
   - Record the test command and expected output in a multica issue comment before running it
   - The test MUST fail before the fix and pass after

2. **Implement a Single Fix**
   - Address the root cause identified in Phase 1
   - One change at a time
   - No "while I am here" improvements
   - No bundled refactoring

3. **Verify Fix via verification.md Gate Function**
   - Run the test; confirm it passes
   - Run the full test suite; confirm no regressions
   - Write evidence to multica issue comment in the format specified in verification.md

4. **If Fix Does Not Work — Count First**
   - < 3 attempts: return to Phase 1, re-investigate with new information
   - ≥ 3 attempts: STOP — see rule below

## ≥3 Fixes Failed — Mandatory HITL Escalation

When three or more fix attempts have failed, the problem is likely architectural, not a local bug. Do not attempt a fourth fix.

Write the following comment to the multica issue:

```
[HITL] question_id=<uuid> 已尝试 3 次修复均失败，可能是架构问题。
尝试记录：1) <fix1> 2) <fix2> 3) <fix3>
建议：<architectural question>
```

Then run:

```
multica issue status <id> blocked
```

Then exit. Do not attempt another fix until the architectural question is answered.

**Pattern indicating architectural problem:**
- Each fix reveals new shared state, coupling, or a problem in a different place
- Fixes require large-scale refactoring to implement correctly
- Each fix creates new symptoms elsewhere

## Red Flags — STOP and Return to Phase 1

If any of the following appear in your reasoning:

- "Quick fix for now, investigate later"
- "Just try X and see if it works"
- "Add multiple changes, run tests"
- "It's probably X, let me fix that"
- "I don't fully understand but this might work"
- "Here are the main problems:" (listing fixes before completing investigation)
- "One more fix attempt" (when already tried 2 times)
- Each fix is revealing a new problem in a different place

**ALL of these mean: STOP. Return to Phase 1.**

**If 3+ fixes failed:** Write HITL comment, set issue to blocked, exit.

## Daemon-Safe Notes

All debugging steps MUST be automated command executions.

- Do NOT use AskUserQuestion or any interactive prompt
- Do NOT wait for human confirmation before running diagnostic commands
- Do NOT skip Phase 1 because the fix "looks obvious"
- Record all evidence (error output, boundary logs, test results) in multica issue comments — not in agent memory
- If a diagnostic command is unavailable, document the gap and use the nearest available equivalent
- The ≥3 fix rule is enforced by writing a HITL comment and setting `blocked` status — no human input is needed to trigger the escalation
