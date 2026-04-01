# M-RAD-02: Extract + Embed + Dedup — Tracking

**Started:** 2026-04-01
**Branch:** `milestone/M-RAD-02`
**Spec:** `work/epics/E-11-radar/M-RAD-02-extract-embed-dedup.md`

## Acceptance Criteria

- [x] AC1: Embedding provider: model2vec (local, 256d, no API) + EmbeddingProvider protocol + mock provider
- [x] AC2: Radar.Ops.Normalize (Python, pure) — HTML strip, deterministic IDs, full_text support
- [x] AC3: Radar.Ops.Embed (Python, pinned_env) — model2vec default, swappable provider
- [x] AC4: Radar.Ops.Dedup (Python, pure) — 3-tier with configurable thresholds (0.55/0.35 for model2vec)
- [x] AC5: Radar.Ops.LlmDedupCheck (Python, recordable) — Haiku, safe default without API key
- [x] AC6: LanceDB vector store — cumulative history, new items added per run
- [x] AC7: Updated Radar.plan/1 — fetch → collect → normalize → embed → dedup → llm_dedup → merge
- [x] AC8: Dedup statistics artifact (total, new, ambiguous, duplicate counts)

## Test Summary

- Elixir radar: 26 tests, 0 failures
- Python: 38 tests, 0 failures (11 runner + 7 fetch + 6 normalize + 8 embed/dedup + 6 llm_dedup)

## Notes

- model2vec `potion-base-8M`: 256 dims, 59MB model, 6.6ms/100 items, no PyTorch/ONNX
- Dedup thresholds lower than transformer models (0.55/0.35 vs 0.92/0.7) due to static embedding model
- LanceDB `list_tables()` replaces deprecated `table_names()`
- LLM dedup defaults to "keep" when no ANTHROPIC_API_KEY — safe fallback
