---
id: M-RAD-03-cluster-rank-render
epic: E-11-radar
status: not started
depends_on: M-RAD-02-extract-embed-dedup
---

# M-RAD-03: Cluster + Rank + Render

## Goal

Group deduplicated items into topic clusters, rank by novelty, generate per-cluster summaries via Haiku, and render a complete HTML briefing artifact. After this milestone, `mix radar.run` produces a self-contained briefing document.

## Context

M-RAD-02 delivers a deduplicated list of items with embeddings. This milestone adds the intelligence layer: clustering reveals themes, ranking surfaces what matters, LLM summaries provide narrative, and the renderer produces a readable briefing.

This is the milestone where Radar becomes genuinely useful — the output is a daily briefing, not raw data.

## Acceptance Criteria

1. `Radar.Ops.Cluster` op (Python, `:pure`):
   - Takes deduplicated items with embeddings
   - Groups into topic clusters using embedding-based clustering (HDBSCAN or k-means)
   - Each cluster gets: `{cluster_id, label (auto-generated from top terms), items, centroid}`
   - Unclustered outliers form a "miscellaneous" cluster
   - Number of clusters is data-driven (not hardcoded) — HDBSCAN preferred for this

2. `Radar.Ops.Rank` op (Python, `:pure`):
   - Ranks items within each cluster by novelty score
   - Novelty score based on: distance from historical centroid (newer angle = higher), source diversity (item covered by multiple sources = important), recency
   - Ranks clusters themselves by: max novelty in cluster, cluster size, tag relevance
   - Returns ordered clusters with ordered items within each

3. `Radar.Ops.Summarize` op (Python, `:recordable`):
   - For each cluster: sends the cluster's items (titles + clean text) to Haiku
   - Prompt: "Summarize these related items into 2-3 paragraphs. Highlight what's new, why it matters, and any conflicting viewpoints."
   - Returns: `{cluster_id, summary_text, key_takeaways: [string]}`
   - Each summary is a recorded decision
   - Runs one LLM call per cluster (not per item)

4. `Radar.Ops.ComposeBriefing` op (Elixir, `:pure`):
   - Takes ranked clusters with summaries
   - Assembles into a structured briefing: metadata (date, run_id, source count, item count), ordered clusters with summaries + item links, source health summary
   - Outputs a briefing data structure (map/JSON)

5. `Radar.Ops.RenderHtml` op (Elixir, `:pure`):
   - Takes briefing data structure
   - Renders self-contained HTML document (inline CSS, no external deps)
   - Sections: header (date, stats), cluster sections (summary + ranked items with links), footer (source health, run metadata)
   - Clean, readable typography — this is a daily reading document
   - Stores HTML as an artifact

6. Updated plan in `Radar.plan/1`:
   - Full pipeline: fetch → collect → normalize → embed → dedup → llm_dedup → merge → cluster → rank → summarize → compose → render_html

7. `mix radar.run` now outputs:
   - Summary: N sources, M items fetched, K items after dedup, C clusters, run_id
   - Path to the HTML briefing artifact

## Tests

### Cluster tests (Python — pytest)
- 10 items about 3 distinct topics → 3 clusters + correct assignment
- All items on same topic → 1 cluster
- 1 item → 1 cluster with 1 item
- Empty input → empty clusters
- Items with pre-computed embeddings (no API calls in tests)

### Rank tests (Python — pytest)
- Items with varying novelty scores → correct ordering within cluster
- Clusters ranked by max novelty → most novel cluster first
- Identical novelty scores → stable ordering (deterministic)
- Single item cluster → rank is trivial

### Summarize tests (Elixir + Python)
- Mock Haiku response → summary text extracted correctly
- 3 clusters → 3 LLM calls, 3 decisions recorded
- Replay → decisions used, no LLM calls
- Empty cluster list → no LLM calls, no summaries

### ComposeBriefing tests (Elixir)
- Clusters + summaries → briefing structure with all expected fields
- Date, run_id, stats are correct
- Clusters are in ranked order
- Items within clusters are in ranked order

### RenderHtml tests (Elixir)
- Briefing data → valid HTML string
- HTML contains: date header, cluster sections, item links, source health
- Self-contained (no external CSS/JS references)
- Empty briefing → renders with "no items found" message

### Integration test
- Full pipeline with test fixtures (known items, known clusters)
- Verify: HTML artifact is stored, readable, contains expected cluster summaries
- Verify: replay produces identical HTML (summaries from recorded decisions)

## Technical Notes

### Clustering approach

HDBSCAN is preferred over k-means:
- Does not require specifying cluster count upfront
- Handles noise (outlier items become "miscellaneous")
- Works well with embedding spaces
- Python package: `hdbscan` or `scikit-learn` (has HDBSCAN since v1.3)

Fallback: if HDBSCAN is problematic, use k-means with silhouette score to pick k.

### Python ops

```
runtime/python/src/ops/
  radar_cluster.py        # HDBSCAN clustering
  radar_rank.py           # Novelty scoring + ranking
  radar_summarize.py      # Haiku cluster summaries
```

### HTML rendering

Use Elixir's `EEx` or simple string interpolation. The HTML template is embedded in the op module. No Phoenix dependency — this is a pure artifact renderer.

### Haiku prompt design

```
You are summarizing a cluster of related news items for a daily intelligence briefing.

Items in this cluster:
{for each item: title, source, date, first 500 chars of text}

Write 2-3 paragraphs summarizing:
1. What happened / what's new
2. Why it matters
3. Any conflicting viewpoints or nuances

Also provide 2-3 key takeaways as bullet points.

Respond in JSON: {"summary": "...", "key_takeaways": ["...", "..."]}
```

### Cost estimate for this milestone

At ~50 sources, expect 5-15 clusters per run:
- Haiku at ~$0.25/1M input tokens, ~$1.25/1M output tokens
- ~5-15 summarize calls × ~2K tokens input each = ~10-30K input tokens = ~$0.003-0.008
- Output ~500 tokens each = ~2.5-7.5K output tokens = ~$0.003-0.009
- **Total per run: ~$0.01-0.02** for summaries

## Out of Scope

- Web UI for viewing briefings (M-RAD-04 — HTML artifact is viewable via file:// or artifact viewer)
- Scheduling (M-RAD-04)
- Serendipity exploration (M-RAD-05)
- Email/Slack delivery
- Interactive briefing (click-to-expand, search within briefing)

## Dependencies

- M-RAD-02 (deduplicated items with embeddings)
- `ANTHROPIC_API_KEY` env var for Haiku summaries
- Python packages: `scikit-learn` (HDBSCAN), `numpy`
