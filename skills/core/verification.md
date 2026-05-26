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
- `exit_code` must be 0 for a passing claim
- The stop hook verifies evidence file existence — missing file causes DONE rejection
- If the story's acceptance criterion is "no tests exist", write `exit_code: 0` with `summary: no-tests-required — <rationale>`

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
