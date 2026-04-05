---
id: E-11-radar
phase: 5
status: complete
depends_on: E-10-port-executor
---

# E-11: Radar Pack

## Goal

Build a daily intelligence briefing pipeline that fetches ~50 configured sources, extracts and deduplicates items, clusters by topic, ranks by novelty, and renders a briefing viewable in the existing web UI. Every nondeterministic judgment (LLM dedup checks, cluster summaries) is recorded as a decision, making briefings fully replayable and auditable.

## Context

Radar (omvärldsbevakning) is the first domain pack built on the Liminara runtime. It validates the full stack: Pack behaviour, Python ops via :port (E-10), recordable decisions with LLM calls, vector-based deduplication, and the observation UI for viewing results.

Sources span AI/LLM orchestration, Elixir/BEAM ecosystem, EU sustainability/compliance, workflow engines, and Nordic tech — all adjacent to Liminara's domain. The source list is maintained in a separate config file (`work/epics/E-11-radar/sources.md`).

Radar is designed for daily use by the project owner as a real intelligence tool, not a demo. It should produce genuinely useful briefings from day one.

## Current Status

- Core Radar Pack delivery is complete: M-RAD-01 through M-RAD-04 shipped the pack, fetch pipeline, extract/embed/dedup flow, clustering/ranking/rendering, web UI, and scheduler.
- Replay correctness follow-on M-RAD-06 is also complete and closes the replay/run-id gaps referenced in older Radar tracking notes.
- Serendipity exploration is not part of the completed E-11 scope. It now lives in its own deferred follow-on epic, `E-11b Radar Serendipity`, until dynamic DAG support lands.

## Scope

### In Scope

- Radar Pack module implementing `Liminara.Pack` behaviour (`id/version/ops/plan`)
- Source configuration: ~50 sources with enabled flag, tags, type (rss/api/web), health tracking
- Python ops via :port: RSS/HTTP fetch (feedparser + httpx), text extraction (trafilatura), embedding (local model2vec), vector dedup (LanceDB), LLM calls (Anthropic Haiku)
- Dedup strategy: vector similarity against LanceDB history (>0.92 skip, <0.7 keep, 0.7-0.92 LLM check as recordable decision)
- Clustering by topic (embedding-based), ranking by novelty
- LLM cluster summaries (recordable decisions via Haiku)
- HTML briefing artifact (compose + render)
- LiveView briefing page (`/radar/briefings/:run_id`)
- GenServer scheduler (configurable daily trigger, OTP-supervised)
- Source health tracking: per-source contribution metrics, cull recommendations
- Replay-correct execution with recorded decisions and stable briefing reproduction (M-RAD-06)

### Out of Scope

- Email delivery (future — web UI only for v1)
- Slack integration (future)
- Multi-user / authentication
- Oban / Postgres (Phase 6 — GenServer scheduler for now)
- Deployment to production server (future — runs locally/devcontainer)
- Custom ML models or fine-tuning
- Source discovery automation (manual curation for v1)
- Serendipity exploration / discovery expansion (moved to E-11b Radar Serendipity after dynamic DAG support)

## Constraints

- Depends on E-10 (Port Executor) for Python op execution
- LLM provider: Anthropic (Haiku for extraction/dedup/summaries) — user has API key
- Embedding provider: local model2vec selected in M-RAD-02 (no paid embedding API on the current path)
- Python dependencies managed via `uv` (runtime/python/)
- All LLM and search calls must be recordable decisions (replayable)
- Budget awareness: current E-11 cost is dominated by Haiku calls and stays within the original <$1/day target

## Success Criteria

