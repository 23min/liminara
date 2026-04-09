---
id: M-DAGBENCH-01-energy-function-corpus-evaluator
epic: E-DAGBENCH-layout-evolution
status: not started
depends_on: dag-map (current main)
---

# M-DAGBENCH-01: Energy Function + Corpus + Evaluator

## Goal

Build the testable foundation of the bench: an energy functional with eight physics-inspired terms, a hard-invariant checker that rejects layouts before scoring, fixture loaders for Tier A and Tier B, and a single-individual evaluator that produces a deterministic score for any (genome, fixture) pair. After this milestone, `bench/` can score the current dag-map v14/R10 defaults across the seed corpus and produce a reference floor that M-DAGBENCH-02 can try to beat.

## Context

`dag-map` was hand-tuned over 32 iterations against an implicit, intuitive cost function. This milestone makes that cost function explicit and contestable. Every later milestone depends on this scalar being well-defined, deterministic, and unit-tested per term. If the energy function is wrong, the GA optimizes the wrong thing.

This is the milestone where the energy function will be most disputed. Acceptance criteria are deliberately tight.

## Acceptance Criteria

1. **Energy terms — each implemented and unit-tested in isolation**
   - [ ] `stretch` — penalizes edges longer than `stretch_ideal_factor * topological_distance`
   - [ ] `repel_nn` — node-node repulsion, monotone in inverse distance below `repel_threshold_px`
   - [ ] `repel_ne` — node-edge repulsion (label crowding proxy)
   - [ ] `bend` — sum of squared turning angles along each rendered route
   - [ ] `crossings` — count of edge-edge crossings
   - [ ] `channel` — channel separation between parallel route bundles
   - [ ] `monotone` — penalty for any non-monotone X progression along a route
   - [ ] `envelope` — aspect-ratio / silhouette deviation from target
   - [ ] Each term has at least: one happy-path test, one zero-case test (input that should score 0), one ordering test (configuration A scores strictly better than B for a hand-constructed pair)

2. **Hard-invariant checker rejects pre-evaluation**
   - [ ] Rule 1 (forward-only edges): any rendered backward edge causes rejection, not a score
   - [ ] Rule 2 (topological X): any node whose x-position contradicts its topological layer causes rejection
   - [ ] Rule 7 (determinism): rendering the same genome on the same DAG twice produces byte-identical layout output; mismatch causes rejection
   - [ ] Rejected layouts return a structured `{rejected: true, rule, detail}` and never reach the energy function

3. **Fixture loaders**
   - [ ] Tier A loader reads `dag-map/test/models.js` and exposes each model as `{id, dag, routes?, theme, opts}`
   - [ ] Tier B loader reads Liminara pack plans (Radar first) and converts them to the same fixture shape; route field absent
   - [ ] Loaders are pure: same input directory => same fixture list in same order
   - [ ] Missing or malformed fixtures fail loudly with a path and reason, never silently

4. **Single-individual evaluator**
   - [ ] `evaluate(genome, fixture) -> {rejected: true, rule} | {score, terms: {stretch, repel_nn, ...}}`
   - [ ] Score is the weighted sum of the eight terms with a default weight vector at `bench/config/default-weights.json`
   - [ ] Per-term contributions are returned alongside the total
   - [ ] Evaluator is deterministic for fixed `(genome, fixture, weights)` — verified by a round-trip test
   - [ ] All randomness is seeded; the evaluator never reads `Math.random()` directly

5. **Baseline reference floor**
   - [ ] `bench/scripts/baseline.js` scores the current dag-map default parameters (v14/R10 equivalent) over Tier A and Tier B
   - [ ] Output written to `bench/run/baseline/<timestamp>/scores.json` with per-fixture totals and per-term breakdowns
   - [ ] Re-running with the same fixture set and weights produces identical scores

6. **Diagnostic — route fidelity (Tier A only)**
   - [ ] Optional `route_fidelity(genome, fixture)` exists for Tier A fixtures with hand-authored routes
   - [ ] Output is written to a separate diagnostic file, never folded into the energy scalar
   - [ ] Test asserts the diagnostic value never appears in `evaluate` return shape

## Scope

### In Scope

- Eight energy terms in `dag-map/bench/energy/`, unit-tested per term
- Hard-invariant checker for rules 1, 2, 7
- Tier A fixture loader (reuses `dag-map/test/models.js`)
- Tier B fixture loader (Liminara pack plans, Radar first)
- Single-individual evaluator and default weight vector
- Baseline scoring script and reference output
- Route-fidelity diagnostic (Tier A only, separate from fitness)

### Out of Scope

- GA code (population, selection, crossover, mutation) — M-DAGBENCH-02
- Tinder UI, vote log, Bradley-Terry refit — M-DAGBENCH-03
- External corpora (Tier C) — M-DAGBENCH-04
- Worker-thread parallelization — profile here, parallelize in M-02 only if needed
- Any change to dag-map's published API or shipped defaults
- Aesthetic terms beyond the eight named (rules 13-21 inform weights, not new terms here)

## Dependencies

- `dag-map` submodule at current main
- `dag-map/test/models.js` schema stable
- Radar pack plan readable from a Liminara workspace path

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Energy term formulation is wrong and the GA optimizes garbage | High | One ordering test per term against a hand-constructed pair; baseline gives a sanity floor |
| `dag-map` render path is too slow to evaluate populations | Med | Profile baseline script; record per-fixture timings; defer parallelization to M-02 |
| Determinism check fails because of Map-iteration order or floating-point drift | Med | Round-trip test runs render twice; fix sources of nondeterminism here, not later |
| Tier B Radar fixtures change and break baseline reproducibility | Low | Snapshot Radar plan into `bench/fixtures/tier-b/` rather than reading the live pack |

## Test Strategy

- **Per-term unit tests** in `bench/energy/__tests__/<term>.test.js`. node:test or vitest, deterministic, no network.
- **Hand-constructed micro-DAGs** for ordering tests — 3-6 nodes, scores predictable.
- **Invariant rejection tests** construct deliberately bad layouts and assert structured rejection.
- **Round-trip determinism test** scores the same `(genome, fixture)` 10 times and asserts byte-identical results.
- **Baseline regression test** snapshots Tier A per-term breakdowns.

## Deliverables

- `dag-map/bench/energy/` — eight terms, default weights, evaluator
- `dag-map/bench/fixtures/` — Tier A and Tier B loaders + snapshotted Tier B fixtures
- `dag-map/bench/invariants/` — rule 1, 2, 7 checker
- `dag-map/bench/scripts/baseline.js` — reference floor scorer
- `dag-map/bench/run/baseline/<timestamp>/scores.json` — first reference output
- Tracking doc: `work/milestones/tracking/E-DAGBENCH-layout-evolution/M-DAGBENCH-01-tracking.md`

## Validation

- All bench tests pass under `cd dag-map/bench && npm test`
- `dag-map` main package tests still pass (bench is gitignored, must not affect them)
- Baseline script runs to completion on Tier A + Tier B and produces a reference output
- No new dependencies in `dag-map/package.json`; bench-only deps live in `dag-map/bench/package.json`

## References

- `work/epics/E-DAGBENCH-layout-evolution/epic.md`
- `dag-map/test/models.js`
- `dag-map/.scratch/metro-experiments/SUMMARY.txt`
- 21-rule appendix in the epic spec
