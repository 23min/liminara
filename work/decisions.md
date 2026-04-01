# Decisions

Shared decision log. Active decisions that guide implementation choices.

## D-2026-04-01-001: A2UI as secondary observation UI
**Status:** active
**Context:** Needed lightweight mobile-friendly observation alongside Phoenix LiveView
**Decision:** Use ex_a2ui (A2UI v0.9) as a secondary renderer; LiveView remains primary
**Consequences:** A2UI provider maps Observation.Server state to components; debug renderer works for dev; production needs a proper Lit/React renderer

## D-2026-04-01-002: dag-map lineGap defaults to 0 for auto-discovered routes
**Status:** active
**Context:** v0.3 lineGap feature caused squiggly bezier curves on auto-discovered routes
**Decision:** lineGap defaults to 0 for auto-discovered routes; non-zero only for consumer-provided routes
**Consequences:** Metro-map aesthetic preserved; parallel line separation available when routes are explicit

## D-2026-04-01-003: Python ops via :port for Radar pack
**Status:** active
**Context:** Python ecosystem (feedparser, trafilatura, sentence-transformers) is vastly richer for web scraping and NLP
**Decision:** Radar ops execute as Python processes via Elixir :port; Elixir handles orchestration
**Consequences:** Need Python toolchain in deployment; uv for package management; ops communicate via JSON over stdio

## D-2026-04-01-004: Compliance packs sequence after Radar
**Status:** active
**Context:** VSME, DPP, EUDR all have enforcement deadlines 2026-2027
**Decision:** Radar first (validates Pack pattern + LLM decisions), then VSME (validates compliance pattern), then DPP/EUDR
**Consequences:** EIC Accelerator pitch by Sep 2026 needs Radar running; compliance packs follow

## D-2026-04-01-005: Port executor uses raw Erlang Ports, not libraries
**Status:** active
**Context:** Need Python op execution for Radar. Evaluated ErlPort (abandoned), Porcelain (leaks), Rambo (stale), Pythonx (GIL kills concurrency), MuonTrap (not for bidirectional JSON). OTP documentation and community converge on raw Ports.
**Decision:** Use `Port.open/2` with `{packet, 4}` length-framed JSON. Zero Elixir dependencies. Spawn-per-call for V1; upgrade to NimblePool long-running workers for V2 when spawn overhead matters. Include correlation IDs from day 1.
**Consequences:** No library risk. Protocol is future-proof (V2 is internal swap). Python side uses a generic dispatcher (`liminara_op_runner.py`).

## D-2026-04-01-006: Local embeddings via model2vec, not API
**Status:** active
**Context:** Evaluated API options (Voyage AI, Jina, Gemini, Cohere) and local options (model2vec, fastembed, sentence-transformers). Local avoids API keys and costs. model2vec (potion-base-8M) is 152MB installed, no PyTorch, no ONNX, 6.6ms for 100 items. Quality sufficient for news dedup (threshold ~0.35 cleanly separates duplicates).
**Decision:** Use model2vec with `minishlab/potion-base-8M` (256 dims). Swappable via EmbeddingProvider protocol — can upgrade to fastembed or Voyage AI if quality insufficient.
**Consequences:** Zero API cost for embeddings. Works offline. Dedup thresholds lower than transformer models (0.55 dup / 0.35 ambiguous vs 0.92/0.7). Model auto-downloads on first run (~59MB).

## D-2026-04-01-007: Tavily as primary search provider for serendipity
**Status:** active
**Context:** Evaluated 8 search APIs. Bing dead, Google CSE sunsetting 2027. Tavily: 1,000 free queries/month, no CC, AI-agent optimized, returns LLM-ready content. Exa.ai (neural search) is a complement option for later.
**Decision:** Tavily as primary search provider. Swappable via SearchProvider protocol. Exa.ai deferred to future enhancement.
**Consequences:** Free at our volume (~450 queries/month). Search call is a recordable op — provider is captured in decision record.

## D-2026-04-01-009: Persistent storage paths, not tmp
**Status:** active
**Context:** Default storage falls back to `System.tmp_dir!()` — data lost on reboot/container restart. Radar needs cumulative LanceDB history and persistent run artifacts.
**Decision:** Configure explicit paths in dev config: `runtime/data/store/` (artifacts), `runtime/data/runs/` (events/decisions/plans). LanceDB at `runtime/data/radar/lancedb/`. Gitignore `runtime/data/`. Tests continue using `tmp_dir`.
**Consequences:** Data persists across dev sessions. Production paths (`/var/lib/liminara/`) configured when deployment epic arrives.

## D-2026-04-01-008: GenServer scheduler, not system cron
**Status:** active
**Context:** Need daily run trigger for Radar. Options: system cron (simple, invisible), GenServer + :timer (portable, testable, visible), Oban (Phase 6).
**Decision:** GenServer scheduler supervised by OTP. Configurable daily trigger. Prepares the path for Oban migration in Phase 6 — the run-triggering logic becomes the Oban worker's `perform/1` body.
**Consequences:** Portable across macOS/devcontainer/production. Testable in ExUnit. Visible in observation UI. No persistence — recalculates next run on restart.
