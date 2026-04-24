---
id: M-RAD-02-extract-embed-dedup
epic: E-11-radar
status: complete
depends_on: M-RAD-01-pack-config-fetch
---

# M-RAD-02: Extract + Embed + Dedup

## Goal

Add text normalization, embedding, and vector-based deduplication to the Radar pipeline. After this milestone, fetched items are cleaned, embedded, compared against historical items in a LanceDB vector store, and near-duplicates are filtered out — with ambiguous cases resolved by Haiku (as recorded decisions).

## Context

M-RAD-01 delivers raw fetched items from ~47 sources. This milestone processes those items: normalize text, generate embeddings via an API provider, store embeddings in LanceDB for cross-run history, and apply a three-tier dedup strategy.

Embedding provider is TBD (decision D-2026-04-01-006). This milestone's first task is to evaluate options and select one. The provider must be swappable via a protocol.

## Acceptance Criteria

1. **Embedding provider selected and integrated:**
   - Evaluate available options (Voyage AI, Jina AI, Google Gemini, Cohere) based on: free tier, cost, quality, Python SDK availability
   - Implement an `EmbeddingProvider` protocol in Python with a concrete implementation for the selected provider
   - Record the selection as a decision in `work/decisions.md`

2. `Radar.Ops.Normalize` op (Python, `:pure`):
   - Takes raw fetched items from CollectItems
   - Extracts clean text via trafilatura (for HTML content) or uses summary text (for RSS items with clean summaries)
   - Produces normalized items: `{id, title, clean_text, url, published, source_id, tags}`
   - Deterministic — same input always produces same output (cacheable)

3. `Radar.Ops.Embed` op (Python, `:pinned_env`):
   - Takes normalized items
   - Generates embeddings via the selected API provider
   - Returns items with embeddings attached: `{..., embedding: [float]}`
   - Batches API calls for efficiency (provider SDK typically supports batch)
   - Determinism: `:pinned_env` (same input + same model version → same output, but model updates may change results)

4. `Radar.Ops.Dedup` op (Python, `:pure` for the vector comparison part):
   - Compares each item's embedding against LanceDB history
   - Three-tier classification:
     - Similarity > 0.92 → DUPLICATE — skip, log as "seen"
     - Similarity 0.7–0.92 → AMBIGUOUS — pass to LLM check
     - Similarity < 0.7 → NEW — keep
   - Returns: `{new_items, ambiguous_items, duplicate_items, dedup_stats}`

5. `Radar.Ops.LlmDedupCheck` op (Python, `:recordable`):
   - Takes ambiguous items (0.7–0.92 similarity zone)
   - For each: sends the item + its nearest historical match to Haiku
   - Prompt: "Are these the same story from different sources, or different stories?"
   - Returns decision per item: merge (same story, keep better source) or keep (different angle)
   - Each judgment is a recorded decision (replayable without LLM call)

6. LanceDB vector store:
   - Stores all item embeddings across runs (cumulative history)
   - Schema: `{item_id, embedding, title, url, source_id, run_id, created_at}`
   - New items (passing dedup) are added to the store after the run completes
   - Queryable by cosine similarity
   - Store location: configurable, default `runtime/data/radar/lancedb/`

7. Updated plan in `Radar.plan/1`:
   - Pipeline is now: fetch nodes → collect → normalize → embed → dedup → llm_dedup_check → merge_results
   - `merge_results` combines new items + LLM-approved ambiguous items into final item list

8. Dedup statistics artifact per run:
   - Total items after collection
   - Items classified as: new, ambiguous, duplicate
   - LLM checks performed (count, cost estimate)
   - Items surviving dedup

## Tests

### Normalize tests (Python — pytest)
- HTML content → clean text extracted
- RSS summary (already clean) → passed through
- Empty content → empty string, no crash
- Special characters / encoding → handled correctly

### Embed tests (Python — pytest)
- List of items → embeddings returned with correct dimensions
- Empty list → empty result
- Provider error (rate limit, auth) → graceful error with descriptive message
- Mock provider for unit tests (no real API calls in tests)

### Dedup tests (Python — pytest)
- Item identical to history (sim > 0.92) → classified as duplicate
- Item completely novel (sim < 0.7) → classified as new
- Item in ambiguous zone (sim 0.7–0.92) → classified as ambiguous
- Empty history → all items classified as new
- Empty input → empty results

### LLM dedup check tests (Elixir + Python)
- Ambiguous pair where stories are same → returns "merge" decision
- Ambiguous pair where stories are different angle → returns "keep" decision
- Decision is recorded and can be replayed
- No ambiguous items → op returns immediately with empty decisions

### LanceDB tests (Python — pytest)
- Insert items → query by similarity → returns nearest matches with scores
- Query against empty store → returns no matches
- Insert across multiple "runs" → all items queryable

### Integration test
- Run full pipeline with test fixtures (3-5 sources with known overlapping content)
- Verify: duplicates filtered, ambiguous items sent to LLM check, new items pass through
- Verify: LanceDB updated with new items after run
- Verify: replay uses stored decisions (no LLM call)

## Technical Notes

### Python ops

```
runtime/python/src/ops/
  radar_normalize.py
  radar_embed.py
  radar_dedup.py
  radar_llm_dedup.py
  providers/
    embedding.py          # EmbeddingProvider protocol
    embedding_voyage.py   # or whichever is selected
    llm.py                # Anthropic Haiku wrapper
```

### Embedding provider protocol

```python
class EmbeddingProvider(Protocol):
    def embed(self, texts: list[str]) -> list[list[float]]: ...
    def dimensions(self) -> int: ...
    def model_name(self) -> str: ...
```

Concrete implementation selected during this milestone. Config specifies which provider + API key env var.

### LanceDB schema

```python
import lancedb

db = lancedb.connect("runtime/data/radar/lancedb")
table = db.create_table("items", schema={
    "item_id": "string",
    "embedding": f"vector({dimensions})",
    "title": "string",
    "url": "string",
    "source_id": "string",
    "run_id": "string",
    "created_at": "string"
})
```

### Haiku integration

LLM calls use the Anthropic Python SDK (`anthropic`). The op sends a structured prompt and parses the JSON response. The prompt + response are the decision record.

```python
import anthropic
client = anthropic.Anthropic()  # uses ANTHROPIC_API_KEY env var
```

### Test fixtures

Use pre-computed embeddings in test fixtures to avoid API calls. The embedding provider is mocked in unit tests. Integration tests that touch the real API are gated behind an env flag.

## Out of Scope

- Clustering and ranking (M-RAD-03)
- Briefing composition
- Web UI
- Serendipity exploration (M-RAD-05, now tracked under E-11b Radar Serendipity)
- Source health dashboard (basic health is M-RAD-01; dashboard is M-RAD-04)

## Dependencies

- M-RAD-01 (fetch pipeline must produce items)
- Embedding API key (whichever provider is selected)
- `ANTHROPIC_API_KEY` env var for Haiku calls
- Python packages: `lancedb`, `anthropic`, embedding provider SDK

## Open Questions

- **LanceDB data location:** Should it live in `runtime/data/` (gitignored, local) or be configurable? Suggest `runtime/data/radar/lancedb/` with a config override.
- **Embedding dimensions:** Depends on provider. Most modern models use 384-1536 dimensions. LanceDB schema needs to match.
- **Dedup thresholds:** 0.92 and 0.7 are starting points from the design plan. May need tuning after real-world testing. Should be configurable.
