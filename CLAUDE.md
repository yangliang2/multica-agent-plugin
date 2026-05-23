AGENTS.md is the source of truth; this file adds Claude Code-specific affordances only.

---

## Advanced Skills Index

| Skill | Purpose |
|-------|---------|
| `skills/advanced/persistence-loop.md` | PRD-driven persistence loop with session state, completion signal protocol, and deslop pass |
| `skills/advanced/parallel-exec.md` | Two-stage review (spec compliance → code quality) with model routing |

---

## Hooks Registration

Hooks are registered by merging `hooks/hooks.json` into your project's `.claude/settings.json`:

```json
{
  "hooks": {
    "Stop": [{"type": "command", "command": "${MULTICA_PLUGIN_ROOT}/hooks/stop.sh"}],
    "PreToolUse": [{"type": "command", "command": "${MULTICA_PLUGIN_ROOT}/hooks/pre-tool.sh"}],
    "SessionStart": [{"type": "command", "command": "${MULTICA_PLUGIN_ROOT}/hooks/session-start.sh", "matcher": "startup|clear|compact"}]
  }
}
```

Set `MULTICA_PLUGIN_ROOT` to the absolute path of this plugin directory before starting Claude Code.

---

## Capability Authority

`capabilities/claude-code.json` is the authoritative capability map for this harness.
Skills MUST check capability presence before using hook-dependent features.

---

## Notepad Three-Section Spec

`.multica/notepad.md` uses three named sections:

```
## Priority Context
```
≤500 characters. Loaded at every session start by `hooks/session-start.sh`.
Write the single most important context for the next session here.
Auto-replaced (not appended) when you update it.

```
## Working Memory
```
Timestamped entries. Auto-pruned after 7 days.
Use for in-progress observations, iteration learnings, partial findings.
Format: `[YYYY-MM-DDTHH:MM:SSZ] <content>`

```
## Manual Notes
```
Permanent. Never auto-pruned.
Use for decisions, architecture rationale, recurring patterns worth remembering forever.

---

## learnings.jsonl Format

Learnings are stored at `.multica/learnings.jsonl` (append-only JSONL).
Each line is one learning entry:

```jsonl
{"ts":"<ISO8601>","skill":"<skill-id>","type":"<pattern|fix|constraint|observation>","key":"<short-unique-key>","insight":"<text>","confidence":<1-10>,"source":"<issue-id or session-id>","branch":"<git-branch>","commit":"<sha-or-empty>","files":["<path>"]}
```

Fields:
- `ts` — ISO 8601 timestamp when the learning was recorded
- `skill` — originating skill id (e.g. `persistence-loop`, `parallel-exec`)
- `type` — one of: `pattern`, `fix`, `constraint`, `observation`
- `key` — short unique identifier; duplicate keys resolve to latest entry at read time
- `insight` — the learning text, plain language
- `confidence` — integer 1–10; session-start loads entries with `confidence >= 7`
- `source` — issue id or session id that produced this learning
- `branch` — git branch at time of recording
- `commit` — git commit sha, or empty string if not applicable
- `files` — array of file paths touched by this learning (may be empty)

At session start, `hooks/session-start.sh` reads the 10 most recent entries
plus all entries with `confidence >= 7` and injects them as advisory context.
