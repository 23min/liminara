# Liminara: Build Plan

**Status:** Living document. Updated as phases complete and priorities shift.
**Last updated:** 2026-03-19

---

## Current phase: Phase 3

---

## Build sequence

### Phase 0: Data model definition (before any code)

**Goal:** Define the on-disk format once. Both the Python SDK and the Elixir runtime implement this model. No ambiguity, no cross-language drift.

**Deliverable:** [11_Data_Model_Spec.md](../analysis/11_Data_Model_Spec.md) — canonical spec for hashing, event log format, artifact storage layout, decision records.

**What's defined:**
- Hash algorithm: SHA-256, encoded as `sha256:{64 lowercase hex chars}`
- Canonical serialization: RFC 8785 JSON (sorted keys, no whitespace, UTF-8)
- Event log: JSONL, hash-chained, append-only
- Artifact storage: filesystem, content-addressed, Git-style sharding
- Decision records: canonical JSON, one file per recordable op execution
- Run seal: event_hash of final event, cryptographic commitment to entire run

**Done when:** Spec reviewed, no open questions about format. Both implementations can target it.

**Status:** Complete.

---

### Phase 1: Python SDK / data model validation

**Goal:** Validate the data model spec by implementing it in Python before the Elixir runtime exists. Changes to the format are cheap now, expensive later. Secondary goal: produce a runnable demo artifact for pitches and funding applications.

**What this is NOT:** A product. The compliance reporting the SDK produces (Article 12 reports, tamper-evidence) is a consequence of Liminara's architecture — event sourcing, content-addressing, decision records. Anyone could build equivalent compliance-only tooling in a weekend. The value is in proving the data model works end-to-end.

**Location:** `integrations/python/`

**What's built:**
- `liminara/` Python SDK: decorators (`@op`, `@decision`), hash chain, event log, artifact store, compliance report generator
- Example 01: raw Python + Anthropic SDK (universality demo)
- Example 02: LangChain RAG + `LiminaraCallbackHandler` (named integration, one-line instrumentation)
- CLI: `liminara list`, `liminara report`, `liminara verify`, `liminara tamper-test`, `liminara diff`
- Docker: runnable in 5 minutes
- Full test suite: output equivalence, completeness, correctness, tamper-evidence, Article 12 report, cache behavior

**Done when:** The data model spec is validated end-to-end in a running implementation. The Elixir runtime can target the same spec with confidence.

**Design:** [09_Compliance_Demo_Tool.md](../analysis/09_Compliance_Demo_Tool.md)

**Status:** Not started.

---

### Phase 2: Elixir walking skeleton

**Goal:** The minimal Elixir runtime that exercises every core concept. Zero external dependencies — pure BEAM.

**What's built:**
- `Artifact.Store` — ETS for metadata, filesystem for blobs, content-addressed by SHA-256
- `Event.Store` — append-only JSONL files, one per run, hash-chained
- `Plan` — the data structure (nodes, refs, literals)
- `Run.Server` — the scheduler loop (find ready → dispatch → collect → repeat)
- `Op` — the behaviour: `execute(inputs) :: {:ok, outputs, decisions} | {:error, reason}`
- ETS rebuild on startup from event files
- Reads the same file format the Python SDK writes

**Done when:** Can define a trivial plan (3 ops), execute it, produce artifacts, record events, and replay from the event log. The JSONL event files are identical in format to what the Python SDK produces.

**Dependencies:** Phase 0 (data model).

**Status:** Complete.

---

### Phase 3: OTP Runtime Layer

**Goal:** Promote the synchronous walking skeleton into a proper OTP application. The Phase 2 runtime is a synchronous loop with no supervision, no process isolation, and no event broadcasting. This phase builds the foundation that the observation layer and all real packs depend on.

**What's built:**
- `Liminara.Application` — OTP application with full supervision tree
- `Run.Server` GenServer — async, message-driven execution with concurrent fan-out
- `Run.DynamicSupervisor` + `Op.TaskSupervisor` — process isolation and supervision
- `Run.Registry` — maps run IDs to Run.Server PIDs
- `:pg` event broadcasting — every event broadcast to subscribers in real-time
- Crash recovery — op crashes handled gracefully, Run.Server rebuilds from event log
- Concurrent run isolation — multiple runs don't interfere
- Property-based stress testing (StreamData) — random DAG shapes, crash injection, concurrency invariants
- Toy pack exercising all four determinism classes, gates, binary artifacts, cache, and replay through the async runtime

**Done when:** Observer shows the expected supervision tree. 100+ random DAG shapes all execute correctly. Op crashes don't crash the Run.Server. Two concurrent runs produce independent, valid results. A toy pack with all determinism classes runs end-to-end through the GenServer path.

**Dependencies:** Phase 2 (walking skeleton).

