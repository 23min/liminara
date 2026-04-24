---
title: Architecture Source Map
doc_type: architecture
truth_class: live
status: active
owner: architecture
last_reviewed: 2026-04-04
source_of_truth:
  - work/roadmap.md
  - docs/governance/truth-model.md
  - docs/architecture/indexes/contract-matrix.md
---

# Architecture Source Map

This file replaces the old "living build plan" as the index for where architectural truth lives.

The historical phase-by-phase build plan is now archived at `docs/history/architecture/02_PLAN.md`. Current sequencing and status live in `work/roadmap.md`.

## Current sources of truth

- **Program sequencing and active status:** `work/roadmap.md`
- **Current architecture narrative:** `docs/architecture/01_CORE.md`
- **Approved next-state execution contract:** `docs/architecture/08_EXECUTION_TRUTH_PLAN.md`
- **Truth governance and contract ownership:** `docs/governance/truth-model.md`, `docs/architecture/indexes/contract-matrix.md`, `docs/governance/shim-policy.md`
- **Historical snapshots and superseded design notes:** `docs/history/`

## Resolution rules

1. If code/tests and narrative docs disagree about current behavior, code/tests win.
2. If current behavior and approved next behavior disagree, active milestone and epic specs define the target state.
3. `work/roadmap.md` is the only current build-plan and sequencing source.
4. `docs/history/` preserves chronology and rationale, but it does not override active docs or live code.

## Update protocol

- When a contract changes, update the relevant row in `docs/architecture/indexes/contract-matrix.md`.
- When a document becomes non-authoritative, move it under `docs/history/` instead of leaving it in `docs/architecture/`.
- When AI instruction behavior needs to change, edit `.ai-repo/` sources and run `./.ai/sync.sh` rather than hand-editing generated instruction files.
