---
id: E-MATRIX-layout-core
phase: 5c-parallel
status: planning
depends_on: E-EVOLVE-layout-pipeline
---

# E-MATRIX: Matrix-Based Layout Core

**ID:** E-MATRIX

## Goal

Replace dag-map's ad-hoc graph traversals with a matrix-based layout core — adjacency matrix, graph Laplacian, efficient crossing count, and spectral ordering. This makes the layout algorithm mathematically principled, enables global optimization (spectral) instead of local heuristics (barycenter), and opens new continuous parameters for GA evolution.

## Context

E-EVOLVE built a pluggable strategy pipeline for layoutMetro and proved that evolutionary algorithm configuration works — the GA finds strategy combinations that beat dagre on 97% of 2,220 benchmarks. But the strategies themselves are basic: barycenter sorting (iterative, local, gets stuck in local optima), greedy adjacent-swap, and BFS lane allocation. These are 1980s Sugiyama heuristics.

Matrix representation enables:
- **O(|E| log |V|) crossing count** instead of O(|E|²) — via merge sort on the crossing matrix
- **Spectral ordering** — the Fiedler vector (second eigenvector of the graph Laplacian) gives a globally optimal 1D node embedding that provably minimizes certain crossing metrics
- **Continuous blending** — mix spectral and heuristic orderings with a blend parameter the GA can evolve
- **Edge weighting** — the crossing matrix can weight edges by length/importance, creating a richer optimization surface

The GA's role shifts from "pick strategy A or B" to "evolve continuous parameters that control hybrid matrix algorithms." The Tinder UI stays as-is for human aesthetic steering.

## Approach

The layout algorithm's internal representation changes from adjacency lists to matrices. The pipeline slots from E-EVOLVE remain — the matrix algorithms are registered as new strategies in the same registry. Existing strategies continue to work (backward compatible).

**Layout is purely topological.** Node `cls` does not influence positions (established in E-EVOLVE). Styling (color, thickness, opacity) is a rendering overlay, not a layout concern.

**X positioning is a consumer constraint**, not evolvable. The consumer chooses `fixed`, `compact`, `custom`, or `proportional` — the GA optimizes everything else within that constraint.

### Matrix infrastructure

```
Adjacency matrix A:  A[i][j] = 1 if edge i→j
Degree matrix D:     D[i][i] = out-degree of node i
Laplacian L:         L = D - A (or normalized variant)
Crossing matrix C:   C[i][j] = crossings if node i is above node j in a layer
```

### Spectral ordering

The Fiedler vector (second-smallest eigenvector of L) places connected nodes close together in a 1D embedding. Sort nodes by Fiedler value = optimal ordering for crossing minimization on many graph classes.

For JavaScript: power iteration or Lanczos algorithm to compute the Fiedler vector without external dependencies. Convergence is fast for sparse graphs (typical DAGs).

### GA integration

New evolvable parameters with matrix representation:

| Parameter | Type | Range | Purpose |
|-----------|------|-------|---------|
| `crossingAlgorithm` | categorical | spectral, barycenter, median, hybrid | Node ordering method |
| `spectralBlend` | continuous | 0.0–1.0 | Blend spectral + heuristic ordering |
| `edgeWeightPower` | continuous | 0.5–3.0 | Weight long edges in crossing matrix |
| `laplacianType` | categorical | combinatorial, normalized, signless | Which Laplacian to use |
| `coordinateMethod` | categorical | barycenter, priority | Coordinate assignment approach |
| `refinementStrength` | continuous | 0.0–1.0 | Post-spectral iterative refinement amount |

## Scope

### In Scope

- Adjacency matrix and Laplacian construction from DAG
- Efficient crossing count via merge sort on crossing matrix
- Fiedler vector computation (power iteration, no external deps)
- Spectral node ordering strategy
- Hybrid spectral+barycenter ordering with blend parameter
- Edge-weighted crossing matrix
- GA genome extension with matrix parameters
- Benchmark comparison (spectral vs barycenter vs dagre)

### Out of Scope

- Network simplex coordinate assignment (complex, deferred)
- External linear algebra libraries (keep dependency-free)
- Changes to rendering/styling
- Changes to the Tinder UI (it works as-is)
- Modifying layoutHasse or layoutFlow

## Constraints

- All 342+ dag-map tests must pass at every milestone
- No external dependencies in dag-map's main package
- Matrix operations must be fast enough for GA evaluation (~100ms per fixture)
- Spectral ordering must be deterministic (seeded power iteration)
- Consumer X positioning choice is a constraint, not evolvable

## Success Criteria

- [ ] Crossing count is O(|E| log |V|) — measurably faster on 40+ node graphs
- [ ] Spectral ordering produces fewer crossings than barycenter on Tier C benchmarks
- [ ] GA can evolve spectral blend parameters and they converge to non-trivial values
- [ ] Evolved matrix-based pipeline maintains or improves the 97% win rate vs dagre
- [ ] Layout quality on visual inspection (Tinder) is preferred over non-spectral approaches

## Risks & Open Questions

| Risk / Question | Impact | Mitigation |
|----------------|--------|------------|
| Power iteration may not converge on degenerate graphs | Med | Fallback to barycenter if eigenvalue computation fails |
| Spectral ordering may not compose well with metro routes | Med | Test on Tier A (metro-style) and Tier C (pure DAGs) separately |
| Fiedler vector computation too slow for GA evaluation | Med | Pre-compute and cache per fixture; only recompute when edge weights change |
| Matrix representation adds memory overhead | Low | Sparse representation; DAGs under 100 nodes are tiny |

## Milestones

| ID | Title | Status |
|----|-------|--------|
| M-MATRIX-01 | Matrix infrastructure + efficient crossing count | not started |
| M-MATRIX-02 | Spectral ordering (Fiedler vector) | not started |
| M-MATRIX-03 | Hybrid ordering + GA integration | not started |

## ADRs

- (none yet — candidate: Laplacian variant selection, power iteration vs Lanczos)

## References

- Sugiyama, Tagawa, Toda (1981) — original layered graph drawing framework
- Koren (2005) — "Drawing Graphs by Eigenvectors" — spectral graph drawing
- Junger & Mutzel (2004) — "2-Layer Straightline Crossing Minimization" — matrix approach
- dag-map `src/strategies/` — existing pipeline from E-EVOLVE
- bench `genome/strategy-genes.mjs` — existing GA genome
