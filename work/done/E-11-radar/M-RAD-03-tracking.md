# M-RAD-03: Cluster + Rank + Render — Tracking

**Started:** 2026-04-02
**Branch:** `milestone/M-RAD-03`
**Spec:** `work/done/E-11-radar/M-RAD-03-cluster-rank-render.md`

## Acceptance Criteria

- [x] AC1: Radar.Ops.Cluster (Python, pure) — HDBSCAN clustering, outlier handling, data-driven cluster count, post-HDBSCAN merge for over-split clusters (cosine sim > 0.9)
- [x] AC2: Radar.Ops.Rank (Python, pure) — novelty scoring, cluster + item ranking
  - `reference_time` passed as explicit plan input, raises on missing (no wall-clock fallback)
  - `historical_centroid` is empty `[]` — accepted for v1 (see spec Scope Amendment)
  - Source diversity is cluster-level — accepted for v1 (see spec Scope Amendment)
- [x] AC3: Radar.Ops.Summarize (Python, recordable) — Haiku per-cluster summaries, decisions recorded
  - KNOWN: multi-decision replay broken at runtime level (Decision.Store overwrites per node_id) — M-RAD-06
- [x] AC4: Radar.Ops.ComposeBriefing (Elixir, pure) — assemble briefing data structure
  - KNOWN: `run_id` is a plan-time ID (`radar-YYYYMMDDTHHMMSS`), not the runtime's actual run_id. Consistent between dedup and compose, but not the real execution run_id. Threading real run_id through plan execution is M-RAD-06 scope.
- [x] AC5: Radar.Ops.RenderHtml (Elixir, pure) — self-contained HTML briefing artifact
- [x] AC6: Updated Radar.plan/1 — full pipeline through render
- [x] AC7: mix radar.run outputs summary + HTML path
  - FIXED: live run works end-to-end (llm_dedup dict input fix, plan.json persistence, failure diagnostics)

## Test Summary

- Elixir radar: 45 tests, 0 failures
- Python: 64 tests, 0 failures (includes hash-seed independence test + monkeypatched over-split merge test)

## Known Limitations (deferred to M-RAD-06 / Phase 5a)

- Multi-decision replay: summarize produces N decisions per node, but Decision.Store stores one per node_id
- Replay rebuilds a fresh plan instead of loading the stored plan (fresh timestamps drift)
- `run_id` in plan is a plan-time ID, not the runtime execution run_id
- `historical_centroid` is empty (no cross-run history computation yet)
- Source diversity is cluster-level, not per-item

## Notes

- scikit-learn >= 1.3 for HDBSCAN (approved)
- model2vec 256d embeddings from M-RAD-02
- Haiku for cluster summaries (safe default without API key)
- dag-map: CSS classes + cssVars sizing for all text elements (title, subtitle, label, legend, stats)
