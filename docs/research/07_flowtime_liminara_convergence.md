# FlowTime and Liminara: Convergence Analysis

**Date:** 2026-03-19
**Status:** Research / exploration
**Supersedes:** Extends `docs/analysis/06_FlowTime_and_Liminara.md` (2026-03-14) with insights from the graph execution patterns research and supply chain parallels.
**Context:** The user is bringing FlowTime back into active use as a consulting tool. This analysis re-examines the relationship with new framing.

---

## 1. What Has Changed Since the Last Analysis

The previous analysis (06_FlowTime_and_Liminara.md) identified three integration models: FlowTime as an Op, FlowTime's model-building as a Liminara pipeline, and shared philosophical DNA. All three remain valid.

What's new:

1. **The "graph execution patterns" research** (`docs/research/graph_execution_patterns.md`) placed both systems in a broader taxonomy of "things that execute on a graph" — alongside build systems, smart contracts, supply chains, and biological pathways. This reveals deeper structural parallels and a wider applicability than either system claims individually.

2. **The activatable run pattern** — recognizing that Liminara runs can span arbitrary time scales (seconds to years) by stopping the Run.Server between events and restarting on demand. This makes Liminara viable for real-world process tracking, not just computational pipelines.

3. **The simulation/live duality** — the same DAG can run instantly (simulation) or over months (live, gated by the real world). Decision records enable comparing planned vs actual.

4. **FlowTime's current state** — actively developed (last push 2026-03-07), with MCP server, time-travel observability, dependency constraints, and expression language. Not yet production-ready but approaching it. The user wants to use it in consulting now.

---

## 2. Two Systems, One Pattern

### The structural parallel

Both FlowTime and Liminara are instances of the same abstract pattern:

> A directed graph of typed transformations, evaluated in dependency order, producing traceable artifacts, with deterministic semantics.

| Property | FlowTime | Liminara |
|----------|----------|----------|
| **Graph type** | Service flow graph (nodes = services, edges = flows) | Computation DAG (nodes = ops, edges = artifacts) |
| **What flows** | Work items (orders, requests, patients, cases) | Artifacts (data, documents, binaries) |
| **Evaluation order** | Topological, bin-by-bin (discrete time steps) | Topological, event-driven (dependency resolution) |
| **Determinism** | Guaranteed (same model + seed = same output) | Captured (4 classes; decisions make nondeterministic runs replayable) |
| **Time model** | Discrete time grid (bins); time IS the evaluation axis | Event-driven; time is metadata on events |
| **Immutability** | Evaluated bins don't mutate | Artifacts are content-addressed, events are append-only |
| **Canonical artifacts** | `run.json`, `manifest.json`, CSV series | JSONL event logs, content-addressed blobs, decision records |
| **Observability** | Time-travel (`/state`, `/state_window`) | Event replay (any past state reconstructable from log) |
| **"What-if"** | Scenario templates → parameter variations → compare runs | Decision injection → branch at any choice → compare runs |

### The key difference

FlowTime models **how work moves through a system over continuous time** — throughput, queues, bottlenecks, latency. It's a physics engine for flows.

Liminara models **how a specific output was produced through a series of transformations** — provenance, decisions, reproducibility. It's a provenance engine for computation.

FlowTime answers: "What happens to this system over the next 30 days?"
Liminara answers: "How was this artifact produced, and what choices led here?"

**They are complementary, not competing.** FlowTime is the microscope (continuous dynamics). Liminara is the workshop (discrete orchestration with provenance).

---

## 3. How Liminara Can Help FlowTime

The user wants to use FlowTime in consulting but it's not production-ready. Can Liminara help? The answer depends on what "help" means.

### 3.1 Liminara as the consulting workflow wrapper

A consulting engagement using FlowTime follows a process:

```
client_briefing → ingest_telemetry → build_model → validate_model →
  [human: review with client] → run_scenarios → analyze_results →
  [human: discuss findings with client] → write_report → deliver
```

This IS a Liminara pipeline. The nondeterministic parts:
- **Model-building choices** — which services to include, how to decompose the system, parameter estimates (recordable decisions)
- **Client reviews** — feedback that changes the model, approval to proceed (gates)
- **Scenario selection** — which what-ifs to run, based on client priorities (recordable decisions)
- **Report content** — what to emphasize, what to recommend (recordable decisions, possibly LLM-assisted)

The deterministic parts:
- **FlowTime simulation** — pure, given model + parameters
- **Data transformation** — normalizing telemetry into FlowTime's input format
- **Report rendering** — given analysis results, produce PDF/markdown

