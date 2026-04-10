---
id: M-MATRIX-01-infrastructure
epic: E-MATRIX-layout-core
status: in-progress
depends_on: []
---

# M-MATRIX-01: Matrix Infrastructure + Efficient Crossing Count

## Goal

Build the matrix representation of DAGs and implement O(|E| log |V|) crossing count. This replaces the current O(|E|²) pairwise crossing count and provides the foundation for spectral ordering.

## Context

The current crossing count (`crossing-utils.js`) iterates over all edge pairs between adjacent layers — O(|E|²) per layer pair. For 40-node graphs with dense edges, this is the bottleneck in GA evaluation. The matrix approach reduces this to O(|E| log |V|) via merge sort on column indices.

## Acceptance Criteria

1. **Adjacency matrix construction**
   - [ ] `buildAdjacencyMatrix(nodes, edges)` returns a sparse matrix representation
   - [ ] Handles DAGs of 1-100+ nodes efficiently
   - [ ] Tested: round-trip with adjacency list produces identical graph

2. **Graph Laplacian**
   - [ ] `buildLaplacian(adjacencyMatrix)` returns L = D - A
   - [ ] Supports combinatorial and normalized variants
   - [ ] Tested: Laplacian properties verified (row sums = 0, positive semidefinite)

3. **Efficient crossing count**
   - [ ] `countCrossingsMatrix(layerAbove, layerBelow, adjacencyMatrix)` returns crossing count
   - [ ] Uses merge sort inversion count — O(|E| log |V|) per layer pair
   - [ ] Tested: produces identical results to current O(|E|²) `countCrossings` on all fixtures
   - [ ] Benchmark: measurably faster on 30+ node graphs

4. **Integration with pipeline**
   - [ ] Registered as strategy option: `reduceCrossings: 'matrix-barycenter'`
   - [ ] Uses efficient crossing count internally
   - [ ] All 342+ dag-map tests pass

## Deliverables

- `dag-map/src/strategies/matrix.js` — matrix construction and operations
- `dag-map/src/strategies/crossing-count-fast.js` — merge sort crossing count
- Tests for matrix operations and crossing count equivalence
