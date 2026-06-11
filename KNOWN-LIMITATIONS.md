# Known Limitations

## Node.js Requirement for npx Installer

`npx github:yangliang2/multica-agent-plugin` requires **Node.js >= 16**. On systems with an older
Node.js version, use the fallback:

```bash
git clone https://github.com/yangliang2/multica-agent-plugin.git
cd multica-agent-plugin
bash install.sh
```

## MVP Scope: Claude Code Only

This release targets the Claude Code harness exclusively. The Stop hook
(`hooks/stop.sh`), PreToolUse hook (`hooks/pre-tool.sh`), and SessionStart
hook (`hooks/session-start.sh`) use Claude Code-specific hook contracts and
exit-code semantics that are not portable to other harnesses without adaptation.

Skills include degradation notices for non-Claude Code environments. When
running outside Claude Code, persistence-loop and parallel-exec fall back to
sequential, unguarded execution.

## multica CLI Version Requirement

The `hooks/stop.sh` and `hooks/session-start.sh` scripts call `multica` CLI
commands directly. They require **multica >= 0.4.0** for the following
subcommands:

- `multica issue comment add`
- `multica issue comment list`
- `multica issue status set`

Using an older multica version will cause hook commands to fail silently
(exit 0 on error, by design) but may produce incorrect loop state or missing
checkpoint comments.

## Destructive Guard Is a Convenience Check, Not a Security Control

`hooks/pre-tool.sh` checks Bash tool calls against `tools/safe-exec.deny.list`
(ERE patterns, `grep -qiE`, matched against both the raw and a
whitespace-normalized form of the command). Since v2.3.0 it is a hybrid:
`tools/safe-exec.allow.list` can rescue a command from a **non-critical** deny
match (e.g. a project-specific `rm -rf /tmp/build/`), while patterns listed in
`tools/safe-exec.critical.list` (reverse shells, `rm -rf /`, `curl|bash`,
disk overwrite, encoded payloads) can **never** be rescued. All decisions —
ALLOW, DENY, ALLOW_OVERRIDE, BYPASS_ATTEMPT — are logged to
`.multica/safe-exec.log`. A denied command that also carries an obfuscation
construct (`$(...)`, backticks, heredocs, `eval`) is tagged `[BYPASS_ATTEMPT]`
and the issue is set `blocked` for human review.

This remains a **convenience check to catch accidental misuse**, not a
security boundary. It **cannot** prevent a determined agent or user from
bypassing it via:

- Novel encodings or multi-step staging the patterns don't cover
- Shell wrappers that assemble the command at runtime (`bash -c "$var"`)
- Commands simply not in the deny list (`git clean -fdx`, `shred`)

The `multica safe-exec` subcommand does not exist in the multica CLI.

**Do not rely on this check to enforce security policy.** For production
multi-tenant deployments, use OS-level sandboxing (containers, namespaces) or
a proper allowlist at the executor level. To extend the convenience patterns,
edit `tools/safe-exec.deny.list` (and mirror high-severity additions into
`tools/safe-exec.critical.list`).

## Post-MVP Harness Extension Paths

This plugin supports **Claude Code only**. There is no adapter architecture in
the repository, and no other harness is implemented. The directions below are
**aspirational, not committed roadmap** — there is no schedule and no work in
progress. They record which harnesses would be candidates *if* multi-harness
support is ever pursued:

1. **Codex** — CLI-native, similar hook surface
2. **Cursor** — IDE-embedded; requires different context injection mechanism
3. **Gemini Code Assist** — Google Cloud context; auth and workspace model differ
4. **Kimi** — International deployment; i18n and locale handling needed

The `> Degradation notice:` blocks in each advanced skill document the expected
fallback behavior when a skill is run outside Claude Code.

## No Automatic CLI Reference Update

`docs/cli-reference.lock` stores the sha256 of `docs/cli-reference.md` at
release time. If you modify `docs/cli-reference.md` manually, re-run
`tools/refresh-cli-reference.sh` to regenerate the lock file. The smoke script
(`tests/smoke/run-claude.sh`) will fail Scenario 4 if the lock is stale.

### ⚠️ Learnings Sync Requires Git Repository

The `stop.sh` hook git-commits `.multica/learnings.jsonl` on task completion
to enable cross-machine knowledge propagation. **This requires the project
workspace to be a git repository.**

Projects without a git repository will NOT sync learnings across machines.
Each machine will maintain a local-only `.multica/learnings.jsonl` that is
never shared. This is a known limitation; a server-side knowledge API
(`multica knowledge set/get`) is planned for a future release.

**Workaround:** Manually sync on the source machine:
```bash
git add .multica/learnings.jsonl
git commit -m "chore(knowledge): manual learnings sync"
git push
```
Then `git pull` on the target machine.

## Multi-Machine Knowledge Sync Requires Git

The v0.4.0 feature that git-commits `.multica/learnings.jsonl` on the DONE path
(`hooks/stop.sh`) requires the project working directory to be a git repository.
In non-git directories, the commit step is silently skipped and learnings remain
local only.

## curate-memory.sh and Staleness Detection Require python3

`tools/curate-memory.sh` (learning dedup and confidence decay) and the
stat-based staleness detection in `hooks/session-start.sh` both require
`python3` to be available on `PATH`. On systems without python3, curate-memory
will not run and staleness detection will be skipped silently.