A `FlowTime.ConsultingPack` would give you:
- **Reproducibility:** Re-run the exact same analysis with the same decisions. Or branch: "What if we'd modeled the retry logic differently?"
- **Provenance:** Six months later, the client asks "Why did you recommend adding capacity to service X?" The event log + decision records show exactly: the telemetry data, the model choices, the simulation results, the analysis that led to the recommendation.
- **Caching:** The simulation runs are pure — change the model parameters, only the simulation and downstream steps re-run. The telemetry ingestion is cached.
- **Efficiency:** Second engagement with the same client? The model from the first engagement is an artifact. Update it instead of rebuilding from scratch.

### 3.2 Liminara's observation layer as a UI reference

FlowTime has a Blazor WebAssembly UI. Liminara is building Phoenix LiveView + A2UI (Phase 4). Both need to visualize graphs and time-series data.

The observation layer work might produce reusable visualization patterns:
- SVG DAG rendering with real-time state updates
- Node inspection with drill-down
- Event timeline with filtering
- Responsive layout for desktop + mobile

These patterns could inform FlowTime's UI evolution, even though the tech stacks differ (Blazor vs LiveView). The design language — how to show a graph, how to show state changes, how to drill down — transfers across frameworks.

### 3.3 What Liminara cannot do for FlowTime

- **Make FlowTime production-ready.** FlowTime is C#/.NET. Liminara is Elixir. They can't share code. FlowTime's own bugs, missing features, and rough edges need to be fixed in FlowTime.
- **Replace FlowTime's UI.** FlowTime's Blazor UI is its own surface. Liminara's observation layer observes Liminara runs, not FlowTime internals.
- **Add FlowTime features.** If FlowTime needs better anomaly detection or telemetry ingestion, that's FlowTime work, not Liminara work.

The practical help is at the **workflow level** (Liminara wraps the consulting process around FlowTime) and the **pattern level** (shared visualization and architecture insights), not at the code level.

---

## 4. How FlowTime Can Help Liminara

### 4.1 FlowTime as a flow analyzer for Liminara's own execution

A Liminara run IS a flow of artifacts through operations. Each op is a "service" in FlowTime terms. Artifacts are the work items. The event log provides telemetry:

| Liminara event | FlowTime telemetry equivalent |
|----------------|------------------------------|
| `op_started` (timestamp, node_id) | Work item enters service |
| `op_completed` (timestamp, node_id, duration_ms) | Work item exits service |
| `op_failed` (timestamp, node_id) | Work item rejected/failed |
| `gate_requested` / `gate_resolved` | Work item queued for human processing |
| Multiple events at same timestamp | Concurrent processing (fan-out) |

If Liminara's JSONL events could be transformed into FlowTime's telemetry format, FlowTime could analyze Liminara's own execution:

- **Bottleneck detection:** Which ops are the slowest? Where do artifacts queue up waiting for dependencies?
- **Capacity analysis:** What happens if we parallelize more? What if the LLM is 2x slower?
- **What-if simulation:** "If we add caching to this op, how does total run duration change?"
- **Comparison:** Run the same pack twice with different parameters → FlowTime compares the flow patterns.

This is the "system analyzing itself" meta-level connection — Liminara generates the telemetry, FlowTime analyzes it.

### 4.2 FlowTime as proof of the heterogeneous executor model

FlowTime is written in C#/.NET. Calling it from Liminara exercises the `:port` or `:container` executor model — the BEAM orchestrates, the .NET engine computes. This proves that Liminara can integrate non-BEAM computation engines, which is the same pattern needed for:

- Rust geometry kernels (house compiler)
- Python ML models (radar summarization, if not using an API)
- External APIs (LLM providers)

If FlowTime works as a `:port` executor, the pattern is validated for all heavy-compute integrations.

### 4.3 FlowTime's domain validates Liminara's generality

Flow modeling through queues and services is maximally different from LLM text pipelines. If the same five concepts (Artifact, Op, Decision, Run, Pack) orchestrate both a Radar intelligence pipeline and a FlowTime model-building process, the architecture is genuinely domain-agnostic.

The previous analysis already made this point. What's new is that the supply chain research adds a third validation domain: physical goods flowing through transformation networks. Three domains (text pipelines, flow simulation, physical supply chains) mapping to the same five concepts is strong evidence of genuine generality.

---

## 5. The Practical Integration Path

### 5.1 Communication protocol

FlowTime has two integration surfaces:
1. **REST API** (`/state`, `/state_window`, `/graph`) — engine mode queries
2. **MCP server** — AI agent tooling for modeling, analysis, inspection

