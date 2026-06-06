# Verification Before Completion

## Iron Law

```
NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE
```

If you have not run the verification command in this turn, you cannot claim it passes.

## Gate Function

```
BEFORE claiming any status or expressing satisfaction:

1. IDENTIFY — What command proves this claim?
2. RUN — Execute the FULL command (fresh, complete, no cached results)
3. READ — Full output, check exit code, count failures
4. VERIFY — Does output confirm the claim?
   - If NO: State actual status with evidence
   - If YES: Write evidence file (see Evidence File below), then state claim WITH evidence
5. ONLY THEN — Make the claim

Skip any step = assertion without evidence
```

## Evidence File (required before marking any story passes=true)

For each story, write a machine-readable evidence file before setting `passes: true`:

**Path:** `.multica/state/{issue_id}/evidence/{story_id}.txt`

**Format:**
```
command: <full command that was run>
exit_code: <integer>
output_hash: <sha256 of full output, first 8 hex chars>
summary: <1-3 lines of key output — test counts, build result, key assertion>
```

**Rules:**
- File must exist and be non-empty before `passes: true` is written to `loop.json`
- A `command:` line is **required** — it records the exact command that was run
- An `exit_code:` line is **required** and must parse as an integer
- `exit_code` must be `0` for a passing claim — the stop hook cross-checks this:
  if a story is marked `passes: true` but its evidence shows a non-zero
  `exit_code`, DONE is rejected
- A prose `summary:` alone is **not** sufficient — it is self-assessment, not
  machine-checkable proof. The hook ignores it for the pass/fail decision.
- The stop hook enforces all of the above — a missing/empty file, missing
  `command:`, missing/unparseable `exit_code:`, or non-zero `exit_code:` all
  cause DONE rejection
- If the story's acceptance criterion is "no tests exist", still write a real
  command (e.g. `command: ls tests/ || true`) with `exit_code: 0` and a
  `summary: no-tests-required — <rationale>`

### What this gate can and cannot enforce

The evidence gate is a **structural** check, not a semantic one. Be honest
about its limits:

- It **can** verify that a command was named and that its recorded exit code is
  0. It rejects the most common dishonest pattern: claiming `passes: true` while
  the evidence shows a failure or shows no command was run at all.
- It **cannot** verify that the recorded `command:` is actually relevant to the
  story, that the `exit_code:` was transcribed faithfully from a real run, or
  that the command's output truly demonstrates the acceptance criterion. A
  determined agent can still write a passing-looking evidence file for a command
  that proves nothing.
- The `output_hash:` field exists so that a reviewer (or a future external
  checker) can correlate the claimed output against an independent capture. It
  is not currently re-derived by the hook.

Treat the gate as a floor, not a guarantee. The Iron Law still binds you: run
the real command, read the real output, and record it faithfully.

## Claim-to-Proof Table

| Claim | 需要 | 不够 |
|-------|------|------|
| Tests pass | 测试命令输出 0 failures | 上次运行、"应该能过" |
| Build succeeds | build 命令 exit 0 | linter 通过 |
| Bug fixed | 复现原症状的测试通过 | 代码改了 |
| Feature complete | 逐条对照需求清单 | 测试通过 |
| Agent completed | VCS diff 确认变更存在 | Agent 自报 success |

## Rationalization Prevention

| 借口 | 正确回应 |
|------|---------|
| "Should work now" | RUN the verification |
| "I'm confident" | Confidence ≠ evidence |
| "Agent said success" | Verify independently |
| "Just this once" | No exceptions |
| "Partial check is enough" | Partial proves nothing |
| "Different words so rule doesn't apply" | Spirit over letter |

## Evidence Write-Back Format

After verification passes, write result to the multica issue comment:

```
[verification] exit_code=0 command="<cmd>" output_hash=<sha256前8位>
<关键输出摘录，≤10行>
```

If exit code is non-zero, write actual state with full evidence — do not suppress.

## Red Flags — STOP

Any of the following appearing in your output → STOP and run verification first:

- Using "should", "probably", "seems to"
- Expressing satisfaction before verification ("Great!", "Done!", "Perfect!")
- Relying on a previous run from an earlier turn
- Trusting agent success reports without independent check
- Partial verification followed by inference about the whole
- ANY wording implying success without having executed verification

## Daemon-Safe Notes

All verification steps MUST be command executions producing machine-readable output.

- Do NOT use AskUserQuestion or any interactive prompt
- Do NOT wait for human confirmation
- Do NOT skip verification because "it's obvious"
- If a command is unavailable, document the gap and use the nearest available equivalent
- Verification is self-contained: read exit codes, grep output, count lines — no human in the loop
