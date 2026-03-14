---
id: E-01-data-model-spec
phase: 0
status: done
---

# E-01: Data Model Specification

## Goal

Define the canonical on-disk format that both the Python SDK (Phase 1) and the Elixir runtime (Phase 2) implement against. One spec, two implementations, zero ambiguity.

## Scope

**In:**
- Hash algorithm and encoding (SHA-256, `sha256:{64 hex}`)
- Canonical serialization format (RFC 8785 JSON)
- Artifact storage layout (filesystem, content-addressed, sharded)
- Event log format (JSONL, hash-chained, append-only)
- Decision record schema
- Run seal definition
- Event type catalogue (minimum set)
- Directory layout specification
- Implementation checklist

**Out:**
- Implementation in any language
- Plan format (Elixir runtime concern)
- Artifact content schemas / IRs (Pack concern)
- Retention policy details

## Milestones

| ID | Milestone | Status |
|----|-----------|--------|
| M-DM-01-spec | Write canonical data model specification | done |

## Success criteria

- [x] Spec covers all on-disk formats: artifacts, events, decisions, run seal
- [x] Hash computation is unambiguous (exact input for each hash)
- [x] An implementer can build against it without asking questions
- [x] Implementation checklist at the bottom for verification

## References

- Deliverable: `docs/analysis/11_Data_Model_Spec.md`
- Spec: `docs/architecture/01_CORE.md` § Five concepts