For Liminara integration, MCP is the natural choice:
- MCP is designed for tool calling from AI agents and orchestrators
- FlowTime's MCP server already exposes modeling and analysis tools
- Liminara ops could use MCP client calls to interact with FlowTime
- This avoids building custom REST client code

The alternative (`:port` executor launching the FlowTime CLI directly) is simpler but less capable — it doesn't support the interactive model-building workflow.

**Recommended:** MCP for interactive/agentic workflows (model building, analysis). CLI/port for batch simulation runs where you just need results.

### 5.2 Artifact format bridge

FlowTime produces:
- `run.json` — run manifest
- `manifest.json` — artifact manifest
- `series/index.json` + per-series CSVs — time-series data

Liminara stores:
- Content-addressed blobs (any format)
- JSONL event logs
- Decision records (JSON)

The bridge: FlowTime's output files become Liminara artifacts. A `flow.simulate` op calls FlowTime, receives its canonical output, and stores each file as a content-addressed artifact. On replay, the same artifacts are returned from cache (if the model hasn't changed) or re-simulated.

FlowTime's model definition (`flow.model_ir.v1` in the domain pack spec) is the key artifact — it's the immutable, versioned model that FlowTime evaluates. Changes to the model create new artifacts with different hashes, automatically invalidating downstream caches.

### 5.3 Event format convergence

Both systems produce structured event logs. If the event schemas share common fields (timestamp, entity_id, event_type, payload), cross-system analysis becomes possible:

