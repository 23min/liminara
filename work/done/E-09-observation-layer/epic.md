---
id: E-09-observation-layer
phase: 4
status: done
---

# E-09: Observation Layer

## Goal

Build the real-time observation infrastructure for Liminara runs. When this epic is done, a user can watch a run execute in a browser — see the DAG, watch nodes change state in real-time, click any node to inspect its inputs/outputs/decisions, view the event timeline, and browse artifacts. A secondary experimental A2UI renderer provides a mobile-friendly status feed.

## Scope

**In:**
- Observation.Server — renderer-agnostic GenServer that subscribes to `:pg` events and maintains a view model (DAG state, node statuses, timing, artifacts, decisions)
- Phoenix app (liminara_web) in the umbrella — LiveView-based, responsive
- Runs dashboard — list all runs, status, timing, pack info
- SVG-based DAG visualization — nodes, edges, real-time state updates
- Node inspector — inputs, outputs, decisions, timing
- Artifact viewer — content display (JSON, text, binary metadata)
- Event timeline — chronological, filterable
- A2UI experimental renderer — ex_a2ui integration, mobile status feed
- Mobile-responsive layout

**Explicitly out:**
- DAG editor / visual flow designer (observation is read-only)
- Authentication / multi-user
- Deployment configuration (Hetzner, Docker, etc.)
- Canvas-based rendering (SVG first; canvas is a future optimization)
- Discovery mode visualization (pipeline mode only)
- Polished visual design (functional first, aesthetics iterate)

## Milestones

| ID | Milestone | Status |
|----|-----------|--------|
| M-OBS-01-observation-server | Observation Server — renderer-agnostic event projection | done |
| M-OBS-02-phoenix-scaffold | Phoenix scaffolding + runs dashboard | done |
| M-OBS-03-dag-visualization | SVG DAG visualization with real-time updates | done |
| M-OBS-04a-inspector | Node inspector + artifact viewer + dashboard layout | done |
| M-OBS-04b-timeline | Event timeline + decision viewer | done |
| M-OBS-05a-gate-demo | Gate demo + LiveView gate interaction | done |
| M-OBS-05b-a2ui | A2UI exploration + integration | done |

## Success criteria

- [ ] Can start a ToyPack run and watch it execute in real-time in a browser
- [ ] DAG visualization shows nodes colored by state (pending/running/completed/failed/waiting)
- [ ] Clicking a node shows its inputs, outputs, decisions, and timing
- [ ] Event timeline streams events as they happen
- [ ] Artifact content is viewable (JSON pretty-printed, text displayed, binary shows metadata)
- [ ] Gate nodes are visually distinct and show their prompt/response
- [ ] Layout is responsive — usable on mobile (at minimum: runs list + status)
- [ ] A2UI endpoint serves a basic status feed over WebSocket
- [ ] The Observation.Server is renderer-agnostic — both LiveView and A2UI consume the same state

## References

- Spec: `docs/architecture/01_CORE.md §Observation: the Excel quality`
- Spec snapshot: `docs/history/architecture/03_PHASE3_REFERENCE.md §Event broadcasting`
- Research: `docs/research/a2ui_finding.md`
- Research: `docs/research/graph_execution_patterns.md §7 Visualization`
- ADR: `docs/decisions/ADR-002-visual-execution-states.md` (accepted — Phase 1 shipped in M-OBS-05a; Phases 2-3 deferred — renamed from ADR-007 on 2026-04-22 per framework ADR-NNNN convention)
