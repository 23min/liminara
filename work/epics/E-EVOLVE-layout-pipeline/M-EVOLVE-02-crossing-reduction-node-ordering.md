---
id: M-EVOLVE-02-crossing-reduction-node-ordering
epic: E-EVOLVE-layout-pipeline
status: not started
depends_on: [M-EVOLVE-01]
---

# M-EVOLVE-02: Crossing Reduction + Node Ordering Strategies

## Goal

Implement the two highest-impact missing strategies — crossing reduction and node ordering — as pluggable alternatives in the layoutMetro pipeline. These are the techniques that give dagre its edge over dag-map on 80% of benchmark fixtures.

## Context

After M-EVOLVE-01, layoutMetro is a pipeline with `none`/`default` strategies. This milestone adds real alternatives:

- **Node ordering**: dagre and layoutHasse both use barycenter sorting to order nodes within each layer. layoutMetro currently has no node ordering — it just processes nodes in topological order.
- **Crossing reduction**: dagre uses multi-pass barycenter sweeps (alternating top-down/bottom-up). layoutHasse has a working implementation (`reduceCrossings`, 40 lines). layoutMetro has nothing.

The key design challenge is adapting these for metro's **route-centric** model. layoutHasse operates on flat layers of individual nodes. layoutMetro groups nodes into routes with fixed Y positions. The crossing reduction needs to work at either the node level (within-layer reordering before route extraction) or the route level (reordering routes to minimize crossings).

## Acceptance Criteria

1. **Virtual node insertion**
   - [ ] Edges spanning multiple layers are split with virtual (dummy) nodes at each intermediate layer
   - [ ] Virtual nodes participate in ordering and crossing reduction, then are removed before Y-assignment
   - [ ] Adapted from layoutHasse's `insertVirtualNodes` (46 lines)

2. **Node ordering: barycenter**
   - [ ] `strategies/node-ordering/barycenter.mjs`: sorts nodes within each layer by mean position of their neighbors
   - [ ] Adapted from layoutHasse's `barycenterSort` (20 lines)
   - [ ] Configurable: operates on parent positions, child positions, or both

3. **Node ordering: median**
   - [ ] `strategies/node-ordering/median.mjs`: sorts nodes within each layer by median position of their neighbors
   - [ ] Median is more robust to outliers than barycenter (well-known in Sugiyama literature)

4. **Crossing reduction: barycenter-sweep**
   - [ ] `strategies/crossing-reduction/barycenter-sweep.mjs`: multi-pass alternating top-down/bottom-up barycenter sort
   - [ ] Adapted from layoutHasse's `reduceCrossings` (40 lines)
   - [ ] Configurable: number of passes (1–50), keeps best result seen

5. **Crossing reduction: greedy-switching**
   - [ ] `strategies/crossing-reduction/greedy-switching.mjs`: for each pair of adjacent nodes in a layer, swap if it reduces crossings
   - [ ] Simpler than barycenter, sometimes finds improvements barycenter misses
   - [ ] Configurable: number of passes

6. **Crossing count metric**
   - [ ] `countCrossings` function counts edge-edge crossings between consecutive layers
   - [ ] Adapted from layoutHasse's `countCrossings` (29 lines)
   - [ ] Used by crossing reduction to evaluate improvements and by tests to verify reduction

7. **Integration with pipeline**
   - [ ] Node ordering runs after layer assignment, before route extraction
   - [ ] Crossing reduction runs after node ordering (uses the ordered layers)
   - [ ] The order of nodes within each layer influences the subsequent BFS lane allocation
   - [ ] All 285 dag-map tests still pass with default strategies (`none`)

8. **Standalone tests**
   - [ ] Each strategy tested independently on known fixtures with deterministic expected outputs
   - [ ] Crossing count verifiably decreases (or stays same) after crossing reduction
   - [ ] Node ordering produces deterministic output for deterministic input

## Scope

### In Scope

- Virtual node insertion/removal
- Barycenter and median node ordering
- Barycenter-sweep and greedy-switching crossing reduction
- Crossing count metric
- All wired into the pipeline from M-EVOLVE-01

### Out of Scope

- Y-coordinate refinement — that's M-EVOLVE-03
- Extending the bench genome — that's M-EVOLVE-03
- Changing default behavior (defaults remain `none` for backward compatibility)
- Route-level ordering (start with node-level; route-level is a future refinement)

## Dependencies

- M-EVOLVE-01 complete (pipeline structure exists)

## Technical Notes

- **Node ordering before route extraction**: The key insight is that ordering nodes within layers *before* greedy route extraction changes which paths are "longest" and how routes are assembled. This means ordering affects the entire downstream layout, not just visual position.
- **Virtual nodes**: Must be flagged so they're excluded from route extraction, Y-assignment, and rendering. They exist only during the ordering/crossing-reduction phase.
- **Port from layoutHasse**: `barycenterSort` (20 lines), `reduceCrossings` (40 lines), `countCrossings` (29 lines), `insertVirtualNodes` (46 lines) are all portable. The adaptation is in how they integrate with the rest of the metro pipeline.

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Node ordering before route extraction changes trunk selection | High | Test that trunk is still the longest path; ordering shouldn't change path lengths, only positions |
| Virtual nodes confuse route extraction | Med | Flag virtual nodes; route extraction skips them |
| Barycenter doesn't help because metro's Y is route-fixed, not node-free | Med | Order nodes within layers to influence lane allocation order, not final Y directly |

## Deliverables

- `dag-map/src/strategies/node-ordering/barycenter.mjs`
- `dag-map/src/strategies/node-ordering/median.mjs`
- `dag-map/src/strategies/crossing-reduction/barycenter-sweep.mjs`
- `dag-map/src/strategies/crossing-reduction/greedy-switching.mjs`
- `dag-map/src/strategies/virtual-nodes.mjs`
- `dag-map/src/strategies/crossing-count.mjs`
- Tests for each strategy
