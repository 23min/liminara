---
id: M-RAD-05-serendipity
epic: E-11b-radar-serendipity
status: not started
depends_on: E-16-dynamic-dags
---

# M-RAD-05: Serendipity Exploration

## Deferred Status

This milestone is intentionally deferred, not abandoned.

- Epic home: `E-11b Radar Serendipity`
- Deferral reason: D-2026-04-02-020 moved serendipity after VSME because it depends on dynamic DAG support (`E-16`).
- Core Radar prerequisite: E-11 is complete and provides the ranked-item pipeline that serendipity extends.
- Implementation intent to preserve: select the most novel items, explore related coverage and counterpoints, follow outbound links, merge relevant discoveries back into the briefing, and recommend promising new permanent sources for human review.

## Goal

Add automated discovery to the Radar pipeline: for the most novel items, explore the web for related stories, follow links, find counter-narratives, and evaluate newly discovered sources. Every judgment is a recorded decision, making exploration fully replayable. After this milestone, Radar doesn't just report - it discovers.

## Context

This is an enhancement milestone. The core pipeline (M-RAD-01 through M-RAD-04) already produces useful briefings from configured sources. M-RAD-06 later closed the replay correctness gaps in that core path. Serendipity adds a layer of automated curiosity on top: it takes the most interesting items and explores further.

This is the feature that differentiates Radar from an RSS reader. It also validates Liminara's decision recording for multi-step LLM-driven exploration.

Functional dependency remains the ranked-item pipeline introduced in M-RAD-03, but the execution-sequencing dependency is now `E-16 Dynamic DAGs`, which is why this milestone lives in `E-11b` rather than the closed `E-11` epic.

## What Must Not Be Lost

- Exploration is selective, not broad crawling: it starts from top novel items and outliers only.
- Query generation, relevance judgments, counterpoint selection, and source-evaluation calls are recorded decisions.
- Exploration is budget-capped and allowed to stop gracefully with partial results.
- Discovered items merge back into the main briefing pipeline before clustering.
- New-source discovery is advisory only: the system recommends candidate sources, but a human still curates the permanent watchlist.

## Acceptance Criteria

1. `Radar.Ops.SelectForExploration` op (Elixir, `:pure`):
   - Takes deduplicated items with novelty scores (from rank_novel in M-RAD-02/03)
   - Selects top-N most novel items for exploration (N configurable, default 3)
   - Also selects outliers: items with high novelty but low cluster membership
   - Total items selected capped by budget (configurable max items, default 5)

2. `Radar.Ops.ExploreWeb` op (Python, `:recordable`):
   - For each selected item: sends to Haiku with context
   - Haiku generates 2-3 search queries related to the item
   - Executes queries via Tavily search API
   - Returns: `{queries_generated, search_results, query_decisions}`
   - The generated queries and "why this query" rationale are recorded decisions

3. `Radar.Ops.FollowLinks` op (Python, `:side_effecting`):
   - For each selected item: follows 1-2 outbound links from the original article
   - Fetches and extracts text via httpx + trafilatura
   - Returns: `{followed_urls, extracted_items}`
   - Side-effecting: always re-fetches on replay (links may change)

4. `Radar.Ops.FindCounterpoint` op (Python, `:recordable`):
   - For selected items (configurable: all or top-1): sends to Haiku
   - Prompt: "What's the opposing view or counter-narrative to this story?"
   - Haiku generates 1 search query for the counter-narrative
   - Executes via Tavily
   - Returns: `{counterpoint_query, search_results, decision}`
   - Query + rationale are recorded decisions

5. `Radar.Ops.EvaluateDiscoveries` op (Python, `:recordable`):
   - Takes all discovered items (from web search + link following)
   - Embeds them (reuses embedding provider from M-RAD-02)
   - Scores relevance via embedding similarity to the original item
   - For ambiguous relevance: Haiku judges "Is this relevant to the briefing?"
   - Returns: `{relevant_items, rejected_items, decisions}`

6. `Radar.Ops.EvaluateNewSources` op (Python, `:recordable`):
   - For each newly discovered URL domain that isn't in the source config:
   - Haiku evaluates: "Is this a source worth adding to the permanent watchlist?"
   - Returns: `{recommended_sources: [{url, domain, rationale}], decisions}`
   - Recommendations are informational - human reviews and adds to config manually

7. **Budget enforcement:**
   - Total Tavily API calls per run capped (configurable, default 15)
   - Total Haiku calls for exploration capped (configurable, default 20)
   - If budget exceeded mid-exploration: stop gracefully, return partial results
   - Run's cost tracking artifact includes exploration costs

