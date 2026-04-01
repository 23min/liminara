---
id: M-RAD-01-pack-config-fetch
epic: E-11-radar
status: not started
depends_on: E-10-port-executor
---

# M-RAD-01: Pack + Source Config + Fetch

## Goal

Create the Radar Pack module, a source configuration system with ~47 sources, and Python fetch ops that retrieve content from RSS feeds and web pages. After this milestone, `mix radar.run` fetches all enabled sources and stores raw responses as artifacts.

## Context

This is the first Radar milestone and the first real Pack built on the runtime. It depends on E-10 (Port Executor) for Python op execution.

The source list is curated in `work/epics/E-11-radar/sources.md` — 47 sources across 7 categories (AI/LLM, Elixir/BEAM, EU sustainability, workflow engines, HN keyword feeds, Nordic tech, aggregators).

Relevant existing code:
- `Liminara.Pack` behaviour — `runtime/apps/liminara_core/lib/liminara/pack.ex`
- `Liminara.Plan` — `runtime/apps/liminara_core/lib/liminara/plan.ex`
- `Liminara.Op` behaviour — `runtime/apps/liminara_core/lib/liminara/op.ex`

## Acceptance Criteria

1. `Liminara.Radar` module exists in a new umbrella app `liminara_radar` (at `runtime/apps/liminara_radar/`), implementing `Liminara.Pack` behaviour:
   - `id/0` returns `:radar`
   - `version/0` returns `"0.1.0"`
   - `ops/0` returns list of op modules
   - `plan/1` accepts a source config and returns a `Liminara.Plan` with one fetch node per enabled source + a `normalize_all` collector node

2. Source configuration is loaded from a YAML or JSON file:
   - Each source has: `id`, `name`, `type` (rss/web/api), `url`, `feed_url` (optional), `tags`, `enabled`
   - Config file lives at `runtime/apps/liminara_radar/priv/sources.json` (derived from `sources.md`)
   - A `Radar.Config` module loads and validates the config

3. `Radar.Ops.FetchRss` op (Python, `:side_effecting`):
   - Fetches an RSS/Atom feed URL via `feedparser` + `httpx`
   - Returns normalized items: list of `{title, url, summary, published, source_id}`
   - Handles feed errors gracefully (timeout, HTTP 4xx/5xx, parse error → empty list + error field)
   - Supports ETag/Last-Modified conditional fetching (stores headers as part of output for next run)

4. `Radar.Ops.FetchWeb` op (Python, `:side_effecting`):
   - Fetches a web page URL via `httpx`
   - Extracts content via `trafilatura`
   - Returns items found on the page (may need page-specific extraction hints from config)
   - Same error handling as FetchRss

5. `Radar.Ops.CollectItems` op (Elixir, `:pure`):
   - Takes outputs from all fetch nodes
   - Merges into a single list of items
   - Deduplicates by URL (exact match — vector dedup is M-RAD-02)
   - Attaches source metadata (source_id, tags)
   - Produces a `source_health` artifact: per-source item counts, errors, status

6. `mix radar.run` mix task:
   - Loads source config
   - Calls `Radar.plan(config)` to build the plan
   - Starts a run via `Run.Server`
   - Prints summary: N sources fetched, M items collected, errors

7. Source health tracking:
   - Each run produces a `source_health` artifact with per-source metrics
   - Items fetched, fetch errors/warnings, HTTP status codes

8. **Persistent storage paths configured:**
   - Dev config: `runtime/data/store/` (artifacts), `runtime/data/runs/` (events/decisions/plans)
   - `runtime/data/` added to `.gitignore`
   - Test config unchanged (uses `tmp_dir` per test)
   - No more `System.tmp_dir!()` fallback in dev — data survives container restarts

9. Python dependencies declared in `runtime/python/pyproject.toml`:
   - `feedparser` (RSS/Atom parsing)
   - `httpx` (HTTP client)
   - `trafilatura` (HTML extraction)

## Tests

### Config tests (Elixir)
- Load a valid config file → returns list of source structs
- Load config with missing required fields → returns validation error
- Filter config by `enabled: true` → only enabled sources returned
- Filter config by tags → correct subset returned

### Pack tests (Elixir)
- `Radar.plan(config)` with 3 enabled sources → plan has 3 fetch nodes + 1 collect node
- `Radar.plan(config)` with 0 enabled sources → plan has only collect node (empty input)
- Plan validates successfully (no cycles, no dangling refs)
- RSS sources get `FetchRss` op, web sources get `FetchWeb` op

### Fetch op tests (Python — pytest)
- FetchRss with a valid RSS feed → returns list of items with expected fields
- FetchRss with invalid URL → returns empty list + error field
- FetchRss with malformed XML → returns empty list + error field
- FetchWeb with a valid HTML page → returns extracted text content
- FetchWeb with timeout → returns empty list + error field

### CollectItems tests (Elixir)
- Merge 3 source outputs → single list with all items + source metadata attached
- Duplicate URLs across sources → deduplicated (keep first seen)
- One source returned error → items from other sources still collected, health shows error
- All sources empty → empty list, health shows all zeros

### Integration test
- Run `Radar.plan(config)` with 2-3 test sources through Run.Server
- Verify: fetch events logged, artifacts stored, collect node produces merged list

## Technical Notes

### Umbrella app structure

```
runtime/apps/liminara_radar/
  lib/liminara/radar.ex            # Pack module
  lib/liminara/radar/config.ex     # Source config loading/validation
  lib/liminara/radar/ops/
    fetch_rss.ex                   # Elixir op module → delegates to Python
    fetch_web.ex                   # Elixir op module → delegates to Python
    collect_items.ex               # Elixir op (pure, inline)
  priv/sources.json                # Source configuration
  test/
```

### Python ops

```
runtime/python/src/ops/
  radar_fetch_rss.py               # feedparser + httpx
  radar_fetch_web.py               # httpx + trafilatura
```

### Plan structure

```
fetch_rss_hn_elixir ──┐
fetch_rss_anthropic ──┤
fetch_web_efrag ──────┼── collect_items
   ...                │
fetch_rss_lobsters ───┘
```

Each fetch node has a literal input `{:literal, source_config}` with the source's URL, type, etc. The collect node has `{:ref, node_id}` inputs from all fetch nodes.

### RSS testing approach

For deterministic tests, use fixture XML files (not live HTTP). The Python fetch ops should accept a `test_mode` flag or be mockable at the HTTP level. In integration tests, use a tiny local HTTP server or pre-recorded fixtures.

## Out of Scope

- Embedding, dedup, clustering (M-RAD-02, M-RAD-03)
- LLM calls of any kind
- Web UI for viewing results (M-RAD-04)
- Scheduling (M-RAD-04)
- Source discovery or auto-curation

## Dependencies

- E-10 Port Executor (M-PORT-01 + M-PORT-02) must be complete
- `uv` available in environment
- Python >= 3.12 with feedparser, httpx, trafilatura installable

## Open Questions

- **Source config format:** JSON vs YAML vs TOML? JSON is simplest (no extra parser), but YAML is more readable for 47 sources. Leaning JSON since Elixir has `Jason` built-in.
- **RSS test fixtures:** Should we record live feeds once and use as fixtures, or craft minimal XML? Suggest recorded fixtures for realism.
