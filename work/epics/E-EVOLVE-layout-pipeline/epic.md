---
id: E-EVOLVE-layout-pipeline
phase: 5c-parallel
status: planning
depends_on: E-DAGBENCH-layout-evolution
---

# E-EVOLVE: Evolvable Layout Pipeline

**ID:** E-EVOLVE

## Goal

Refactor dag-map's `layoutMetro` from a monolithic function with tunable spacing knobs into a **pipeline of swappable algorithmic strategies** — then evolve the best strategy combination using the existing GA harness. The current bench evolves 4 render parameters; after this epic it evolves the algorithm itself: which crossing reduction heuristic, which node ordering, which coordinate refinement, how many passes — with the GA exploring thousands of combinations humans would never try.

## Context

E-DAGBENCH built the evolution harness: energy functional, GA with islands, Tinder UI, Bradley-Terry refit, external benchmarks. But the genome only controls 4 spacing parameters that feed into `layoutMetro()`. The algorithm's actual decisions — how nodes are ordered within layers, whether crossings are minimized, how coordinates are refined — are all hardcoded.

The benchmark report (seed 42, 50 generations, 2,220 fixtures) shows the current state:
- **vs dagre**: 442W / 1,777L — dagre wins 80% on the energy functional
- **vs ELK**: 1,525W / 694L — dag-map already beats ELK on 69%

dagre's advantage comes from Sugiyama-framework techniques that layoutMetro lacks entirely: barycenter crossing reduction, median node ordering, iterative coordinate refinement. dag-map's own `layoutHasse` engine already implements barycenter crossing reduction and coordinate refinement, but layoutMetro doesn't use any of it.

The fix is not to copy dagre. It's to make layoutMetro's pipeline pluggable, implement multiple strategies per step (including techniques from layoutHasse), and let evolution find the best combination for dag-map's metro aesthetic.

## Approach

**Automated algorithm configuration**, not genetic programming. We don't evolve raw code — we implement known graph layout techniques as swappable strategy functions, then evolve which combination works best.

**Pipeline decomposition.** layoutMetro currently executes 6 hardcoded steps. We decompose it into a sequence of strategy slots:

```
DAG
 → [Layer Assignment]      — longest-path (current), minimum-width, Coffman-Graham
 → [Node Ordering]         — none (current), barycenter, median
 → [Crossing Reduction]    — none (current), barycenter-sweep, greedy-switching
 → [Y-Position Assignment] — BFS-occupancy (current), barycenter-pull
 → [X-Coordinate Refine]   — fixed-spacing (current), iterative-barycenter
 → [Routing]               — bezier (current), angular, metro (already plugged)
 → Layout
```

**Extended genome.** Strategy selection genes (categorical) join the existing continuous parameter genes:

| Gene | Type | Values |
|------|------|--------|
| `strategy.nodeOrdering` | categorical | `none`, `barycenter`, `median` |
| `strategy.crossingReduction` | categorical | `none`, `barycenter`, `greedy-switching` |
| `strategy.crossingPasses` | integer | 1–50 |
| `strategy.yRefinement` | categorical | `none`, `barycenter-pull` |
| `strategy.yRefinementIterations` | integer | 1–20 |
| + existing render params | continuous | current ranges |

**Backward compatible.** Default strategy values reproduce current layoutMetro behavior exactly. Existing dag-map tests pass without changes. The pluggable pipeline is an internal refactoring, not an API change.

**Crossing reduction adapted for metro.** layoutHasse's barycenter works on a flat node-per-layer model. layoutMetro is route-centric — nodes are grouped into routes that maintain fixed Y. The crossing reduction needs to operate on route ordering within layers, not individual nodes. This is the key design challenge.

**Virtual nodes for long edges.** layoutHasse inserts virtual nodes for edges spanning multiple layers, enabling per-layer crossing reduction. layoutMetro should adopt this for the crossing reduction step, then remove virtual nodes before Y-assignment.

## Scope

### In Scope

- Refactor layoutMetro into a pipeline of named strategy functions
- Implement node ordering strategies: barycenter, median (ported/adapted from layoutHasse)
- Implement crossing reduction strategies: barycenter-sweep, greedy-switching
- Implement Y-coordinate refinement: barycenter-pull (adapted from layoutHasse)
- Virtual node insertion for long edges (adapted from layoutHasse)
- Extend bench genome to include strategy selection genes
- GA evolution of strategy combinations against existing energy functional
- Benchmark report comparing evolved pipeline vs dagre vs ELK

### Out of Scope

- Changing dag-map's public API or default behavior (defaults = current strategies)
- Modifying layoutHasse or layoutFlow
- New energy terms (existing 8 terms are sufficient)
- Shipping evolved defaults as a dag-map release (separate decision)
- Touching Liminara runtime code

## Constraints

- All 285 dag-map tests must pass at every milestone (default strategies = current behavior)
- All bench tests must pass at every milestone
- No new dependencies in dag-map's main package.json
- Strategy functions must be deterministic (same input → same output)
- Pipeline refactoring must not change layoutMetro's public interface or return shape
- Work happens on the dagbench worktree, same parallel track as E-DAGBENCH

## Success Criteria

- [ ] layoutMetro is decomposed into a pipeline where each step is a swappable function
- [ ] At least 2 strategies per slot implemented and tested
- [ ] Default strategies reproduce current behavior exactly (285 dag-map tests green)
- [ ] Extended genome includes strategy selection; GA evolves strategy combinations
- [ ] Evolved pipeline substantially improves dag-map vs dagre win rate on external benchmarks (target: from 20% to >50%)
- [ ] Benchmark report with evolved pipeline published (win or lose, per E-DAGBENCH honesty constraint)

## Risks & Open Questions

| Risk / Question | Impact | Mitigation |
|----------------|--------|------------|
| Crossing reduction for route-centric layouts is harder than for flat node layouts | High | Start with per-layer node ordering (simpler), then add route-aware crossing reduction |
| Strategy combinations explode the search space; GA convergence slows | Med | Start with 2 strategies per slot (small space); expand if convergence is fast |
| Barycenter adapted from layoutHasse may not compose well with metro's BFS lane allocation | Med | M-02 tests this specifically; fallback is to keep BFS for Y and only add crossing reduction |
| Virtual node insertion changes route extraction behavior | Med | Virtual nodes inserted after route extraction, removed before Y-assignment |
| Performance: more pipeline steps slow down evaluation | Low | Each strategy is O(n²) at worst on <100 nodes; negligible vs current evaluation cost |

## Milestones

| ID | Title | Status |
|----|-------|--------|
| M-EVOLVE-01 | Pipeline refactoring | not started |
| M-EVOLVE-02 | Crossing reduction + node ordering strategies | not started |
| M-EVOLVE-03 | Coordinate refinement + extended genome | not started |
| M-EVOLVE-04 | Evolution run + benchmark comparison | not started |

## ADRs

- (none yet — candidate: route-centric vs node-centric crossing reduction model)

## References

- `dag-map/src/layout-metro.js` — current monolithic layout (542 lines)
- `dag-map/src/layout-hasse.js` — barycenter crossing reduction + coordinate refinement source
- `dag-map/src/graph-utils.js` — shared topo sort + graph primitives
- `bench/` — existing GA harness (E-DAGBENCH)
- `work/epics/E-DAGBENCH-layout-evolution/epic.md` — predecessor epic
