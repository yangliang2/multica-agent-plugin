<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-06-07 | Updated: 2026-06-07 -->

# docs/abi

## Purpose
Outward ABI (Application Binary Interface) contracts that freeze the external CLI interface agents depend on. Skills must only call commands through the anchors defined here — never via raw CLI literals.

## Key Files

| File | Description |
|------|-------------|
| `cli-outward.md` | CLI anchor index — maps every `<<cli:*>>` anchor to its resolved `multica ...` command. Includes version contract (`multica ≥ 0.3.4`), JSON schemas for command output, and deprecation notices. |

## For AI Agents

### Working In This Directory
- This file is **normative and versioned**. Any change to a command signature is a breaking change and requires a version bump in the contract header.
- To add a new CLI anchor: add the anchor row to the table, document the JSON schema for its output, and update the version contract if the minimum CLI version changes.
- Never remove an anchor without marking it deprecated first (one release cycle).

### Common Patterns
- Anchor format: `<<cli:noun.verb>>` matching `multica noun verb` subcommand structure.
- Output schema: document as a code block with field names and types directly below the anchor table row.

## Dependencies

### External
- `multica` CLI (≥0.3.4) — the commands this ABI describes

<!-- MANUAL: -->
