AGENTS.md is the source of truth; this file adds Claude Code-specific affordances only.

---

## Advanced Skills Index

| Skill | Purpose |
|-------|---------|
| `skills/advanced/persistence-loop.md` | PRD-driven persistence loop with session state, completion signal protocol, and deslop pass |
| `skills/advanced/parallel-exec.md` | Two-stage review (spec compliance → code quality) with model routing |
| `skills/advanced/subagent-dispatch.md` | Subagent dispatch with model routing and fresh context principle |

---

## Hooks Registration

Hooks are installed to `~/.claude/hooks/multica/` by the installer and registered
in `~/.claude/settings.json`. Run the installer to set up:

```bash
npx multica-agent-plugin
```

The installer registers these hooks:

| Event | Script |
|-------|--------|
| Stop | `~/.claude/hooks/multica/stop.sh` |
| PreToolUse | `~/.claude/hooks/multica/pre-tool.sh` |
| SessionStart | `~/.claude/hooks/multica/session-start.sh` |

> Hooks are installed to a stable location (`~/.claude/hooks/multica/`) that does
> not change if you move or update the plugin directory.

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

Learnings are stored as append-only JSONL. The storage path depends on scope:

| Scope | Storage path | Sharing |
|-------|-------------|---------|
| `issue` (default) | `$MULTICA_WORKDIR/.multica/learnings.jsonl` | Same (agent, issue) sessions only |
| `repo` | `{checkout_dir}/.multica/learnings.jsonl` | All sessions on that repo (via git) |
| `workspace` | multica workspace context field | All agents in the workspace |

Each line is one learning entry:

```jsonl
{"ts":"<ISO8601>","scope":"<workspace|repo|issue>","repo":"<url-or-empty>","skill":"<skill-id>","type":"<pattern|fix|constraint|observation>","key":"<short-unique-key>","insight":"<text>","confidence":<1-10>,"source":"<issue-id>","branch":"<git-branch>","commit":"<sha-or-empty>","files":["<path>"]}
```

Fields:
- `ts` — ISO 8601 timestamp when the learning was recorded
- `scope` — one of: `workspace`, `repo`, `issue` (default: `issue` if omitted — backward compatible)
- `repo` — repository URL; required when `scope=repo`, empty otherwise
- `skill` — originating skill id (e.g. `persistence-loop`, `parallel-exec`)
- `type` — one of: `pattern`, `fix`, `constraint`, `observation`
- `key` — short unique identifier; duplicate keys resolve to latest entry at read time
- `insight` — the learning text, plain language
- `confidence` — integer 1–10; session-start loads entries with `confidence >= 7`
- `source` — issue id or session id that produced this learning
- `branch` — git branch at time of recording
- `commit` — git commit sha, or empty string if not applicable
- `files` — array of relative file paths touched by this learning (no absolute paths, no `..`)

**Scope selection guide:**
- `workspace` — cross-cutting business rules, API constraints, team conventions
- `repo` — repo-specific test flags, build quirks, code patterns
- `issue` — investigation findings, dead ends, session-specific context

At session start, `hooks/session-start.sh` injects in order:
1. L1 workspace learnings (parsed from workspace context field)
2. L3 issue learnings (`$MULTICA_WORKDIR/.multica/learnings.jsonl`)

L2 repo learnings are read by the agent during Phase 1 discover, after `multica repo checkout`.