- [x] `mix radar.run` executes the full pipeline: fetch -> extract -> embed -> dedup -> cluster -> rank -> summarize -> render
- [x] Briefing is viewable at `/radar/briefings/:run_id` in the existing web UI
- [x] Every LLM judgment (dedup check, cluster summary) is recorded as a decision
- [x] Replaying a run with recorded decisions produces the same briefing (no LLM calls)
- [x] Dedup correctly identifies duplicate stories across sources (>0.92 similarity -> skip)
- [x] Source health is tracked: which sources contribute items, which are stale/empty
- [x] GenServer scheduler triggers runs on a configurable daily schedule
- [x] The pipeline handles source failures gracefully (one broken RSS feed doesn't block the run)

Deferred follow-on: M-RAD-05 serendipity now lives in `work/epics/E-11b-radar-serendipity/` and is not required for E-11 completion.

## Risks & Open Questions

Most of the original E-11 delivery risks were resolved during implementation. The remaining notes below are retained as core Radar delivery context.

| Risk / Question | Impact | Mitigation |
|----------------|--------|------------|
| Embedding provider availability/pricing | Resolved | M-RAD-02 selected local model2vec, removing paid embedding API dependency from the current path. |
| LanceDB maturity for production use | Med | Embedded, no server needed. If issues arise, swap for simple JSON + numpy cosine similarity. |
| Source RSS feeds breaking/changing | Med | Per-source error handling, health tracking, graceful degradation. Broken source = warning, not failure. |
| Haiku quality for cluster summarization | Med | Test during M-RAD-03. Can upgrade to Sonnet for summaries if Haiku is insufficient. Cost impact is small. |
| API cost creep with 50 sources daily | Low | Budget tracking per run. Local embeddings removed the largest variable cost; current spend is mainly Haiku usage. |

## Milestones

| ID | Title | Summary | Depends on | Status |
|----|-------|---------|------------|--------|
| M-RAD-01 | Pack + source config + fetch | Radar Pack module, source config (~50 sources), RSS/HTTP fetch ops via :port, raw response artifacts, source health tracking | E-10 | complete |
| M-RAD-02 | Extract + embed + dedup | Normalize (trafilatura), local model2vec embeddings, LanceDB vector store, dedup pipeline, ambiguous-zone LLM check (recordable) | M-RAD-01 | complete |
| M-RAD-03 | Cluster + rank + render | Cluster by embeddings, rank by novelty, Haiku summaries per cluster (recordable), compose briefing, render HTML artifact | M-RAD-02 | complete |
| M-RAD-04 | Web UI + scheduler | LiveView briefing page, observation UI integration, GenServer scheduler, source health dashboard | M-RAD-03 | complete |
| M-RAD-06 | Replay correctness | Replay-safe artifact identity, deterministic briefings, environment recording, and truth-model cleanup for Radar runs | M-RAD-04 | complete |

## DAG Structure

### Core Pipeline (completed E-11 plus M-RAD-06 correctness follow-on)

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

## Cost Notes

The original planning estimate assumed paid embedding APIs. Current implemented scope is cheaper and narrower:

| Component | Current E-11 run | Monthly (daily) |
|-----------|------------------|-----------------|
| HTTP fetching | ~free | ~free |
| Text extraction | ~free (local trafilatura) | ~free |
| Embeddings (local model2vec) | ~free | ~free |
| Dedup LLM checks (Haiku, ambiguous only) | small, volume-dependent | small, volume-dependent |
| Cluster summarization (Haiku) | small, volume-dependent | small, volume-dependent |
| **Total current run cost** | **dominated by Haiku usage** | **well below the original <$1/day target in normal operation** |

## References

- Design plan: `docs/analysis/15_Radar_Pack_Plan.md`
- Live sequencing truth: `work/roadmap.md`
- Follow-on epic: `work/epics/E-11b-radar-serendipity/epic.md`
- Source list: `work/epics/E-11-radar/sources.md`
- Decision D-2026-04-01-003: Python ops via :port
- Decision D-2026-04-01-004: Radar before compliance packs
- Decision D-020: dynamic DAGs and serendipity deferment after VSME
- Pack behaviour: `runtime/apps/liminara_core/lib/liminara/pack.ex`
- Executor: `runtime/apps/liminara_core/lib/liminara/executor.ex`
