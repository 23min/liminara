---
id: E-11-radar
phase: 5
status: not started
depends_on: E-10-port-executor
---

# E-11: Radar Pack

## Goal

Build a daily intelligence briefing pipeline that fetches ~50 configured sources, extracts and deduplicates items, clusters by topic, ranks by novelty, and renders a briefing viewable in the existing web UI. Every nondeterministic judgment (LLM dedup checks, cluster summaries) is recorded as a decision, making briefings fully replayable and auditable.

## Context

Radar (omvärldsbevakning) is the first domain pack built on the Liminara runtime. It validates the full stack: Pack behaviour, Python ops via :port (E-10), recordable decisions with LLM calls, vector-based deduplication, and the observation UI for viewing results.

Sources span AI/LLM orchestration, Elixir/BEAM ecosystem, EU sustainability/compliance, workflow engines, and Nordic tech — all adjacent to Liminara's domain. The source list is maintained in a separate config file (`work/epics/E-11-radar/sources.md`).

Radar is designed for daily use by the project owner as a real intelligence tool, not a demo. It should produce genuinely useful briefings from day one.

## Scope

### In Scope

- Radar Pack module implementing `Liminara.Pack` behaviour (`id/version/ops/plan`)
- Source configuration: ~50 sources with enabled flag, tags, type (rss/api/web), health tracking
- Python ops via :port: RSS/HTTP fetch (feedparser + httpx), text extraction (trafilatura), embedding (API), vector dedup (LanceDB), LLM calls (Anthropic Haiku)
- Dedup strategy: vector similarity against LanceDB history (>0.92 skip, <0.7 keep, 0.7-0.92 LLM check as recordable decision)
- Clustering by topic (embedding-based), ranking by novelty
- LLM cluster summaries (recordable decisions via Haiku)
- HTML briefing artifact (compose + render)
- LiveView briefing page (`/radar/briefings/:run_id`)
- GenServer scheduler (configurable daily trigger, OTP-supervised)
- Source health tracking: per-source contribution metrics, cull recommendations
- Serendipity exploration (enhancement milestone): web search, link following, counterpoint, source evaluation
- Swappable providers: embedding (TBD, decide during M-RAD-02), search (Tavily primary)

### Out of Scope

- Email delivery (future — web UI only for v1)
- Slack integration (future)
- Multi-user / authentication
- Oban / Postgres (Phase 6 — GenServer scheduler for now)
- Deployment to production server (future — runs locally/devcontainer)
- Custom ML models or fine-tuning
- Source discovery automation (manual curation for v1)

## Constraints

- Depends on E-10 (Port Executor) for Python op execution
- LLM provider: Anthropic (Haiku for extraction/dedup/summaries) — user has API key
- Embedding provider: TBD — decide during M-RAD-02 (no OpenAI key; evaluate Voyage AI, Jina, Google Gemini, or Cohere)
- Search provider: Tavily (1,000 free queries/month, no CC required, AI-agent optimized)
- No local compute for embeddings — must use API-based provider
- Python dependencies managed via `uv` (runtime/python/)
- All LLM and search calls must be recordable decisions (replayable)
- Budget awareness: target <$1/day for API costs at 50 sources

## Success Criteria

