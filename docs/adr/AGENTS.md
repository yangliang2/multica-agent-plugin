<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-06-07 | Updated: 2026-06-07 -->

# docs/adr

## Purpose
Architecture Decision Records — immutable documents that capture the context, options considered, and rationale for significant design decisions. ADRs explain the *why* behind choices that are no longer obvious from the code alone.

## Key Files

| File | Description |
|------|-------------|
| `0001-claude-code-mvp.md` | ADR 0001 — Adopts Claude Code as the sole supported harness for the 0.1.0 MVP. Establishes `AGENTS.md` as single source of truth; all other files (`CLAUDE.md`, hooks, skills) are additive affordances. Post-MVP harness adapters will shim to the same `AGENTS.md` contract. |

## For AI Agents

### Working In This Directory
- **Do not edit accepted ADRs.** Status transitions (Proposed → Accepted → Superseded) are the only permitted changes.
- To supersede an ADR: create a new numbered ADR, reference the superseded one, then update the old ADR's status to `Superseded by ADR-XXXX`.
- Numbering is sequential: next ADR is `0002-<slug>.md`.

### Common Patterns
- ADR template sections: Status, Date, Deciders, Decision, Context, Options Considered, Consequences.

<!-- MANUAL: -->
