# Domain Pack: Radar / Omvärldsbevakning

**Status:** Draft  
**Last updated:** 2026-03-02  
**Pack ID:** `radar.omvarldsbevakning`

---

## 1. Purpose and value

Continuously monitor a curated set of sources (RSS, websites, APIs like Hacker News), detect novelty, cluster themes, and produce briefings with provenance.

This pack is intentionally the **first prototype**: it exercises snapshotting, caching, nondeterministic LLM decisions, and publishing gates without requiring complex CAD/compilers.

### Fit with the core runtime

Radar is a “compiler-shaped” pipeline: *raw sources → snapshots → normalized docs → extracted items → ranked clusters → briefing artifacts*.
It also serves as a proving ground for long-running schedules (“agent fleet” style) by turning each scheduled tick into an **episode Run** with durable artifacts.

### Non-goals

- Be a general-purpose web crawler at internet scale.
- Replace dedicated threat intel / market intel SaaS.
- Guarantee perfect novelty detection; the goal is explainable, tunable ranking.

---

## 2. Pack interfaces

This pack integrates with the core via:

- **Schemas / IR artifacts** (versioned).
- **Op catalog** (determinism class + side-effect policy).
- **Graph builder** (plan DAG → execution DAG expansion).
- **A2UI views** (optional, but recommended for debugging).

---

## 3. IR pipeline

The pack is expressed as *compiler-like passes* (even if the workload is “agentic”). Each pass produces an artifact IR that is inspectable, cacheable, and replayable.

### Source Plan (`IR0`)

Resolved list of sources, fetch policies, rate limits, credentials references, and parse adapters selected for this run.

**Artifact(s):**
- `radar.source_plan.v1`

### Source Snapshots (`IR1`)

Immutable snapshots of external inputs (HTML, RSS XML, JSON API payloads). This is the key move to make downstream runs replayable.

**Artifact(s):**
- `radar.source_snapshot.v1`

**Notes:**
- Store raw bytes + content-type + fetch metadata (ETag/Last-Modified, status, timing).

### Normalized Documents (`IR2`)

Cleaned, extracted main content (e.g. Readability-like), canonical URLs, deduplicated texts, and metadata.

**Artifact(s):**
- `radar.normalized_doc.v1`

### Extracted Items (`IR3`)

Entity + topic extraction, citations to source spans, embeddings (optional), and candidate 'items' for clustering and ranking.

**Artifact(s):**
- `radar.item.v1`
- `radar.item_index.v1`

### Clusters & Rankings (`IR4`)

Cluster assignments, novelty scores, importance scores, and rationale traces.

**Artifact(s):**
- `radar.cluster_set.v1`
- `radar.ranking.v1`

### Briefing (`IR5`)

Generated human-readable briefing (Markdown/HTML/PDF) with links back to source snapshots and rationales.

**Artifact(s):**
- `radar.briefing_md.v1`
- `radar.briefing_pdf.v1`

**Notes:**
- LLM outputs must be stored as decision records or as embedded artifacts with hashes.

---

## 4. Op catalog (core-executed contract)

Each Op must declare determinism and side-effects (see core spec).

- **`radar.resolve_sources`** — *Pure deterministic*, *no side-effects*
  - Expand source lists (feeds, site maps, config), validate schema.
  - Inputs: `radar.config.v1`
  - Outputs: `radar.source_plan.v1`
- **`radar.fetch_snapshot`** — *Deterministic w/ pinned env*, *side-effect*
  - Fetch external URLs/APIs and store snapshots. Side effect is *captured* into artifacts; must be idempotent per (url, etag, time bucket).
  - Inputs: `radar.source_plan.v1`
  - Outputs: `radar.source_snapshot.v1`
- **`radar.normalize`** — *Pure deterministic*, *no side-effects*
  - Normalize raw snapshots to canonical doc form (strip boilerplate, extract text).
  - Inputs: `radar.source_snapshot.v1`
  - Outputs: `radar.normalized_doc.v1`
- **`radar.extract_items`** — *Nondeterministic but recordable*, *no side-effects*
  - Use LLM or heuristics to extract items/entities; store decision record for LLM path.
  - Inputs: `radar.normalized_doc.v1`
  - Outputs: `radar.item.v1`, `radar.item_index.v1`
- **`radar.cluster_rank`** — *Pure deterministic*, *no side-effects*
  - Cluster and rank items (can be embedding-based but deterministic with pinned model+seed).
  - Inputs: `radar.item_index.v1`
  - Outputs: `radar.cluster_set.v1`, `radar.ranking.v1`
