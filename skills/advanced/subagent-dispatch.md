# Subagent Dispatch

## Iron Law

EVERY subagent prompt must contain complete task context. Never reference prior context — subagent has a fresh window.

## Model Routing

Use $MULTICA_MODEL_FAST, $MULTICA_MODEL_STD, $MULTICA_MODEL_DEEP (injected by session-start hook).
Defaults if env vars absent: haiku / sonnet / opus.

| Task type | Model | When to use |
|-----------|-------|-------------|
| Mechanical implementation (1-2 files, clear spec) | $MULTICA_MODEL_FAST | Isolated function, clear acceptance criteria |
| Standard implementation (multi-file, judgment) | $MULTICA_MODEL_STD | Integration work, pattern matching, debugging |
| Architecture / review / security | $MULTICA_MODEL_DEEP | Design decisions, code review, security analysis |

## Dispatch Pattern

Task(
  subagent_type="oh-my-claudecode:executor",
  model="<$MULTICA_MODEL_FAST|STD|DEEP>",
  prompt="<complete context including: task description, relevant code, acceptance criteria, output format>"
)

Specialist subagent types:
- executor — implementation
- code-reviewer — quality review
- debugger — root cause analysis

## Fresh Context Principle

Each subagent prompt must include:
1. Task description (full context)
2. Relevant code snippets
3. Acceptance criteria (specific, testable)
4. Output format (file path or multica comment)

## Output Contract

Subagents must write results to file or multica comment, not rely on return value.
Preferred path: `.multica/state/<issue_id>/subagent-<task_id>.md`

## Daemon-Safe Notes

- No AskUserQuestion
- No interactive prompts in subagent
- Subagent uses same HITL protocol as main agent if blocked
