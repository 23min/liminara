---
id: ADR-007
status: accepted
date: 2026-03-23
---

# ADR-007: Visual Execution States in the Observation Layer

## Status

Accepted. Phase 1 (dim pending nodes) shipped in M-OBS-05a. Phases 2-3 (cache-aware and replay-aware visual states) deferred; tracked in `work/gaps.md`.

### Status history

- 2026-03-23 — drafted
- 2026-04-01 — Phase 1 shipped (M-OBS-05a, via E-09 squash merge `2a45b5e`); ADR promoted to accepted
- Phase 2 and Phase 3 deferred as documented in the body of this ADR; see `work/gaps.md`

## Context

The observation layer's DAG visualization currently maps execution status to dag-map CSS classes:

| Execution status | dag-map class | Color |
|---|---|---|
| completed | pure | teal |
| running | recordable | coral |
| failed | gate | red |
| waiting | side_effecting | amber |
| pending | pending | gray |

This conflates two dimensions: **determinism class** (what kind of op) and **execution status** (what happened to it). The result is confusing:
- Pending nodes look nearly identical to completed nodes (gray vs teal at small sizes)
- There's no distinction between "not yet reached" and "has a cached result"
- Replay mode (injecting stored decisions) looks identical to discovery mode

## Problem

The user needs to see at a glance:
1. Where execution has reached (the "frontier")
2. What's blocking progress (gates, errors)
3. What will be skipped (cached results)
4. What decisions will be replayed vs discovered

## Proposed visual states

| Visual state | Meaning | Rendering |
|---|---|---|
| **Completed** | Executed in this run | Full color, full opacity |
| **Running** | Currently executing | Full color, possibly pulsing |
| **Failed** | Errored in this run | Red, full opacity |
| **Waiting (gate)** | Blocked on human/agent input | Amber, pulsing, attention indicator |
| **Pending** | Not yet reached | Dimmed (low opacity), routes dimmed |
| **Cached** | Has cached result, will skip | Dotted outline or "cached" badge |
| **Replay** | Decision exists, will inject | Different fill pattern or badge |

## Implementation approach

### Phase 1: Dim pending nodes (M-OBS-05a)
- dag-map: add generic `dim: true` flag → reduces node + route opacity
- Liminara: set `dim: true` on pending nodes
- Immediate visual improvement, no cache integration needed

### Phase 2: Cache-aware states (future)
- Observation.Server queries cache for each pending node
- Adds `cache_available: true` to node view
- dag-map renders cached nodes with a distinct visual (dotted outline, badge)
- Requires: cache lookup API in Observation.Server

### Phase 3: Replay-aware states (future)
- Decision Store queried for each recordable/side-effecting node
- Adds `replay_available: true` to node view
- Visual distinction for "will replay" vs "will discover"
- Requires: Decision Store lookup API in Observation.Server

## Decision

Implement Phase 1 now. Defer Phases 2-3 until cache and replay integration are needed (likely Phase 5: Radar or later).

## References

- `docs/architecture/01_CORE.md §Caching` and `§Discovery vs Replay`
- dag-map library: `dim` flag proposal
- M-OBS-05a milestone (gate demo)
