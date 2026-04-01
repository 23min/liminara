# Radar Pack — Design Plan

## Overview

Radar (omvärldsbevakning) is a daily intelligence briefing pipeline. It fetches configured sources, extracts and deduplicates items, explores serendipitous discoveries, clusters by topic, and delivers a ranked briefing with full provenance.

**What makes it different from an RSS reader:** Serendipity exploration (web search for related stories, follow links, find counter-narratives), decision recording (every judgment is replayable), cumulative learning (today's discovery becomes tomorrow's known source), and full auditability ("why did this item appear in my briefing?").

## Architecture: Elixir + Python

- **Elixir** — orchestration, Pack module, scheduling, event sourcing, observation UI
- **Python ops** (via `:port`) — source fetching, text extraction, embeddings, LLM calls, vector store

### Python libraries (solved problems, not reinventing)

| Concern | Library | Why |
|---------|---------|-----|
| RSS/Atom parsing | `feedparser` | Battle-tested, handles every broken feed |
| HTML → clean text | `trafilatura` | Mozilla Readability-class extraction |
| HTTP client | `httpx` | Async, retries, connection pooling |
| Embeddings | `sentence-transformers` or embedding API | Local or API-based |
| Vector store | LanceDB | Embedded, no server, Python-native |
| Near-duplicate detection | Cosine similarity on embeddings | No LLM needed for 95% of cases |
| Web search | Brave Search API or SerpAPI | For serendipity exploration |
| LLM calls | Anthropic/OpenAI SDK | Structured output (JSON mode) |

## DAG Structure

### Stage 1: Known sources (automated, cheap)

```
fetch_rss_1 ──┐
fetch_rss_2 ──┤
fetch_api_1 ──┼── normalize ── embed ── dedup_vs_history ── rank_novel
   ...        │
fetch_rss_N ──┘
```

**Ops:**

| Op | Class | Notes |
|----|-------|-------|
| fetch_rss_*, fetch_api_* | side_effecting | HTTP fetch, ETag caching, raw response stored as artifact |
| normalize | pure | trafilatura extraction, canonical text, cacheable |
| embed | pure | sentence-transformers, cacheable per content hash |
| dedup_vs_history | pure | Vector similarity against LanceDB history. >0.92 = duplicate (skip), <0.7 = new (keep) |
| rank_novel | pure | Novelty score based on distance from existing clusters |

**Ambiguous zone (0.7-0.92 similarity):**

```
dedup_vs_history
       ↓
  similarity 0.7-0.92?
       ↓
  llm_dedup_check (recordable) — "Is this the same story?" → decision recorded
```

LLM only fires for the ambiguous middle. On replay, the recorded decision is used — no LLM call.

### Stage 2: Serendipity exploration (LLM-driven, recorded)

For the top-N most novel items from Stage 1 (budget-controlled: max 3-5 items):

```
top_item_1 → explore_web_1 → follow_links_1 → evaluate_discoveries_1
top_item_2 → explore_web_2 → find_counterpoint_2 → evaluate_discoveries_2
top_item_3 → explore_web_3 → follow_links_3 → evaluate_discoveries_3
                                                       ↓
                                             evaluate_new_sources
```

**Ops:**

| Op | Class | Notes |
|----|-------|-------|
| explore_web | recordable | LLM generates 2-3 search queries. Calls Brave Search. Records queries + results. |
| follow_links | side_effecting | Follows 1-2 outbound links from article. Extracts text. |
| find_counterpoint | recordable | LLM: "What's the opposing view?" Generates search query. Records decision. |
| evaluate_discoveries | recordable | For each discovered item: relevant? Score via embedding + LLM if ambiguous. |
| evaluate_new_sources | recordable | New source found? LLM: "Worth adding to watchlist?" Yes/no + rationale recorded. |

### Stage 3: Synthesis (LLM-driven, recorded)

```
all_items (known + discovered)
       ↓
  cluster ── rank_final
                ↓
  summarize_cluster_1
  summarize_cluster_2
  summarize_cluster_3
       ...
       ↓
  compose_briefing
       ↓
  render_html ── [GATE: publish]
  render_email
```