- [ ] `mix radar.run` executes the full pipeline: fetch → extract → embed → dedup → cluster → rank → summarize → render
- [ ] Briefing is viewable at `/radar/briefings/:run_id` in the existing web UI
- [ ] Every LLM judgment (dedup check, cluster summary) is recorded as a decision
- [ ] Replaying a run with recorded decisions produces the same briefing (no LLM calls)
- [ ] Dedup correctly identifies duplicate stories across sources (>0.92 similarity → skip)
- [ ] Source health is tracked: which sources contribute items, which are stale/empty
- [ ] GenServer scheduler triggers runs on a configurable daily schedule
- [ ] The pipeline handles source failures gracefully (one broken RSS feed doesn't block the run)
- [ ] Serendipity exploration (M-RAD-05) discovers relevant content via web search with budget cap

## Risks & Open Questions

| Risk / Question | Impact | Mitigation |
|----------------|--------|------------|
| Embedding provider availability/pricing | High | TBD during M-RAD-02. Multiple options (Voyage, Jina, Gemini, Cohere). Provider is swappable. |
| LanceDB maturity for production use | Med | Embedded, no server needed. If issues arise, swap for simple JSON + numpy cosine similarity. |
| Source RSS feeds breaking/changing | Med | Per-source error handling, health tracking, graceful degradation. Broken source = warning, not failure. |
| Haiku quality for cluster summarization | Med | Test during M-RAD-03. Can upgrade to Sonnet for summaries if Haiku is insufficient. Cost impact is small. |
| API cost creep with 50 sources daily | Low | Budget tracking per run. Embeddings are the main cost — estimate during M-RAD-02 provider selection. |
| Tavily free tier changes | Low | Search provider is swappable. Brave and Serper are fallbacks. |

## Milestones

| ID | Title | Summary | Depends on | Status |
|----|-------|---------|------------|--------|
| M-RAD-01 | Pack + source config + fetch | Radar Pack module, source config (~50 sources), RSS/HTTP fetch ops via :port, raw response artifacts, source health tracking | E-10 | not started |
| M-RAD-02 | Extract + embed + dedup | Normalize (trafilatura), embed (API, provider TBD), LanceDB vector store, dedup pipeline, ambiguous-zone LLM check (recordable) | M-RAD-01 | not started |
| M-RAD-03 | Cluster + rank + render | Cluster by embeddings, rank by novelty, Haiku summaries per cluster (recordable), compose briefing, render HTML artifact | M-RAD-02 | not started |
| M-RAD-04 | Web UI + scheduler | LiveView briefing page, observation UI integration, GenServer scheduler, source health dashboard | M-RAD-03 | not started |
| M-RAD-05 | Serendipity exploration | Web search (Tavily), follow links, counterpoint search, source evaluation. All recordable. Budget cap. *(Enhancement)* | M-RAD-03 | not started |

## DAG Structure

### Core Pipeline (M-RAD-01 through M-RAD-04)

```
init_config
    ├── fetch_rss_1
    ├── fetch_rss_2
    ├── fetch_api_1
    ├── ...
    └── fetch_rss_N
           │
      normalize_all
           │
       embed_all
           │
    dedup_vs_history ─── (0.7-0.92?) ─── llm_dedup_check [recordable]
           │
       rank_novel
           │
      cluster_all
           │
       rank_final
           │
    ┌──────┼──────┐
    │      │      │
 summarize_1  summarize_2  summarize_3  [recordable]
    │      │      │
    └── compose_briefing ──┘
           │
      render_html
```

### With Serendipity (M-RAD-05)

```
    rank_novel
        │
   ┌────┼────┐
   │    │    │
explore_1 explore_2 explore_3  [recordable]
follow_1  counter_2 follow_3   [recordable/side_effecting]
   │    │    │
   └── evaluate_all ──┘        [recordable]
        │
   evaluate_new_sources        [recordable]
        │
   cluster_all  (merges known + discovered items)
```

## Dedup Strategy

```
New item embedding
       ↓
Cosine similarity vs LanceDB history
       ↓
  > 0.92  →  DUPLICATE (skip, log)
  0.7-0.92 →  LLM CHECK (recordable): "Same story?" → merge or keep
  < 0.7   →  NEW (keep, add to history)
```

## Source Health Tracking

Each run produces a source health artifact:
- Items fetched per source
- Items surviving dedup per source
- Items in final briefing per source
- Fetch errors/timeouts
- Running averages across last N runs

Sources with sustained zero contribution are flagged for review. Manual cull via config edit.

## Cost Estimate

| Component | Per run (50 sources) | Monthly (daily) |
|-----------|---------------------|-----------------|
| HTTP fetching | ~free | ~free |
| Text extraction | ~free (local trafilatura) | ~free |
| Embeddings (API) | ~$0.01-0.05 | ~$0.30-1.50 |
| Dedup LLM checks (Haiku, ambiguous only) | ~$0.02 | ~$0.60 |
| Cluster summarization (Haiku) | ~$0.05 | ~$1.50 |
| Serendipity search (Tavily free tier) | $0 | $0 |
| **Total per run** | **~$0.08-0.12** | **~$2.40-3.60** |

## References

- Design plan: `docs/analysis/15_Radar_Pack_Plan.md`
- Source list: `work/epics/E-11-radar/sources.md`
- Decision D-2026-04-01-003: Python ops via :port
- Decision D-2026-04-01-004: Radar before compliance packs
- Pack behaviour: `runtime/apps/liminara_core/lib/liminara/pack.ex`
- Executor: `runtime/apps/liminara_core/lib/liminara/executor.ex`
