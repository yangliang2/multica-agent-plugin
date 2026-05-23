# Known Limitations

## MVP Scope: Claude Code Only

This release targets the Claude Code harness exclusively. The Stop hook
(`hooks/stop.sh`), PreToolUse hook (`hooks/pre-tool.sh`), and SessionStart
hook (`hooks/session-start.sh`) use Claude Code-specific hook contracts and
exit-code semantics that are not portable to other harnesses without adaptation.

Skills include degradation notices for non-Claude Code environments. When
running outside Claude Code, persistence-loop and parallel-exec fall back to
sequential, unguarded execution.

## multica CLI Version Requirement

The `hooks/stop.sh` and `hooks/pre-tool.sh` scripts call `multica` CLI commands
directly. They require **multica >= 0.4.0** for the following subcommands:

- `multica issue comment add`
- `multica issue comment list`
- `multica issue status set`
- `multica safe-exec`

Using an older multica version will cause hook commands to fail silently
(exit 0 on error, by design) but may produce incorrect loop state or missing
checkpoint comments.

## Post-MVP Harness Extension Paths

Other harnesses are on the roadmap. See `.omc/plans/multica-agent-plugin.md`
rev2 for the planned adapter architecture. Priority order:

1. **Codex** — CLI-native, similar hook surface; adapter planned for v0.2.0
2. **Cursor** — IDE-embedded; requires different context injection mechanism
3. **Gemini Code Assist** — Google Cloud context; auth and workspace model differ
4. **Kimi** — International deployment; i18n and locale handling needed

Until adapters ship, the `> Degradation notice:` blocks in each advanced skill
document the expected fallback behavior per harness.

## No Automatic CLI Reference Update

`docs/cli-reference.lock` stores the sha256 of `docs/cli-reference.md` at
release time. If you modify `docs/cli-reference.md` manually, re-run
`tools/refresh-cli-reference.sh` to regenerate the lock file. The smoke script
(`tests/smoke/run-claude.sh`) will fail Scenario 4 if the lock is stale.
