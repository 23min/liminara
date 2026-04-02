# M-RAD-03: Cluster + Rank + Render — Tracking

**Started:** 2026-04-02
**Branch:** `milestone/M-RAD-03`
**Spec:** `work/epics/E-11-radar/M-RAD-03-cluster-rank-render.md`

## Acceptance Criteria

- [x] AC1: Radar.Ops.Cluster (Python, pure) — HDBSCAN clustering, outlier handling, data-driven cluster count
- [~] AC2: Radar.Ops.Rank (Python, pure) — novelty scoring, cluster + item ranking
  - **ISSUE:** `datetime.now()` in rank op violates `:pure` determinism (cache hits unsafe)
  - **ISSUE:** `historical_centroid` passed as empty `[]` — distance-from-history scoring is inert
  - **ISSUE:** source diversity is cluster-level (same bonus for all items), not per-item cross-source coverage as spec describes
- [x] AC3: Radar.Ops.Summarize (Python, recordable) — Haiku per-cluster summaries, decisions recorded
  - **NOTE:** multi-decision replay is broken at runtime level (Decision.Store overwrites per node_id) — tracked in E-11c
- [x] AC4: Radar.Ops.ComposeBriefing (Elixir, pure) — assemble briefing data structure
  - **ISSUE:** `run_id` is `{:literal, "placeholder"}` — not the actual run ID
- [x] AC5: Radar.Ops.RenderHtml (Elixir, pure) — self-contained HTML briefing artifact
- [x] AC6: Updated Radar.plan/1 — full pipeline through render
- [~] AC7: mix radar.run outputs summary + HTML path
  - **ISSUE:** live run failed — not yet debugged

## Test Summary

- Elixir radar: 45 tests, 0 failures (32 pack/compose/render + 13 existing)
- Python: 58 tests, 0 failures (38 existing + 7 cluster + 7 rank + 6 summarize)

## Known Shortcuts

- `historical_centroid` is `{:literal, Jason.encode!([])}` — always empty, novelty-from-history scoring does nothing
- `run_id` in compose_briefing is `{:literal, "placeholder"}` — not the real run ID
- Source diversity scoring gives same bonus to every item in a cluster (cluster-level, not per-item)
- Rank op calls `datetime.now()` but is declared `:pure` — determinism violation
- Multi-decision replay (summarize produces N decisions per node) is a runtime-level issue (E-11c)

## Notes

- scikit-learn >= 1.3 for HDBSCAN (approved)
- model2vec 256d embeddings from M-RAD-02
- Haiku for cluster summaries (safe default without API key)
