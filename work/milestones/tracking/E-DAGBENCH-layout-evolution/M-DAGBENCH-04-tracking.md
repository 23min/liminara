# M-DAGBENCH-04 Tracking: External Corpora + Benchmark Report

**Status:** In Progress
**Started:** 2026-04-09
**Branch:** milestone/M-DAGBENCH-04

## Acceptance Criteria

### AC1: External corpora fetcher
- [x] `make fetch-corpora` downloads North DAGs and Random DAGs GraphML archives
- [x] Downloads land under `bench/corpora/tier-c/` (gitignored)
- [x] Fetcher is idempotent: re-running with archives present is a no-op
- [x] Fetcher fails gracefully if network/remote unavailable
- [x] `bench/corpora/tier-c/README.md` cites source and license terms

### AC2: GraphML ingestion into fixture shape
- [x] GraphML loader converts each graph into `{id, dag, theme, opts}` fixture shape
- [x] Cyclic graphs skipped with logged reason
- [x] Loader is deterministic: same archive => same fixture list in same order
- [x] Sample fixtures checked into `bench/test/fixtures-tier-c-sample/`

### AC3: Adapter layer for dagre and ELK
- [x] `bench/adapters/dagre.mjs` runs dagre and returns energy-function-compatible layout
- [x] `bench/adapters/elk.mjs` runs ELK and returns same shape
- [x] Both adapters are deterministic and isolated (per-fixture failures don't abort)
- [x] Dependencies in `bench/package.json` only

### AC4: Comparison report
- [x] `make bench-report` runs energy functional on (dag-map, dagre, ELK) over Tier C + A
- [x] Output: `bench/run/report/<timestamp>/report.md` with scores, breakdowns, win/loss/tie
- [x] Output: `report.json` with raw numbers
- [x] Thumbnails in `bench/run/report/<timestamp>/gallery/`
- [x] Report is reproducible with same inputs

### AC5: Honesty constraints
- [x] Report includes evolved weight vector and run id
- [x] Loss fixtures listed explicitly
- [x] No per-engine special-casing of energy function

## Progress Log

| Date | AC | Note |
|------|----|------|
| 2026-04-09 | — | Milestone started |
| 2026-04-09 | AC1 | Fetcher with idempotency, graceful failure, README. 6 tests. |
| 2026-04-09 | AC2 | GraphML loader + Tier C corpus loader. Sample fixtures. 14 tests. |
| 2026-04-09 | AC3 | dagre and ELK adapters + dag-map adapter. 10 tests. |
| 2026-04-09 | AC4+AC5 | Report generator with honesty constraints. 7 tests. |