8. **Pipeline integration:**
   - Exploration runs after dedup/rank_novel, before clustering
   - Discovered items are merged with known items before clustering
   - Discovered items tagged with `{discovered_via: :web_search | :link_follow | :counterpoint}`
   - Source evaluation recommendations appear in the briefing's footer section

9. Updated plan in `Radar.plan/1`:
   - When serendipity is enabled in config: adds exploration nodes between rank_novel and cluster
   - When disabled: pipeline is identical to M-RAD-03

## Tests

### SelectForExploration tests (Elixir)
- 20 items with varying novelty -> top 3 selected
- Budget cap of 2 -> only 2 selected even if 3 qualify
- All items equal novelty -> stable selection (deterministic)
- Empty input -> empty selection

### ExploreWeb tests (Python - pytest)
- Mock Haiku -> generates search queries
- Mock Tavily -> returns search results
- Queries and rationale recorded as decisions
- Replay: uses recorded queries, still calls Tavily (search results are side-effecting)

### FollowLinks tests (Python - pytest)
- Mock HTTP -> fetches and extracts text from links
- Broken link -> skipped, logged
- No outbound links -> empty result

### FindCounterpoint tests (Python - pytest)
- Mock Haiku -> generates counterpoint query
- Mock Tavily -> returns counter-narrative results
- Decision recorded with rationale

### EvaluateDiscoveries tests (Python - pytest)
- Discovered items with high relevance -> kept
- Discovered items with low relevance -> rejected
- Ambiguous items -> Haiku judgment recorded
- Empty discoveries -> empty result

### EvaluateNewSources tests (Python - pytest)
- New domain found -> Haiku evaluates, returns recommendation
- Known domain (in source config) -> skipped
- Multiple items from same new domain -> evaluated once

### Budget tests
- Set budget to 5 Tavily calls -> exploration stops after 5
- Set budget to 0 -> no exploration at all
- Verify cost tracking artifact includes exploration costs

### Integration test
- Full pipeline with serendipity enabled, test fixtures
- Verify: discovered items appear in final briefing tagged as discoveries
- Verify: new source recommendations appear in briefing footer
- Verify: replay uses recorded decisions for query generation, but re-fetches web content

## Technical Notes

### Python ops

```
runtime/python/src/ops/
  radar_explore_web.py
  radar_follow_links.py
  radar_find_counterpoint.py
  radar_evaluate_discoveries.py
  radar_evaluate_new_sources.py
```

### Tavily integration

```python
from tavily import TavilyClient

client = TavilyClient(api_key=os.environ["TAVILY_API_KEY"])
results = client.search(query, max_results=5)
```

The `SearchProvider` protocol (same pattern as `EmbeddingProvider`):
```python
class SearchProvider(Protocol):
    def search(self, query: str, max_results: int = 5) -> list[SearchResult]: ...
```

### Exploration DAG (per explored item)

```
selected_item -> explore_web -> evaluate_discoveries
              -> follow_links -> evaluate_discoveries
              -> find_counterpoint -> evaluate_discoveries
                                          ↓
                                  evaluate_new_sources
```

Since exploration is per-item and items are independent, exploration nodes for different items can run in parallel.

### Haiku prompt examples

**Query generation:**
```
Given this news item, generate 2-3 web search queries to find:
1. Related stories from other sources
2. Deeper analysis or background

Item: {title}
Content: {first 500 chars}

Respond in JSON: {"queries": [{"query": "...", "rationale": "..."}]}
```

**Counterpoint:**
```
Given this news item, what is the opposing view or counter-narrative?
Generate 1 search query to find this perspective.

Item: {title}
Content: {first 500 chars}

Respond in JSON: {"query": "...", "rationale": "..."}
```

**Source evaluation:**
```
A new source was discovered during exploration:
Domain: {domain}
Sample content: {first 300 chars}
Found via: {how it was discovered}

Is this source worth adding to a daily intelligence watchlist for topics:
{user's configured tags}?

Respond in JSON: {"recommend": true/false, "rationale": "..."}
```

## Out of Scope

- Automated source config updates (recommendations are advisory only)
- Multi-hop exploration (follow links from followed links)
- Image/video content analysis
- Real-time exploration (exploration runs within the daily batch)

## Dependencies

- E-11 core Radar pipeline
- E-16 Dynamic DAGs
- `TAVILY_API_KEY` env var
- `ANTHROPIC_API_KEY` env var
- Python package: `tavily-python`