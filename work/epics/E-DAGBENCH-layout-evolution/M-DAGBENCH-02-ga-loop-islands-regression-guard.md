---
id: M-DAGBENCH-02-ga-loop-islands-regression-guard
epic: E-DAGBENCH-layout-evolution
status: not started
depends_on: M-DAGBENCH-01-energy-function-corpus-evaluator
---

# M-DAGBENCH-02: GA Loop + Islands + Regression Guard

## Goal

Add a genetic algorithm on top of the M-DAGBENCH-01 evaluator: two-tier genome, one population per `routing_primitive` (island model), seeded RNG, regression guard against per-fixture best-ever scores, and a headless overnight runner that produces an elite gallery of thumbnails. After this milestone, an unattended overnight run improves on the M-01 baseline measured by the energy functional, with no human input.

## Context

M-01 makes the cost function explicit. M-02 makes the search explicit. The GA must be reproducible (seeded), must not collapse modes (regression guard), and must isolate Tier 2 discrete choices into separate populations so a `routing_primitive` flip does not break selection pressure on Tier 1 continuous params.

This milestone explicitly does not include human steering. Success is measured by the energy functional alone. Taste enters in M-03.

## Acceptance Criteria

1. **Two-tier genome**
   - [ ] Tier 1 continuous parameters (~15 fields, full GA): documented in `bench/genome/tier1.js` with min/max/default per field
   - [ ] Tier 2 discrete parameters (`route_extraction`, `routing_primitive`, `convergence_style`): mutation-only, no crossover
   - [ ] Genome serialization round-trips: `parse(serialize(g))` deep-equals `g`
   - [ ] Validation rejects out-of-range Tier 1 values and unknown Tier 2 values with structured errors

2. **Island model per routing primitive**
   - [ ] One population per value of `routing_primitive` (`bezier`, `angular`, `progressive`)
   - [ ] No cross-island migration during selection
   - [ ] Cross-island comparison happens only at reporting time (gallery rendering)
   - [ ] Test: a Tier 2 mutation that changes `routing_primitive` produces an individual that is migrated to the matching island, not retained on its origin

3. **GA operators**
   - [ ] Tournament selection (configurable size, default 3)
   - [ ] Tier 1 crossover (uniform or arithmetic — pick one and document)
   - [ ] Tier 1 Gaussian mutation with per-field sigma
   - [ ] Tier 2 categorical mutation with low rate (default 5%)
   - [ ] Elitism: top N per island carried forward unchanged
   - [ ] All operators consume an explicit seeded PRNG; same seed + same initial population => same generation N

4. **Regression guard**
   - [ ] Per-fixture best-ever score is tracked across the run in `bench/run/<run-id>/best-ever.json`
   - [ ] An individual is rejected from the elite set if it scores worse than 0.9 * best-ever on any single Tier B fixture
   - [ ] Rejection reason is logged with fixture id and offending score
   - [ ] Test: a synthetic individual that wins overall but tanks one fixture is correctly rejected from the elite

5. **Headless overnight runner**
   - [ ] `bench/scripts/run.js --config <path> --seed <int> --generations <n>` runs without TTY
   - [ ] Writes per-generation snapshots to `bench/run/<run-id>/gen-<NNNN>/` (genomes, scores, elite IDs)
   - [ ] Writes thumbnail SVGs of each elite individual on each Tier A fixture to `bench/run/<run-id>/gallery/`
   - [ ] Run is resumable: `--resume <run-id>` continues from the last completed generation
   - [ ] Run terminates cleanly on SIGINT and leaves a consistent on-disk state

6. **Improvement over baseline**
   - [ ] A short reproducible run (small population, ~20 generations, fixed seed) improves mean Tier A energy strictly below the M-01 baseline reference floor
   - [ ] This is asserted by an integration test, not by eyeball

7. **Determinism end-to-end**
   - [ ] Two runs with identical config, seed, and fixture set produce identical generation snapshots and identical elite IDs at every generation

## Scope

### In Scope

- Two-tier genome representation, validation, serialization
- GA operators (selection, crossover, mutation, elitism)
- Island model per routing primitive
- Regression guard against per-fixture best-ever
- Headless runner with resume + clean shutdown
- Per-generation gallery thumbnails
- Optional worker-thread parallelization if M-01 profiling showed it was needed

### Out of Scope

- Tinder UI, pairwise vote log, Bradley-Terry refit — M-DAGBENCH-03
- External corpora (Tier C) — M-DAGBENCH-04
- Gradient refinement of elites
- Any change to dag-map's published defaults
- Cross-island migration during selection (deliberately excluded)

## Dependencies

- M-DAGBENCH-01 complete: evaluator, invariant checker, fixtures, baseline
- `dag-map` render path stable

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Population size and dag-map render speed make overnight runs infeasible | High | Profile in M-01; parallelize across worker threads here if needed |
| Regression guard causes elite set to go empty (over-strict) | Med | Log all rejections; allow guard threshold (default 0.9) to be configurable per run |
| Tier 2 discrete jumps cause large fitness swings that destabilize a population | Med | Island model isolates each routing primitive; mutation rate is low |
| RNG threading leaks `Math.random()` somewhere and breaks determinism | Med | Lint/grep check in test; explicit assertion that the seeded PRNG is used everywhere |
| Resume loses state if interrupted mid-write | Low | Atomic snapshot writes (tmp + rename); document recovery rule |

## Test Strategy

- **Genome unit tests** for serialization, validation, mutation, crossover.
- **Operator tests** with seeded PRNG, asserting determinism and expected distributions on small populations.
- **Island isolation test**: a population mutation that flips `routing_primitive` is migrated; no cross-island leak during selection.
- **Regression guard test** with synthetic best-ever data and a constructed offender.
- **Small-scale reproducibility integration test**: 20 generations, 2 islands, 8 individuals, fixed seed; assert byte-identical generation snapshots across two runs.
- **Improvement assertion**: integration test compares mean Tier A energy of final elite vs M-01 baseline floor; must improve.

## Deliverables

- `dag-map/bench/genome/`
- `dag-map/bench/ga/` — selection, crossover, mutation, elitism, island manager
- `dag-map/bench/regression/` — best-ever tracker, guard
- `dag-map/bench/scripts/run.js` — headless runner with resume
- `dag-map/bench/run/<run-id>/gallery/` — thumbnail output (gitignored)
- Tracking doc: `work/milestones/tracking/E-DAGBENCH-layout-evolution/M-DAGBENCH-02-tracking.md`

## Validation

- All bench tests pass
- Reproducibility test passes twice in a row producing identical artifacts
- A small overnight-equivalent run produces an elite gallery on disk and improves on the baseline floor
- No new dependencies in dag-map main package

## References

- `work/epics/E-DAGBENCH-layout-evolution/epic.md`
- `work/epics/E-DAGBENCH-layout-evolution/M-DAGBENCH-01-energy-function-corpus-evaluator.md`
