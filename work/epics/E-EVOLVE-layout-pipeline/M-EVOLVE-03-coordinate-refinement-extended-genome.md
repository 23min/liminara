---
id: M-EVOLVE-03-coordinate-refinement-extended-genome
epic: E-EVOLVE-layout-pipeline
status: not started
depends_on: [M-EVOLVE-02]
---

# M-EVOLVE-03: Coordinate Refinement + Extended Genome

## Goal

Add Y-coordinate refinement strategies to the pipeline, then extend the bench genome to include strategy selection genes — enabling the GA to evolve which algorithmic combination works best, not just spacing parameters.

## Context

After M-EVOLVE-02, the pipeline has node ordering and crossing reduction strategies but they're manually selected via `options.strategies`. The bench genome still only has 8 continuous fields (4 render + 4 energy). This milestone:

1. Adds coordinate refinement (the third missing Sugiyama technique)
2. Extends the genome with categorical strategy genes
3. Wires the GA to evolve strategy combinations

## Acceptance Criteria

1. **Y-coordinate refinement: barycenter-pull**
   - [ ] `strategies/coordinate-refinement/barycenter-pull.mjs`: iteratively moves nodes toward the barycenter of their neighbors
   - [ ] Adapted from layoutHasse's `assignXCoordinates` (47 lines) — applied to Y instead of X
   - [ ] Includes spacing enforcement (minimum distance between nodes) adapted from layoutHasse's `enforceSpacing`
   - [ ] Configurable: number of iterations (1–20)
   - [ ] Operates after initial BFS lane allocation, refining Y positions while respecting occupancy

2. **Extended genome schema**
   - [ ] `bench/genome/tier2.mjs` (or strategy genes in tier1): defines categorical strategy fields
   - [ ] Strategy genes: `nodeOrdering` (none/barycenter/median), `crossingReduction` (none/barycenter/greedy-switching), `crossingPasses` (1–50), `yRefinement` (none/barycenter-pull), `yRefinementIterations` (1–20)
   - [ ] Genome serialization/deserialization handles mixed continuous + categorical fields
   - [ ] `toEvaluatorGenome` projects strategy selections into `options.strategies` for layoutMetro

3. **GA operators for categorical genes**
   - [ ] Crossover: categorical genes inherited from one parent (no blending)
   - [ ] Mutation: categorical genes randomly switch to another valid value with configurable probability
   - [ ] Continuous genes use existing Gaussian mutation (unchanged)

4. **Evaluator integration**
   - [ ] `bench/evaluator/evaluator.mjs` passes `options.strategies` derived from genome to `layoutMetro`
   - [ ] All energy terms score layouts produced by the selected strategy combination
   - [ ] No per-strategy special-casing in the energy function

5. **Backward compatibility**
   - [ ] Default genome produces `none` strategies (current behavior)
   - [ ] All 285 dag-map tests pass
   - [ ] All existing bench tests pass
   - [ ] Existing GA runs can still resume (old genome format tolerated)

6. **Strategy combination tests**
   - [ ] At least one test runs the evaluator with each non-default strategy on a sample fixture
   - [ ] Crossing count verifiably lower with barycenter-sweep vs none on a fixture with known crossings

## Scope

### In Scope

- Barycenter-pull Y-coordinate refinement strategy
- Extended genome with strategy selection genes
- GA crossover/mutation operators for categorical genes
- Evaluator integration (genome → strategies → layoutMetro → energy score)

### Out of Scope

- New energy terms
- Evolution runs (that's M-EVOLVE-04)
- Benchmark reports (that's M-EVOLVE-04)
- New node ordering or crossing reduction algorithms beyond M-EVOLVE-02

## Dependencies

- M-EVOLVE-02 complete (node ordering + crossing reduction strategies available)

## Technical Notes

- **Categorical mutation rate**: should be lower than continuous mutation to avoid thrashing between strategies every generation. Suggest 0.1 (10% chance of switching strategy per gene per mutation).
- **Island model**: consider one island per `crossingReduction` strategy (mirroring E-DAGBENCH's one-island-per-routing-primitive). Prevents barycenter and greedy-switching from competing within the same population. Alternative: single island, let selection decide.
- **Coordinate refinement after BFS**: barycenter-pull refines the Y positions assigned by BFS lane allocation. It should respect route grouping — nodes on the same route should stay close together.

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Categorical genes increase search space; GA converges slowly | Med | Small number of strategies (2-3 per slot); start with small populations |
| Coordinate refinement breaks route visual coherence | Med | Enforce per-route Y constraints during refinement |
| Mixed genome complicates crossover/mutation operators | Low | Separate continuous and categorical crossover; test independently |

## Deliverables

- `dag-map/src/strategies/coordinate-refinement/barycenter-pull.mjs`
- `bench/genome/` updates for strategy genes
- `bench/ga/operators.mjs` updates for categorical crossover/mutation
- `bench/evaluator/evaluator.mjs` updates for strategy passthrough
- Tests for refinement strategy, genome operations, and evaluator integration
