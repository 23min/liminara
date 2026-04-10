---
id: M-MATRIX-03-hybrid-ga-integration
epic: E-MATRIX-layout-core
status: not started
depends_on: [M-MATRIX-02]
---

# M-MATRIX-03: Hybrid Ordering + GA Integration

## Goal

Enable the GA to evolve continuous blends between spectral and heuristic orderings, with edge weight parameters — creating a richer optimization surface than pure algorithm selection.

## Context

M-MATRIX-02 gives us spectral ordering as a strategy option. But the real power is in hybrids: "70% spectral + 30% barycenter with edge weight power 1.8" may outperform either pure approach. These blending parameters are continuous — perfect for GA optimization.

## Acceptance Criteria

1. **Hybrid ordering strategy**
   - [ ] `orderNodesHybrid(ctx)` blends spectral and barycenter orderings
   - [ ] Blend parameter `spectralBlend` (0.0 = pure spectral, 1.0 = pure barycenter)
   - [ ] For each node: `position = blend * barycenterPos + (1-blend) * spectralPos`
   - [ ] Registered as `orderNodes: 'hybrid'`

2. **Extended genome**
   - [ ] `strategy.spectralBlend` — continuous 0.0–1.0
   - [ ] `strategy.edgeWeightPower` — continuous 0.5–3.0
   - [ ] `strategy.laplacianType` — categorical: combinatorial, normalized
   - [ ] All three evolvable by GA crossover and mutation

3. **Benchmark comparison**
   - [ ] Evolution run (100+ generations) with matrix strategies available
   - [ ] Report: spectral vs barycenter vs hybrid vs dagre on 2,220 fixtures
   - [ ] Document which parameter values the GA converges to

4. **Tinder validation**
   - [ ] Tinder session comparing spectral vs heuristic layouts
   - [ ] At least 50 votes to validate that spectral orderings are visually preferred

## Deliverables

- `dag-map/src/strategies/order-nodes-hybrid.js` — hybrid ordering
- `bench/genome/strategy-genes.mjs` updates for matrix parameters
- Benchmark report and Tinder vote log
