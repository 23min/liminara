---
id: M-EVOLVE-04-evolution-run-benchmark
epic: E-EVOLVE-layout-pipeline
status: not started
depends_on: [M-EVOLVE-03]
---

# M-EVOLVE-04: Evolution Run + Benchmark Comparison

## Goal

Run the GA with the extended genome to evolve the best strategy combination, then produce a benchmark report comparing the evolved pipeline against dagre, ELK, and the pre-evolution baseline.

## Context

After M-EVOLVE-03, the GA can evolve both continuous parameters and algorithmic strategy selection. This milestone runs the actual evolution, analyzes results, and produces the comparison report. This is the payoff milestone — does evolutionary algorithm configuration actually improve dag-map?

## Acceptance Criteria

1. **Evolution run**
   - [ ] At least one GA run with 200+ generations using the extended genome
   - [ ] Run uses all Tier A + Tier B fixtures for fitness evaluation
   - [ ] Run produces snapshots with strategy selections in the genome
   - [ ] Elite individuals use non-default strategies (evolution actually explored the strategy space)

2. **Benchmark report**
   - [ ] `make bench-report --elite <run-dir>` produces comparison against dagre and ELK
   - [ ] Report includes all three tiers (A, B, C) — 2,000+ fixtures
   - [ ] Report shows the evolved strategy combination and all parameters
   - [ ] Win/loss/tie counts reported honestly per E-DAGBENCH constraints

3. **Quality improvement**
   - [ ] Evolved pipeline improves dag-map vs dagre win rate on Tier C external benchmarks
   - [ ] Crossing count on Tier A fixtures measurably lower with evolved strategies than with defaults
   - [ ] Energy scores on Tier A + B measurably lower than pre-evolution baseline

4. **Before/after comparison**
   - [ ] Side-by-side report: default strategies vs evolved strategies on the same fixtures
   - [ ] Gallery of SVG thumbnails for Tier A fixtures under both configurations
   - [ ] The evolved strategy combination is documented: which strategy per slot, which parameters

5. **Reproducibility**
   - [ ] The evolution run is fully seeded and reproducible
   - [ ] The benchmark report is reproducible from the evolved elite snapshot

## Scope

### In Scope

- Running the GA with extended genome (200+ generations)
- Benchmark report generation with evolved elite
- Before/after comparison (defaults vs evolved)
- Documenting the evolved strategy combination

### Out of Scope

- Shipping evolved parameters/strategies as dag-map defaults
- Tinder UI steering (optional, not required)
- Further algorithmic improvements beyond what M-EVOLVE-02/03 implemented
- Performance optimization of the evolution pipeline

## Dependencies

- M-EVOLVE-03 complete (extended genome, all strategies wired)
- External corpora fetched (`make fetch-corpora`)

## Deliverables

- GA run snapshots under `bench/run/`
- Benchmark report: `report.md` + `report.json` + gallery
- Before/after comparison document
- Summary in tracking doc with final win/loss numbers