**Ops:**

| Op | Class | Notes |
|----|-------|-------|
| cluster | pure | Group items by topic via embedding clusters (k-means or HDBSCAN) |
| rank_final | pure | Score by novelty + importance + serendipity bonus |
| summarize_cluster | recordable | LLM: summarize this cluster into 2-3 paragraphs. Decision recorded. |
| compose_briefing | pure | Assemble clusters into ordered briefing with metadata |
| render_html | pure | Markdown/HTML rendering |
| render_email | pure | Short digest: top 5-10 items, 1-line each, link to web UI |
| publish | side_effecting + gate | Human approves → send email + optional Slack webhook |

### Full DAG (~30-50 nodes)

```
                                  ┌── fetch_rss_1
                                  ├── fetch_rss_2
                init_config ──────┼── fetch_api_1
                                  ├── ...
                                  └── fetch_rss_N
                                         │
                                    normalize_all
                                         │
                                    embed_all
                                         │
                                    dedup_vs_history ─── (ambiguous?) ─── llm_dedup_check
                                         │
                                    rank_novel
                                         │
                              ┌──────────┼──────────┐
                              │          │          │
                    explore_web_1  explore_web_2  explore_web_3
                    follow_links_1 find_counter_2 follow_links_3
                              │          │          │
                              └──── evaluate_all ───┘
                                         │
                                  evaluate_new_sources
                                         │
                                    cluster_all
                                         │
                                    rank_final
                                         │
                              ┌──────────┼──────────┐
                              │          │          │
                    summarize_1    summarize_2    summarize_3
                              │          │          │
                              └── compose_briefing ─┘
                                         │
                                    render_html ──── [GATE: publish]
                                    render_email
```

## Deduplication Strategy

```
New item embedding
       ↓
Cosine similarity vs LanceDB history
       ↓
  > 0.92  →  DUPLICATE (skip, log as "seen")
  0.7-0.92 →  LLM CHECK (recordable): "Same story, different source?"
              → yes: merge, keep better source
              → no: keep both, different angle
  < 0.7   →  NEW (keep, add to history)
```

LanceDB stores all item embeddings across runs. Each run queries against the full history. New items are added after the run completes.

## Serendipity: How Discovery Works

### What triggers exploration
- Top-N most novel items from Stage 1 (configurable, default 3-5)
- Items with high novelty score but low cluster membership (outliers)
- Budget cap: max $0.50 per run on serendipity (configurable)

### What exploration does
1. **Web search** — LLM generates 2-3 search queries based on the item. Calls Brave Search API. Results are fetched, extracted, embedded, and scored for relevance.
2. **Follow links** — outbound links from the original article, 1 hop. Same extract/embed/score pipeline.
3. **Counter-narrative** — LLM asks "What's the opposing view?" and generates a search query. Finds alternative perspectives.
4. **Source evaluation** — if a new blog/newsletter/paper is discovered, LLM evaluates: "Worth adding to the permanent watchlist?" Decision recorded with rationale.

### What makes this different from Claude's research
- **Recorded**: every search query, every "this is relevant" judgment is a decision record
- **Replayable**: re-run with same decisions → same briefing. New exploration → see what changed.
- **Cumulative**: discoveries feed the vector store. Today's serendipity becomes tomorrow's context.
- **Auditable**: "Why did this item appear?" → trace to the exploration decision that found it.

## Delivery

### Email (short digest)
```
Subject: Radar Briefing — 2026-04-15

Top items:
1. EU proposes new AI liability framework (3 sources, novelty: HIGH)
2. Swedish battery startup raises €40M Series B (serendipity discovery)
3. DEFRA updates 2026 emission factors (2 sources)
...

Full briefing: https://your-server.com/radar/briefings/run-abc123
```

### Web UI (full briefing)
- New LiveView page: `/radar/briefings/:run_id`
- Or: observation UI run detail page with "briefing" artifact rendered inline
- Shows: all clusters, ranked items, source metadata, novelty scores
- Click any item → see decision records (how it was found, why it ranked here)
- Click any cluster → see summarization decision

