<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-06-07 | Updated: 2026-06-07 -->

# docs

## Purpose
Project documentation: ABI contracts that freeze the external CLI interface agents depend on, and Architecture Decision Records (ADRs) that capture why key design choices were made.

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `abi/` | Outward ABI definitions — CLI anchor index, JSON schemas, version contract (see `abi/AGENTS.md`) |
| `adr/` | Architecture Decision Records — immutable rationale for past decisions (see `adr/AGENTS.md`) |

## For AI Agents

### Working In This Directory
- `abi/` documents are normative — changing them is a breaking change. Always bump the version contract when editing.
- `adr/` documents are immutable after acceptance. Do not edit accepted ADRs; write a new superseding ADR instead.

<!-- MANUAL: -->