- **`radar.summarize_briefing`** — *Nondeterministic but recordable*, *no side-effects*
  - Generate briefing narrative and sections; store model output as decision record.
  - Inputs: `radar.cluster_set.v1`, `radar.ranking.v1`
  - Outputs: `radar.briefing_md.v1`
- **`radar.publish`** — *Side-effecting*, *side-effect*
  - Deliver briefing (email/slack/web) with idempotency key. Always gated in production.
  - Inputs: `radar.briefing_md.v1`
  - Outputs: `radar.delivery_receipt.v1`

---

## 5. Decision records and replay

This pack produces/consumes decision records for nondeterministic steps:

- **Extraction decision**: LLM outputs for extraction/classification, plus tool-call traces.
  - Stored as: `decision.llm_output.v1`
  - Used for: Exact replay and diffing across runs.
- **Briefing narrative**: LLM-generated briefing sections (including citations to item IDs).
  - Stored as: `decision.llm_output.v1`
  - Used for: Exact replay; also supports selective refresh of narrative only.
- **Human curation overrides (optional)**: Manual pin/unpin of sources, cluster merges/splits, thresholds.
  - Stored as: `decision.override.v1`
  - Used for: Controlled editorial workflow.

---

## 6. A2UI / observability

Recommended A2UI surfaces:

- Source browser (with snapshot previews and fetch metadata).
- Cluster explorer (items, novelty score breakdown, 'why did this rank').
- Briefing editor with decision-record injection (accept/redo sections).
- Run diff view: what changed and why (new snapshots vs new decisions).

---

## 7. Executor and tool requirements

This pack may require external executors (ports/containers/remote workers).

- HTTP fetcher executor (can be in-BEAM with Finch/Req or external for sandboxing).
- Optional embedding executor (GPU/CPU external).
- LLM executor (provider adapter; supports prompt caching if available).

---

## 8. MVP plan (incremental, testable)

- Support RSS + Hacker News API ingestion into snapshots.
- Deterministic normalization and simple clustering (TF-IDF or embeddings).
- LLM summarization (cheap model) with decision recording.
- A2UI run view + cluster explorer + 'redo summary' gate.
- Daily schedule as fleet deployment that emits 1 run/day.

---

## 9. Should / shouldn’t

### Should

- Snapshot all external inputs before any LLM work.
- Separate extraction and summarization into different Ops to localize nondeterminism.
- Keep per-run costs bounded (budget caps; abort early if exceeded).

### Shouldn’t

- Don’t stream raw full-text of every doc into LLM context; rely on IR + citations.
- Don’t allow 'publish' to run without a gate in early phases.

---

## 10. Risks and mitigations

- **Risk:** Prompt injection via fetched content
  - **Why it matters:** Radar reads untrusted web pages; injected instructions can leak secrets or cause unsafe tool use.
  - **Mitigation:** Treat web content as data; isolate; strict tool allowlists; never include secrets in prompts; sanitize HTML; separate 'read' vs 'act' ops.
- **Risk:** Novelty scoring becomes a black box
  - **Why it matters:** Users lose trust if ranking can't be explained.
  - **Mitigation:** Store feature contributions; show rationale; allow user tuning and overrides.
- **Risk:** Cost creep
  - **Why it matters:** Even 'cheap' models can become expensive with broad ingestion.
  - **Mitigation:** Budgeting per run; incremental processing; cache; summarize only top-K clusters.

---

## Appendix: Related work and competitive tech

- [Feedly](https://feedly.com/) — RSS/news reader.
- [Feedly AI](https://feedly.com/ai) — AI-assisted topic tracking.
- [Inoreader](https://www.inoreader.com/) — RSS reader with filtering/search.
- [Readwise Reader](https://readwise.io/read) — Read-it-later + RSS.
- [Hacker News API](https://github.com/HackerNews/API) — Official HN JSON API.

### Vector search candidates

When Radar moves beyond TF-IDF to embedding-based clustering and semantic deduplication (IR3/IR4), an in-process vector database will be needed. Current best candidate:

- **[zvec](https://github.com/alibaba/zvec)** — Alibaba's embedded vector database (C++/Proxima). Has Elixir NIF bindings on hex.pm (`{:zvec, "~> 0.2.0"}`). In-process, no server, hybrid search (vector + field filters), dirty-scheduler-safe. Fits the "zero external dependencies" principle. Full evaluation: [docs/research/zvec.md](../research/zvec.md).
- [LanceDB](https://lancedb.com/) — file-based embedded vector DB (Rust). No Elixir bindings; would require a sidecar.
- [pgvector](https://github.com/pgvector/pgvector) — PostgreSQL extension. Only if Postgres is already present for Oban.