### Slack (optional, private)
- Webhook to personal Slack channel
- Same short digest format as email
- Link to web UI for details

## Cost Management

| Component | Cost per run (10 sources) | Cost per run (100 sources) |
|-----------|--------------------------|----------------------------|
| HTTP fetching | ~free | ~free |
| Text extraction | ~free (local) | ~free (local) |
| Embeddings (API) | ~$0.01 | ~$0.05 |
| Embeddings (local) | free | free |
| Dedup LLM checks (ambiguous only) | ~$0.02 | ~$0.10 |
| Serendipity exploration (3-5 items) | ~$0.10 | ~$0.15 |
| Cluster summarization | ~$0.05 | ~$0.20 |
| Briefing composition | ~$0.03 | ~$0.05 |
| **Total per run** | **~$0.20** | **~$0.55** |
| **Monthly (daily runs)** | **~$6** | **~$17** |

Embeddings locally (sentence-transformers) eliminates the API embedding cost entirely.

## Deployment (for long-running use)

**Minimum viable deployment:**
- Hetzner CX31 (~€10/month) — Elixir + Python + LanceDB + Postgres
- Postgres for Oban scheduling + run metadata
- LanceDB embedded (no separate server)
- LLM API key (Anthropic/OpenAI)
- Brave Search API key (free tier: 2000 queries/month)
- Domain + Let's Encrypt SSL for web UI

**Not needed for v1:**
- Kubernetes, Docker Compose (single binary + Python venv)
- Redis, Elasticsearch, separate vector DB server
- Multi-user auth (single user, localhost or basic auth)

## What We Build (in order)

### Phase 1: Minimal Radar (manual runs, 5 sources)
1. Pack module with plan/1
2. Python ops: fetch (httpx + feedparser + trafilatura), normalize, embed
3. LanceDB vector store for dedup
4. LLM extraction op (structured JSON output)
5. Simple compose + render (markdown → HTML)
6. Run via `mix radar_run` (like `mix demo_run`)
7. View in existing observation UI

### Phase 2: Serendipity + quality
8. Serendipity ops: explore_web, follow_links, find_counterpoint
9. Source evaluation + watchlist management
10. Cluster + rank
11. Briefing narrative (LLM summarization per cluster)
12. Email delivery op

### Phase 3: Deployment + scheduling
13. Oban + Postgres for scheduled runs
14. Hetzner deployment
15. Web UI for briefings (LiveView page or artifact renderer)
16. Run diff (what changed since yesterday?)

## Configuration

```elixir
# radar_config.exs
%{
  sources: [
    %{id: "hn", type: :rss, url: "https://news.ycombinator.com/rss", tags: ["tech"]},
    %{id: "arxiv_ai", type: :api, url: "https://export.arxiv.org/api/...", tags: ["research", "ai"]},
    %{id: "eu_commission", type: :rss, url: "https://ec.europa.eu/...", tags: ["policy", "eu"]},
    # ...
  ],
  serendipity: %{
    enabled: true,
    max_items: 5,
    budget_usd: 0.50,
    search_provider: :brave
  },
  delivery: %{
    email: "peter@example.com",
    slack_webhook: nil,  # optional
    web_ui: true
  },
  embedding: %{
    provider: :local,  # or :openai
    model: "all-MiniLM-L6-v2"
  },
  llm: %{
    provider: :anthropic,
    model: "claude-sonnet-4-20250514",
    extraction_model: "claude-haiku-4-5-20251001"  # cheaper for extraction
  }
}
```

## Why Radar Before House Compiler

1. **You're the customer** — immediate feedback loop, daily use
2. **Validates LLM decision recording** — the core differentiator
3. **Validates Python op execution** — proves :port executor works for real
4. **Deployable** — you want to see it running over time
5. **Serendipity is unique** — no RSS reader does recorded, replayable exploration
6. **Feeds EIC pitch** — "working prototype producing real intelligence briefings" = TRL 6
7. **Cost is low** — $6-17/month for daily runs, €10/month hosting
