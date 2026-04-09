---
id: M-DAGBENCH-04-external-corpora-benchmark-report
epic: E-DAGBENCH-layout-evolution
status: in-progress
depends_on: M-DAGBENCH-03-tinder-ui-bradley-terry-live-steering
---

# M-DAGBENCH-04: External Corpora + Benchmark Report (stretch)

## Goal

Add an external benchmark tier — North DAGs and Random DAGs from graphdrawing.org — and produce a reproducible comparison report against `dagre` and ELK using the M-DAGBENCH-01 energy functional. After this milestone, `make fetch-corpora && make bench-report` produces a transparent score table and a thumbnail gallery, win or lose. This milestone is explicitly stretch: the epic does not block on it.

## Context

Tier A and Tier B drive aesthetic and Liminara-realistic optimization. Tier C tells the wider DAG layout community what the bench thinks of itself. The epic owner has committed to publishing the report regardless of outcome — transparency over score. Beating dagre/ELK is not a primary objective; producing a reproducible, honest comparison is.

## Acceptance Criteria

1. **External corpora fetcher**
   - [ ] `make fetch-corpora` (or `bench/scripts/fetch-corpora.js`) downloads North DAGs and Random DAGs GraphML archives from graphdrawing.org
   - [ ] Downloads land under `bench/corpora/tier-c/` (gitignored)
   - [ ] Fetcher is idempotent: re-running with archives present is a no-op
   - [ ] Fetcher fails gracefully if the network or remote host is unavailable, with a clear error and no partial state
   - [ ] Cited in `bench/corpora/tier-c/README.md`: graphdrawing.org, academic-benchmark license terms, no redistribution

2. **GraphML ingestion into the fixture shape**
   - [ ] GraphML loader converts each external graph into the `{id, dag, theme, opts}` fixture shape used by Tier A/B (no `routes`)
   - [ ] Cyclic graphs are skipped with a logged reason — Tier C is DAGs only
   - [ ] Loader is deterministic: same archive => same fixture list in same order
   - [ ] Sample test fixtures: at least one North DAG and one Random DAG checked into `bench/test/fixtures-tier-c-sample/` for offline tests (a tiny subset, license-permitting)

3. **Adapter layer for dagre and ELK**
   - [ ] `bench/adapters/dagre.js` runs `dagre` on a fixture and returns a layout in the same shape the energy function expects
   - [ ] `bench/adapters/elk.js` runs ELK on a fixture and returns the same shape
   - [ ] Both adapters are deterministic (seeded where applicable) and isolated (failures on one fixture do not abort the run)
   - [ ] Adapter dependencies live in `bench/package.json`, never in `dag-map/package.json`

4. **Comparison report**
   - [ ] `make bench-report` runs the energy functional on (dag-map evolved elite, dagre, ELK) over Tier C and Tier A
   - [ ] Output is `bench/run/report/<timestamp>/report.md` with: per-fixture scores, per-term breakdowns, win/loss/tie counts per layout engine, and links to thumbnails
   - [ ] Output also includes `report.json` with the raw numbers
   - [ ] Thumbnails for each (engine, fixture) pair land under `bench/run/report/<timestamp>/gallery/`
   - [ ] Report is reproducible: re-running with the same fixture set, weights, and elite produces identical numbers

5. **Honesty constraints**
   - [ ] The report includes the dag-map evolved elite's weight vector and run id used to produce it
   - [ ] Fixtures where dag-map loses are listed explicitly, not buried
   - [ ] No per-engine special-casing of the energy function — all three engines are scored against the same weights and the same terms

## Scope

### In Scope

- External corpora fetcher and GraphML loader
- `dagre` and ELK adapters
- Comparison report (Markdown + JSON + gallery)
- Sample fixtures for offline tests (license-permitting)

### Out of Scope

- Hosting or publishing the report anywhere (operator decision per release)
- Beating dagre/ELK as a success criterion
- Any change to dag-map's published API or shipped defaults
- Auto-PR with evolved parameters to dag-map main (forbidden by epic constraints)
- Cyclic graphs (Tier C is DAGs only)

## Dependencies

- M-DAGBENCH-03 complete: an evolved elite exists to compare against
- Network access to graphdrawing.org for the initial fetch (offline tests use checked-in samples)

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| graphdrawing.org archives become unavailable | Med | Cite source; fail gracefully; sample fixtures keep tests offline |
| Adapter mismatches between dagre/ELK output and the energy function's expected layout shape | Med | Adapters convert into the same shape used by dag-map render; tested per-fixture |
| Report results are unflattering and create pressure to tweak weights post-hoc | Med | Honesty constraint: report includes the weight vector and run id; no per-engine tuning |
| ELK is slow or hard to run from Node | Low | Use the JS port; isolate per-fixture failures; allow ELK to be skipped per-fixture with a logged reason |
| License interpretation of redistributing sample fixtures is unclear | Low | Default to fetch-on-demand; only check in samples if license clearly permits |

## Test Strategy

- **Fetcher tests**: idempotency, graceful failure on network error, README presence.
- **GraphML loader tests** against checked-in sample fixtures.
- **Adapter tests**: each adapter produces a layout for a known sample, deterministic across runs.
- **Report integration test**: a tiny end-to-end run (sample fixtures only) produces a report with the expected file shape and stable numbers.
- **Honesty test**: assert the report includes the evolved weight vector and run id, and that loss fixtures are listed.

## Deliverables

- `dag-map/bench/scripts/fetch-corpora.js` (or `Makefile` target)
- `dag-map/bench/loaders/graphml.js`
- `dag-map/bench/adapters/dagre.js`, `dag-map/bench/adapters/elk.js`
- `dag-map/bench/scripts/report.js`
- `dag-map/bench/run/report/<timestamp>/report.md` + `report.json` + `gallery/`
- `dag-map/bench/test/fixtures-tier-c-sample/` (license-permitting)
- Tracking doc: `work/milestones/tracking/E-DAGBENCH-layout-evolution/M-DAGBENCH-04-tracking.md`

## Validation

- All bench tests pass
- `make fetch-corpora` is idempotent and fails cleanly without network
- `make bench-report` produces a complete report including loss fixtures
- No new dependencies in `dag-map/package.json`

## References

- `work/epics/E-DAGBENCH-layout-evolution/epic.md`
- North DAGs: `http://www.graphdrawing.org/data/north-graphml.tgz`
- Random DAGs: `http://www.graphdrawing.org/data/random-dag-graphml.tgz`
