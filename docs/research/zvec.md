# zvec — Embedded Vector Database

**Date:** 2026-03-22
**Context:** Evaluating zvec as a candidate vector search backend for Liminara packs that need semantic similarity (Radar, Software Factory, future RAG-dependent packs).

---

## What it is

**zvec** is an in-process vector database from Alibaba, built on their internal Proxima search engine. Apache 2.0. First released December 2025, currently v0.2.1 (March 2026). ~9k GitHub stars.

- **GitHub:** https://github.com/alibaba/zvec
- **Docs:** https://zvec.org/en/

The pitch: "SQLite for vectors." No server, no infrastructure — it embeds directly into your application as a C++ library with language bindings.

---

## Key capabilities

- **In-process architecture** — links into the application, no network hop, no deployment overhead
- **Dense + sparse vectors** — native support for both, queryable in a single call
- **Hybrid search** — vector similarity combined with structured field filters (`"category = 'ai' AND score > 0.8"`)
- **Index types** — HNSW (general-purpose ANN), Flat (brute-force exact), IVF (large-scale)
- **Distance metrics** — Cosine, L2, Inner Product
- **Schema-based collections** — typed fields (string, int, float, bool, binary) with optional inverted indexes
- **Full CRUD** — insert, upsert, delete, delete-by-filter
- **Persistence** — filesystem-backed, survives restarts
- **Platforms** — Linux (x86_64, ARM64), macOS (ARM64)

---

## Elixir integration

A community NIF binding exists on hex.pm:

- **Package:** `{:zvec, "~> 0.2.0"}`
- **Source:** https://github.com/nyo16/zvec_ex
- **Built with:** Fine (Elixir NIF framework from the Nx team)
- **Requirements:** Elixir >= 1.16, CMake >= 3.13, C++17 compiler

Design choices relevant to BEAM compatibility:

- All blocking operations run on **dirty schedulers** (will not block normal schedulers)
- Vectors pass as **raw binaries** — zero-overhead encoding
- Interops with **Nx tensors** via `Nx.to_binary/1`
- Idiomatic API: `{:ok, result}` / `{:error, {code, message}}` tuples

**Maturity caveat:** The Elixir bindings are very new (published 2026-02-23, 1 star). The C++ core has Alibaba behind it, but the Elixir layer would need vetting before depending on it in production.

---

## Comparison to alternatives

| Aspect | zvec | LanceDB | FAISS | pgvector | Qdrant |
|---|---|---|---|---|---|
| Architecture | In-process (C++ NIF) | In-process (Rust) | In-process (C++) | PostgreSQL extension | Client-server |
| Elixir bindings | Yes (hex.pm, NIF) | No native | No native | Yes (via Ecto/Postgrex) | HTTP API only |
| Hybrid search | Yes (field filters) | Yes (SQL-like) | No | Yes (SQL) | Yes (payload filters) |
| Sparse vectors | Yes | No | Limited | No | Yes |
| Persistence | Filesystem | File-based (Lance format) | Optional save/load | PostgreSQL | On-disk |
| CRUD | Full | Insert/remove only | Insert/remove only | Full (SQL) | Full (API) |
| External deps | None | None | None | Needs PostgreSQL | Needs server |
| License | Apache 2.0 | Apache 2.0 | MIT | PostgreSQL | Apache 2.0 |

**LanceDB** (mentioned in [ADJACENT_TECHNOLOGIES.md](ADJACENT_TECHNOLOGIES.md) §8) remains a strong candidate — its file-based Lance format maps cleanly to content-addressed artifacts. But it lacks Elixir bindings, requiring a Python/Node sidecar or port.

**zvec's advantage for Liminara:** native Elixir NIF bindings mean vector search runs in-process on the BEAM, no sidecar needed. This is a meaningful architectural simplification.

---

## How zvec maps to Liminara

### Alignment with core principles

| Principle | Fit |
|---|---|
| Zero external dependencies | Perfect — in-process, no server |
| Content-addressed artifacts | Index files are filesystem artifacts, versionable by hash |
| OTP supervision | NIF runs on dirty schedulers, supervised like any GenServer |
| Event sourcing | Index mutations are ops producing new artifacts; the event log captures what changed |

### Radar pack integration

The Radar pipeline has three vector-dependent stages:

1. **IR3 — Extracted Items:** Embed documents via LLM/model. Store embeddings in a zvec collection for similarity queries. The embedding op is `pure` (or `pinned_env` with model version); the zvec index update is `side_effecting`, producing a new index artifact.

2. **IR4 — Clusters & Rankings:** Semantic deduplication ("have we seen this story before?") and cross-domain connection finding ("this regulatory change is semantically close to this market trend") are ANN queries against the index. These are `pure` ops: `(query_vector, index_artifact) → [(doc_hash, similarity_score)]`.

3. **Novelty detection:** Compare new item embeddings against historical index. Items far from all existing clusters are novel. zvec's hybrid search (vector similarity + metadata filters like `date > last_run`) makes this a single query.

### Other pack opportunities

- **Software Factory** — agent memory / retrieval for discovery mode. "Find past decisions semantically similar to the current context."
- **Report Compiler** — semantic deduplication of source material before synthesis.
- **ProcessMining pack** — embedding process traces for anomaly detection (traces that are geometrically distant from the cluster are anomalies).

### How it would be modeled as Liminara ops

```
radar.embed_items       : pinned_env op  (item artifacts → embedding artifacts)
radar.index_update      : side_effecting op  (old_index + new_embeddings → new_index artifact)
radar.semantic_search   : pure op  (query_vector + index artifact → ranked results)
radar.semantic_dedup    : pure op  (item_index + vector_index → deduplicated item set)
```

The vector index itself is a **Pack-managed reference artifact** registered via `init/0`, updated by collection runs. Each version is content-addressed. Analysis runs reference a specific version — the index at a point in time.

---

## Build complexity

Adding zvec introduces:

- C++ compilation dependency (CMake, C++17 compiler) — already acceptable if Rustler NIFs are on the roadmap for the house compiler
- ~5 minute first build (subsequent builds are instant)
- Platform constraint: Linux/macOS only (no Windows, but Liminara targets Linux anyway)

---

## Recommendation

**Not needed now.** The Radar pack's MVP plan (RSS + HN ingestion, TF-IDF clustering, LLM summarization) doesn't require vector search.

**Worth adopting when:** Radar moves beyond TF-IDF to embedding-based clustering and semantic deduplication. At that point, zvec is the strongest candidate for Liminara because:

1. Native Elixir bindings — no sidecar architecture
2. In-process — no infrastructure to deploy
3. Hybrid search — combines vector similarity with metadata filters in one query
4. Filesystem persistence — index files are content-addressable artifacts

**Risk to watch:** The Elixir bindings are a single-maintainer community project. If zvec adoption is decided, consider contributing to or forking `zvec_ex` to ensure maintenance.

---

*See also:*
- *[ADJACENT_TECHNOLOGIES.md](ADJACENT_TECHNOLOGIES.md) §8 — Vector Databases in the Radar Pipeline*
- *[01_Radar.md](../domain_packs/01_Radar.md) — Radar pack spec*