- Liminara events → FlowTime telemetry (analyze Liminara's own execution patterns)
- FlowTime simulation results → Liminara artifacts (store, cache, trace)
- Process mining events (XES/OCEL) → both systems (common upstream source)

This doesn't require identical formats — just a transformation step (an op) that converts between them. But designing with awareness of each other's event schemas would reduce friction.

---

## 6. The Consulting Toolkit Vision

The user wants FlowTime as a consulting tool. Here's how the two systems combine into a consulting toolkit:

### The workflow

```
1. Client engagement
   └── Liminara: ConsultingPack creates a run
       ├── Ingest client's telemetry data (side_effecting op)
       ├── AI-assisted model building (recordable — decisions recorded)
       │   └── FlowTime MCP: propose model structure, validate against data
       ├── Client review gate (human gate — approval recorded as decision)
       ├── Run scenarios (pure — FlowTime simulation, cached)
       │   ├── Baseline scenario
       │   ├── "Add capacity to service X" scenario
       │   └── "Optimize routing" scenario
       ├── Analysis (pure/recordable — compare scenarios, AI summarize)
       ├── Client discussion gate (human gate — feedback recorded)
       ├── Generate report (pure — deterministic rendering)
       └── Deliver (side_effecting — send to client)
```

### What you get

1. **Every engagement is reproducible.** Re-run with the same decisions → same report. Change one decision → only affected parts re-execute.
2. **Every recommendation is traceable.** Client asks "Why service X?" → follow the decision chain: telemetry data → model structure → simulation results → analysis → recommendation.
3. **Engagements are cacheable.** Second engagement with the same client: the model is an artifact from the first engagement. Update it, don't rebuild.
4. **What-if is native.** "What if we'd modeled it differently?" → branch at the model-building decision, re-simulate, compare.
5. **The observation layer shows progress.** Client can watch (on mobile, via A2UI) as the analysis runs.

### What's needed to build this

| Component | Status | Work needed |
|-----------|--------|-------------|
| Liminara core runtime | Done (Phase 3) | None |
| Observation layer | Phase 4 (E-09, planned) | Build it |
| FlowTime engine | Active development | Reach "consulting-usable" stability |
| FlowTime MCP server | Exists | May need expansion for model-building tools |
| MCP client in Liminara | Not started | Build as part of a FlowTime pack |
| ConsultingPack | Not started | Build after Phase 4 + FlowTime stabilization |
| Report generation | Not started | Could use LLM + templates |

The critical path for the consulting toolkit is:
1. **Phase 4 (observation)** — so you can see what's happening
2. **FlowTime stabilization** — so the simulations are reliable
3. **MCP client op** — so Liminara can call FlowTime
4. **ConsultingPack** — the pipeline definition

This is post-Phase 5 (Radar) in the current plan, unless the consulting need accelerates it.

---

## 7. The Graph-of-Graphs Insight

When FlowTime is an op in a Liminara run, you have a graph within a graph:

```
Liminara DAG level:
  [telemetry] → [build_model] → [simulate] → [analyze] → [report]
                                     │
                                     ▼
                              FlowTime graph level:
                                [service_A] ──→ [router] ──→ [service_B]
                                     │                            │
                                     └──→ [service_C] ──→ [sink] ◄┘
```

The Liminara observation layer shows the top-level DAG. But when you click on the "simulate" node, you could potentially drill down into the FlowTime model graph — seeing the service flow that was simulated.

This "drill-down from orchestration graph to domain graph" is a powerful visualization pattern. It applies beyond FlowTime:
- House compiler: drill into the structural analysis graph
- Radar: drill into the source dependency graph
- Software factory: drill into the code dependency graph

The observation layer doesn't need to understand these domain-specific graphs — it just needs a mechanism for ops to attach a "detail view" artifact that the inspector can render. The FlowTime op attaches its model graph. The structural analysis op attaches its load diagram. The mechanism is generic; the content is domain-specific.

---

## 8. The Bigger Picture: Flow Literacy as a Universal Lens

FlowTime's vision of "flow literacy" — a common language for talking about flows and resilience across domains — aligns with the graph execution patterns research. Supply chains, service systems, manufacturing pipelines, software workflows, and biological pathways are all flow systems.

If FlowTime provides the modeling and simulation layer, and Liminara provides the orchestration and provenance layer, together they cover:

| Capability | Provider |
|-----------|----------|
| Model a system as a flow graph | FlowTime |
| Simulate "what-if" scenarios | FlowTime |
| Orchestrate the analysis process | Liminara |
| Record all decisions (model choices, human approvals) | Liminara |
| Replay and branch analyses | Liminara |
| Cache expensive computations | Liminara |
| Audit trail for recommendations | Liminara |
| Analyze execution performance | FlowTime (meta-level) |
| Visualize graphs and state | Both (each at their level) |

Neither system alone covers this. Together, they're a platform for "understand any flow system, with full provenance and reproducibility."

This is speculative and aspirational — not a build commitment. But it validates both systems' architectures: FlowTime's graph engine and Liminara's provenance engine complement each other at a deep structural level, not just as a convenient integration.

---

## 9. Differences from Previous Analysis

| Previous analysis (06) | This analysis | What changed |
|------------------------|---------------|-------------|
| FlowTime as Op / as Pipeline / as Philosophy | All still valid | Framing expanded |
| "First-class executor type" | MCP as primary integration | MCP server exists now; cleaner than custom executor |
| Generic pack examples (System Modeler, Capacity Planner) | Concrete ConsultingPack | User's immediate need drives the design |
| "When FlowTime matures beyond alpha" | Parallel paths — FlowTime stabilizes while Liminara builds observation | User is actively developing both |
| No supply chain connection | Supply chain as a shared validation domain | graph_execution_patterns.md research |
| No mention of FlowTime analyzing Liminara | Bidirectional: Liminara orchestrates FlowTime AND FlowTime analyzes Liminara | Meta-level insight from flow analysis |
| No activatable runs | Long-running consulting engagements as activatable runs | Architecture pattern recognized |

---

## 10. Open Questions

1. **MCP vs REST vs Port:** What's the right integration protocol for the MVP? MCP is richest but may be overkill for "run a simulation, get results." A `:port` executor calling `dotnet run FlowTime.Cli` is simpler. What does FlowTime's CLI currently support?

2. **Event format convergence:** Should the two systems share an event schema, or is a transformation op sufficient? Sharing would reduce friction; transforming keeps them independent.

3. **Which comes first — ConsultingPack or Radar?** The build plan says Radar first (Phase 5). But if the consulting need is pressing, a minimal FlowTime pack could be built alongside or even before Radar. Both exercise the same core capabilities.

4. **FlowTime's Blazor UI and Liminara's LiveView:** Could they coexist in a single consulting dashboard? Blazor runs client-side (Wasm); LiveView runs server-side. They're architecturally compatible — both could be embedded in the same page via iframes or a shared shell. Worth exploring for the consulting toolkit.

5. **Can FlowTime's deterministic engine benefit from Liminara's content-addressing?** If FlowTime's run artifacts were content-addressed (hash of model + parameters = unique run ID), FlowTime would gain built-in caching semantics. This could be a FlowTime-side improvement inspired by Liminara's architecture.

---

*This document extends `docs/analysis/06_FlowTime_and_Liminara.md`. For the graph execution patterns taxonomy, see `docs/research/graph_execution_patterns.md`. For the historical build-plan discussion of recognized architectural patterns, see `docs/history/architecture/02_PLAN.md §Recognized architectural patterns`.*
