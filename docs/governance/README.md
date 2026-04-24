# Governance

Binding authoring rules for Liminara's project artifacts. See
[ADR-0003](../decisions/0003-doc-tree-taxonomy.md) for the full
bind-me / inform-me taxonomy.

## Instruments

| File | Purpose |
|------|---------|
| [truth-model.md](truth-model.md) | How Liminara adjudicates between competing truth sources (live code, specs, history). |
| [shim-policy.md](shim-policy.md) | When a backward-compatibility shim is allowed (and how it must be removed). |

Related architecture-level inventory:
- [docs/architecture/indexes/contract-matrix.md](../architecture/indexes/contract-matrix.md) — ownership and status of every first-class contract surface.

## Moved from `docs/architecture/contracts/`

The following files were relocated under ADR-0003. Frozen records
(`work/done/`, `work/agent-history/`, `work/decisions.md` entries
D-001–D-030) that link to the old paths are not rewritten; use this
table to resolve them.

| Old path | New path |
|----------|----------|
| `docs/architecture/contracts/00_TRUTH_MODEL.md` | `docs/governance/truth-model.md` |
| `docs/architecture/contracts/02_SHIM_POLICY.md` | `docs/governance/shim-policy.md` |
| `docs/architecture/contracts/01_CONTRACT_MATRIX.md` | `docs/architecture/indexes/contract-matrix.md` |
