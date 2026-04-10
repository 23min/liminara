---
id: M-MATRIX-02-spectral-ordering
epic: E-MATRIX-layout-core
status: not started
depends_on: [M-MATRIX-01]
---

# M-MATRIX-02: Spectral Ordering (Fiedler Vector)

## Goal

Implement spectral node ordering using the Fiedler vector — a globally optimal 1D embedding that places connected nodes close together. This replaces iterative local heuristics (barycenter, median) with a one-shot global optimization.

## Context

Barycenter ordering (from E-EVOLVE) is a local heuristic — it sorts each layer by the mean position of neighbors, iterating until convergence. It can get stuck in local optima. Spectral ordering computes the second-smallest eigenvector of the graph Laplacian, which provably minimizes the weighted sum of squared edge lengths in 1D. For many graph classes, this directly minimizes crossings.

## Acceptance Criteria

1. **Fiedler vector computation**
   - [ ] `computeFiedlerVector(laplacian)` returns the second-smallest eigenvector
   - [ ] Implemented via power iteration with deflation (no external deps)
   - [ ] Deterministic: seeded initial vector, fixed iteration count
   - [ ] Converges within 100 iterations for graphs up to 100 nodes
   - [ ] Tested: Fiedler vector of a path graph is monotonic (known analytical result)

2. **Spectral node ordering strategy**
   - [ ] `orderNodesSpectral(ctx)` sorts nodes within each layer by their Fiedler vector component
   - [ ] Registered as `orderNodes: 'spectral'` in the strategy registry
   - [ ] Tested: produces fewer crossings than barycenter on at least one Tier C fixture

3. **Per-layer spectral ordering**
   - [ ] For the full DAG, compute the Fiedler vector once
   - [ ] Within each layer, sort nodes by their Fiedler value
   - [ ] Nodes with similar connectivity patterns end up adjacent

4. **Edge-weighted spectral ordering**
   - [ ] `computeWeightedLaplacian(adjacencyMatrix, edgeWeightPower)` weights edges by `1/distance^power`
   - [ ] The `edgeWeightPower` parameter is evolvable by the GA
   - [ ] Tested: different weight powers produce different orderings

## Deliverables

- `dag-map/src/strategies/spectral.js` — Fiedler vector computation
- `dag-map/src/strategies/order-nodes-spectral.js` — spectral ordering strategy
- Tests for eigenvector properties and ordering quality