**Status:** Not started.

---

### Phase 4: Observation layer

**Goal:** See what's happening inside a run. The "Excel quality" — everything visible, traceable, inspectable.

**What's built:**
- Observation UI (ex_a2ui on Bandit, or Phoenix LiveView)
- Live DAG visualization (consumes the `:pg` event stream built in Phase 3)
- Node inspection (inputs, outputs, decisions)
- No Phoenix as a platform dependency — lightweight observation only

**Done when:** Can watch a toy pack run in real-time in a browser, click nodes, see artifacts.

**Dependencies:** Phase 3 (OTP runtime with event broadcasting).

**Status:** Not started.

---

### Phase 5: Radar pack (first real product)

**Goal:** Daily-use research intelligence system. Validates the runtime against a real workload.

**What's built:**
- `Radar.Pack` — fetch → normalize → dedup → rank+summarize → deliver
- Real HTTP fetching, real LLM summarization
- Oban for scheduled recurring runs (first Postgres dependency)
- Cache layer (check before execute, store after)
- Two-layer architecture: continuous collection + triggered analysis (see [10_Synthesis.md](../analysis/10_Synthesis.md) § 6)
- LanceDB for vector index (file-based, embeddable)

**Done when:** Produces a daily briefing from real sources. Second run with same sources is near-instant for pure ops.

**Dependencies:** Phase 4 (observation — need to debug real runs).

**Status:** Not started.

---

### Phase 6: Oban + Postgres (scheduling)

**Goal:** Scheduled runs, persistent job queues, cross-run queries.

**What's built:**
- Oban integration for recurring Radar runs
- Postgres for Oban job tables
- Optional: cross-run artifact queries that ETS can't handle efficiently

**Done when:** Radar runs on a cron schedule without manual triggering.

**Dependencies:** Phase 5 (Radar is what needs scheduling).

**Status:** Not started.

---

### Phase 7: House Compiler (proof of generality)

**Goal:** Second real pack in a completely different domain. If the same five concepts work for both LLM text pipelines and geometry/structural/manufacturing pipelines, the platform has genuinely emerged.

**What's built:**
- `HouseCompiler.Pack` — params → semantic model → structural check → manufacture plan → drawings + NC + BOM
- `:port`/`:nif` executors for heavy compute (Rust geometry kernel)
- Binary artifacts (PDF, NC/BTL files)
- Pack-managed reference data (Eurocode5, SMHI snow loads, BBR)
- Fan-out DAG (manufacture → drawings + nc + bom in parallel)

**Done when:** A trivial house design produces correct structural output, PDF drawings, and a BOM. Has a buyer.

**Dependencies:** Phase 5 (Radar validates the runtime first).

**Status:** Not started.

---

### Beyond Phase 7 (not scheduled)

| Pack | Trigger |
|------|---------|
| Software Factory | Hobby pace, after House Compiler |
| Process Mining | When FlowTime is ready for integration |
| FlowTime Integration | When FlowTime matures beyond alpha |
| Far-horizon packs | When external contributors or customers need them |

---

## Deferral triggers

Things that are deferred, and what would un-defer them:

| Deferred | Trigger to un-defer |
|----------|-------------------|
| Multi-tenancy enforcement | Second customer exists |
| Distributed execution | Single BEAM node can't handle the workload |
| Discovery mode | Pipeline mode is proven, Radar collection layer needs it |
| Budget enforcement | Cost patterns are understood from real usage |
| Wasm executor | A concrete pack needs sandboxed DSL execution |
| Complex artifact GC | Storage costs become a problem |
| W3C PROV export | Compliance market demands interoperability |
| Hash-chained event log in v1 vs v2 | Decide during Phase 2 implementation |

---

## Python SDK as data model validation

The Python SDK (Phase 1) validated the data model spec before the Elixir runtime exists. Its primary value was forcing concrete decisions about event format, artifact hashing, decision records, and hash chains when those decisions were cheap to change.

The compliance reporting it produces (Article 12 reports, tamper-evidence) is a natural consequence of Liminara's architecture — not a standalone product. Liminara's actual value proposition is reproducibility, replay, caching, and decision recording; compliance falls out for free.

The SDK remains useful as:
- A runnable demo artifact for pitches and funding applications
- A reference implementation of the data model the Elixir runtime must match
- A proof that the decorator-based instrumentation model works

See [07_Compliance_Layer.md](../analysis/07_Compliance_Layer.md) for the architecture and [08_Article_12_Summary.md](../analysis/08_Article_12_Summary.md) for the regulatory context.

---

*This document is updated as phases complete. For settled strategic decisions, see [10_Synthesis.md](../analysis/10_Synthesis.md). For the runtime architecture, see [01_CORE.md](01_CORE.md).*
