---
title: Compatibility Shim Policy
doc_type: contract-governance
truth_class: live
status: active
owner: architecture
last_reviewed: 2026-04-04
source_of_truth:
  - docs/architecture/contracts/00_TRUTH_MODEL.md
  - work/epics/E-20-execution-truth/M-TRUTH-01-execution-spec-outcome-design.md
---

# Compatibility Shim Policy

Compatibility shims are banned by default.

Liminara should move contracts forward by changing the source of truth, not by letting incompatible stories coexist indefinitely.

## Allowed exception

A shim is allowed only when all of the following are true:

1. The runtime would otherwise be unusable or impossible to migrate in bounded steps.
2. The shim adapts shape, not semantics. It must not preserve a known lie such as false purity, fake runtime identity, or hidden degraded output.
3. The owning milestone spec names the shim explicitly.
4. The active tracking doc records the removal trigger and owning milestone.
5. The code carries a removal comment naming the milestone or decision that must delete it.

## Required records

- Milestone spec entry describing why the shim exists
- Tracking doc entry with removal trigger
- `work/gaps.md` entry if the shim survives beyond the owning milestone
- Contract matrix note if the shim affects a major contract surface

## Forbidden shims

- Indefinite dual surfaces where old and new contracts both look first-class
- Shims that hide semantic mismatches behind field translation
- Shims that keep historical docs looking current
- Shims that let generated instruction files diverge from `.ai-repo/` sources

## Review question

Before accepting any shim, ask:

"Does this preserve truth while creating a bounded migration step, or does it merely postpone naming the real contract?"