# Liminara: Comprehensive Reference

**A runtime for reproducible nondeterministic computation.**

---

## Table of Contents

1. [What Liminara Is](#1-what-liminara-is)
2. [The Core Insight](#2-the-core-insight)
3. [The Mental Model](#3-the-mental-model)
4. [Five Concepts](#4-five-concepts)
5. [The Execution Model](#5-the-execution-model)
6. [Determinism Classes](#6-determinism-classes)
7. [Replay and Why It Matters](#7-replay-and-why-it-matters)
8. [Architecture](#8-architecture)
9. [Data Model](#9-data-model)
10. [Domain Packs](#10-domain-packs)
11. [Competitive Landscape](#11-competitive-landscape)
12. [Intellectual Ancestors](#12-intellectual-ancestors)
13. [EU AI Act and Compliance](#13-eu-ai-act-and-compliance)
14. [Build Plan](#14-build-plan)
15. [Licensing and Business Model](#15-licensing-and-business-model)
16. [Funding Paths](#16-funding-paths)
17. [What's Deferred](#17-whats-deferred)
18. [Recognized Architectural Patterns](#18-recognized-architectural-patterns)
19. [Open Questions](#19-open-questions)

---

## 1. What Liminara Is

**Liminara is a general-purpose supervised computation runtime with recorded nondeterminism.**

It records every nondeterministic choice — LLM responses, human approvals, stochastic selections — so any run can be replayed exactly, audited completely, and cached intelligently. Technically: a directed acyclic graph (DAG) of operations producing immutable, content-addressed artifacts, with nondeterminism captured as decision records, supervised by Elixir/OTP.

Or more succinctly: **Make for processes with choices.**

Where Make (and its descendants: Bazel, Nix, Gradle, Buck) assumes all rules are deterministic — same inputs, same output, always — Liminara extends the build system model to operations that involve genuine nondeterminism: LLM responses, human judgments, evolutionary search, creative synthesis. It does this by recording the choices that resolve that nondeterminism.

The five-concept model (Artifact, Op, Decision, Run, Pack) is completely domain-agnostic. These concepts apply equally to:

- AI/LLM workflow orchestration (Radar pack)
- Computational engineering (House Compiler pack)
- Flow modeling (FlowTime integration)
- Scientific workflows (bioinformatics, materials science)
- Supply chain management
- Any domain where nondeterminism needs to be tracked

"Knowledge work" is the beachhead market, not the definition. The House Compiler (non-LLM, geometry/structural/manufacturing) is the deliberate proof of generality — it is the second real pack precisely because it breaks the "LLM orchestrator" framing.

### The elevator pitch

> Liminara is a provenance engine for nondeterministic computation. The world is building AI pipelines everywhere — but nobody can answer "why did this pipeline produce this output last Tuesday?" Everyone can replay a database migration. Nobody can replay an LLM-driven workflow. Temporal records execution history but treats nondeterminism as a nuisance. LangGraph has checkpoint replay but no content-addressed artifact lineage. Dagster has asset lineage but no decision recording.

### The core differentiator

The combination nobody else has:

1. **Content-addressed artifacts** (like Git/Bazel/Nix) — "have I computed this exact thing before?"
2. **Decision records** (like a lab notebook) — "what did the LLM say, what did the human approve?"
3. **Determinism classes** (like a type system for side effects) — "is this op safe to cache? safe to replay?"

Neither Temporal, Dagster, Apache Burr, LangGraph, nor any other tool in the space has all three. This combination is the architectural moat.

---

## 2. The Core Insight

**Nondeterminism is not chaos — it's just decisions you haven't recorded yet.**

Traditional build systems assume determinism: same inputs, same output. This works for compiling C code or rendering a PDF. It fails for:

- Asking an LLM to summarize a document (different every time)
- A human approving or rejecting a design (a judgment call)
- A genetic algorithm selecting candidates (stochastic)
- Fetching a web page (changes over time)

These are nondeterministic steps — the output depends on choices not captured in the inputs. Make can't handle this. Neither can Bazel or Nix. They either refuse to cache the result (losing the main benefit) or cache it incorrectly (pretending the output is stable when it isn't).

Liminara adds one concept to the build system model: the **decision record**. When an operation makes a nondeterministic choice, it records that choice. Now:

- **First run (discovery):** Execute operations, make choices, record everything. You end up with a fully-determined DAG.
- **Replay:** Re-execute the same DAG, but inject the stored decisions instead of making new ones. Deterministic.

After all decisions are recorded, every run is a deterministic build. Replay is just `make` with cached choices.

The four-class determinism system (pure / pinned_env / recordable / side_effecting) is the most elegant part of this design. It doesn't exist anywhere else as a first-class architectural concept.

---

## 3. The Mental Model

Three analogies reinforce what Liminara is:

### Make (the execution model)

The build system as a starting point. Make, and its descendants (Bazel, Nix, Gradle, Buck), all solve the same problem: given a set of inputs and a set of transformation rules, produce the correct outputs — and don't redo work that hasn't changed. A build system has targets (artifacts), rules (operations), and dependencies (what each target needs). Liminara inherits all of this: dependency tracking, caching, reproducibility, incrementality.

**Make + a tape recorder.** After all decisions are recorded, every run is a deterministic build.

### Excel (the observation model)

The *feeling* Liminara should provide:

- You can **see everything** — every value, every formula, every dependency
- You can **trace backwards** — click a cell, see its formula, click its inputs, see their formulas
- You can **change an input** and see what would change downstream

The DAG viewer is the spreadsheet. Each node is a cell. Each artifact is a value. Each op definition is a formula. You can inspect anything, trace anything.

### OTP (the reliability model)

And the reliability model is pure Elixir:

- Each run is a supervision tree
- Operations crash? Supervisor restarts them
- Run crashes? Resume from the last recorded event
- Everything is isolated. Nothing is silently lost.

### Unix (the composition model)

- Small operations that do one thing
- A universal interface between them (artifacts, like Unix's text streams)
- Composition via the graph (like pipes, but branching and merging)
- Each operation is isolated (a process, like Unix processes)

### Nix (the closest technical ancestor)

Nix's insight: if you record every input (including the environment), builds become reproducible. Liminara's insight: if you record every *decision*, processes with genuine nondeterminism become reproducible too. Nix controls determinism by controlling inputs. Liminara controls determinism by recording choices. That's a more general mechanism because it handles irreducible nondeterminism (human judgment, stochastic algorithms, external API responses) that Nix's approach can't capture.

---

## 4. Five Concepts

The core has five concepts. Not twenty. Five.

### 4.1 Artifact

An immutable, content-addressed blob. The edges in the DAG — data flowing between operations.

```elixir
%Artifact{
  hash: "sha256:a1b2c3...",    # content hash = identity
  type: "radar.briefing.v1",   # schema type
  bytes: <<...>>,              # the actual data
  metadata: %{                 # provenance, not content
    produced_by: "summarize",
    run_id: "run_abc",
    timestamp: ~U[2026-03-02 14:30:00Z]
  }
}
```

An artifact is a value. It doesn't change. If you have its hash, you have its identity. Same hash = same content, always. Small artifacts (JSON, structs, configs) live in ETS (in-memory, fast). Large artifacts (PDFs, NC files, geometry models) live on the filesystem, addressed by hash. Both are content-addressed. No external database needed.

### 4.2 Op

A typed function: artifacts in, artifacts out.

Historically, the runtime exposed ops through separate callbacks. The canonical contract now being locked in Phase 5c is `execution_spec/0`, which folds identity, determinism, execution, isolation, and contracts into one truthful shape.

```elixir
%Liminara.ExecutionSpec{
  identity: %{name: :rank_and_summarize, version: "1.0.0"},
  determinism: %{class: :recordable},
  execution: %{kind: :port, op: "radar_summarize", timeout_ms: 30_000},
  isolation: %{
    env_vars: ["ANTHROPIC_API_KEY"],
    network: :tcp_outbound,
    bootstrap_read_paths: [:op_code, :runtime_deps],
    runtime_read_paths: [],
    runtime_write_paths: []
  },
  contracts: %{
    inputs: %{unique_docs: %{required: true}},
    outputs: %{briefing: %{required: true}},
    may_warn: true
  }
}
```

An op doesn't know about scheduling, retry, supervision, or storage. It's just a function with a determinism class. The runtime handles everything else.

The older four-callback surface is legacy implementation detail during the M-TRUTH-02 migration, not the contract new features should extend:

| Callback | Returns |
|----------|---------|
| `name()` | `String.t()` |
| `version()` | `String.t()` |
| `determinism()` | `:pure \| :pinned_env \| :recordable \| :side_effecting` |
| `execute(inputs)` | `{:ok, outputs}` or `{:ok, outputs, decisions}` or `{:gate, prompt}` or `{:error, reason}` |

### 4.3 Decision

A recorded nondeterministic choice. The concept that makes everything else work.

```elixir
%Decision{
  node_id: "summarize_cluster_3",
  op: :llm_summarize,
  input_hash: "sha256:def456...",
  choice: %{
    model: "claude-haiku-4-5-20251001",
    prompt_hash: "sha256:...",
    response: "The key development is...",
    usage: %{input_tokens: 340, output_tokens: 142}
  },
  timestamp: ~U[2026-03-02 14:30:00Z]
}
```

Decisions exist for one reason: to turn a nondeterministic run into a replayable one. Every `recordable` op must produce a decision record alongside its output artifacts.

Human approvals are decisions. LLM responses are decisions. GA selections are decisions. Random seeds are decisions. Anything nondeterministic that affects the DAG is a decision.

### 4.4 Run

An execution: a plan being walked. Fundamentally **an append-only event log**. Everything else — the current state, which nodes are complete, which artifacts exist — is a projection of that log.

```elixir
%Run{
  id: "run_abc",
  pack: :radar,
  plan: %Plan{...},          # the DAG of nodes
  events: [...],             # append-only event log (source of truth)
  state: :running,           # derived from events, not stored separately
  decisions: %{...},         # indexed for replay injection
}
```

Event types:
```
run_started        {plan}
node_ready         {node_id}
node_started       {node_id}
node_completed     {node_id, output_hashes}
node_failed        {node_id, error}
decision_recorded  {node_id, decision}
node_added         {node_id, op, inputs}        # for discovery mode
gate_requested     {node_id, prompt}
gate_resolved      {node_id, response}
run_completed      {}
run_failed         {reason}
```

Why event sourcing? Because it gives replay, debugging, and time-travel for free. You can reconstruct the state of a run at any point in its history. You can ask "what happened between minute 3 and minute 7?" The events ARE the run.

**Hash-chained event log:** Each event includes `prev_hash` — the SHA-256 of the previous event. This creates a tamper-evident chain: modifying any event invalidates all subsequent hashes. The final event's hash is the **run seal**, cryptographically committing to the entire run history. This gives EU AI Act Article 12 tamper-evidence as an architectural consequence, not a bolt-on.

### 4.5 Pack

A module that provides ops and knows how to plan work.

```elixir
defmodule Liminara.Pack do
  @callback id() :: atom()
  @callback version() :: String.t()
  @callback ops() :: [Op.t()]
  @callback plan(input :: term()) :: Plan.t()

  # Optional: register reference data (rulesets, material databases, geographic lookups)
  @callback init() :: :ok
end
```

Five callbacks (one optional). A pack tells the runtime: who it is, what version it is, what operations it can perform, how to build a plan for a given input, and optionally what reference data it ships with. That's the entire pack contract.

Reference data: the house compiler needs material properties, span tables, geographic load maps. These are **versioned datasets** the pack brings with it. `init/0` registers them as artifacts in the store. When the pack upgrades and the dataset changes, the version changes, cache keys invalidate, downstream ops re-execute automatically.

---

## 5. The Execution Model

### The DAG

The execution model is a **DAG (directed acyclic graph)**. This is a settled decision.

A plan is a graph of nodes. Each node names an op and declares its inputs — either literal values or references to other nodes' outputs.

```elixir
# Radar pack plan — a linear pipeline
Plan.new()
|> Plan.node(:fetch,     :fetch_sources,      sources: literal(source_list))
|> Plan.node(:normalize, :normalize_docs,     raw: ref(:fetch))
|> Plan.node(:dedup,     :deduplicate,        docs: ref(:normalize))
|> Plan.node(:summarize, :rank_and_summarize, docs: ref(:dedup))
|> Plan.node(:deliver,   :deliver_briefing,   briefing: ref(:summarize))
```

```
[source_list] → fetch → [raw_pages] → normalize → [clean_docs] → dedup → [unique_docs] → summarize → [briefing] → deliver
              (pinned)    (pure)       (pure)    (recordable/LLM)   (side_effect)
```

Not all plans are linear. The house compiler shows branching, fan-out, and heterogeneous workloads:

```
                    [location]
                        │
[params] → semantic ────┤──→ structural ──→ manufacture ──┬──→ drawings
                        │         ↑            ↑          ├──→ nc_files
                        └──→ thermal    [ruleset]         └──→ bom
```

For discovery mode (agents that decide what to do next):

```elixir
Plan.new()
|> Plan.node(:analyze, :analyze_task,   task: literal(task_description))
|> Plan.node(:next,    :plan_next_step, analysis: ref(:analyze), expand: true)
```

The `expand: true` flag means this node's output includes new nodes to add to the plan. The scheduler adds them and keeps going. Same loop, same infrastructure.

| | Pipeline mode | Discovery mode |
|---|---|---|
| Plan | Known upfront | Built incrementally |
| DAG | Static | Growing |
| Examples | Radar, house compiler | Software factory, agent fleets |
| Planning | Once, before execution | Interleaved with execution |
| Result | Same thing: a DAG of artifacts with recorded decisions |

### Why not a state machine?

Apache Burr chose a state machine model for AI agents because agents loop — observe, reason, act, repeat. State machines handle cycles ergonomically. But they sacrifice:

- **Content-addressed caching** — stable cache keys require stable node identity, which cycles break
- **Deterministic replay** — "which cycle iteration are we on?" has no clean answer in a state machine
- **Provenance tracing** — shared mutable state makes backward tracing hard
- **Parallelism** — independent DAG nodes fire simultaneously; shared state creates implicit dependencies

Any state machine can be **unrolled** into a DAG — a standard result in formal methods. The DAG is the property that enables content-addressing, replay, and provenance. The state machine is an implementation detail of individual ops, not a runtime concern.

**Formal backing:** A Liminara plan is a **workflow net** — a well-studied subclass of Petri nets. Petri net theory provides formal tools for verifying the scheduler: deadlock-freedom, liveness, reachability.

### The scheduler

The core of the runtime is embarrassingly simple:

```elixir
def execute(run) do
  case find_ready_nodes(run) do
    [] when all_complete?(run) -> {:ok, run}
    [] when any_failed?(run)   -> {:error, run}
    [] -> {:waiting, run}  # nodes are executing or gated
    ready ->
      run = Enum.reduce(ready, run, &dispatch/2)
      {:continuing, run}
  end
end

defp find_ready_nodes(run) do
  run.plan.nodes
  |> Enum.filter(fn {_id, node} ->
    node.state == :pending and all_inputs_resolved?(node, run)
  end)
end
```

Find nodes whose inputs are all available. Dispatch them. Collect results. Repeat. This loop handles:

- **Linear pipelines** — each node resolves one at a time
- **Fan-out** — multiple nodes become ready simultaneously, dispatched in parallel
- **Fan-in** — a node waits until all upstream nodes complete
- **Discovery** — an `expand` node adds new nodes, which the loop picks up next iteration
- **Gates** — a gated node stays in `:waiting` until a human resolves it
- **Failure** — a failed node triggers the run's error policy

No special cases. The loop is the same for all workload shapes.

---

## 6. Determinism Classes

The determinism class is a type system for side effects. It controls caching and replay behavior:

| Class | Meaning | Cache? | On replay |
|---|---|---|---|
| `pure` | Same inputs → same output, always | Yes | Re-execute (or cache hit) |
| `pinned_env` | Same inputs + same environment → same output | Yes (with env hash in key) | Re-execute with pinned env |
| `recordable` | Nondeterministic, but we record the decision | No | Inject stored decision |
| `side_effecting` | Changes the outside world | No | Must re-execute (or skip) |

Four classes. Clean, exhaustive, actionable.

### Caching (Bazel's gift)

Caching falls out naturally from content addressing and determinism classes:

```
cache_key = hash(op_name, op_version, hash(input_artifacts), env_hash?)
```

On execution:
1. Compute cache key from op + inputs (+ environment for `pinned_env` ops)
2. Check if a result exists for this key
3. **Hit:** skip execution, return cached artifacts
4. **Miss:** execute, store result, index by cache key

This is Bazel's model (action cache + CAS), applied to knowledge work:

- Re-running the radar with the same sources? All pure ops are cached. Only the LLM summarization re-executes.
- Tweaking the house roof pitch from 27° to 30°? The load lookup is cached (same location). Semantic model re-runs. Everything downstream re-runs. Everything upstream is cached.
- Replaying a run with stored decisions? Every node is either cached (pure/pinned) or injected (recordable). Nothing actually executes. Instant replay.

### Environment pinning

For `pinned_env` ops, "same environment" means same Elixir version, same NIF library version, same Rust toolchain, etc. An `%Environment{}` struct captures relevant versions, gets hashed, and included in cache keys:

```elixir
%Environment{
  elixir: "1.18.0",
  otp: "27.0",
  os: "darwin-arm64",
  deps: %{
    "opencascade_rs" => "0.3.1",
    "eurocode5_solver" => "1.0.0"
  }
}
```

---

## 7. Replay and Why It Matters

"I ran a pipeline. I have the output. Why would I ever run it again?"

If Liminara only re-ran the same thing identically, replay would be pointless overhead. But replay isn't about repetition — it's the mechanism that turns a process into a navigable structure instead of a one-shot event.

### 7.1 Selective re-execution (the build system property)

50 sources analyzed by an LLM — $2 and 10 minutes. You realize the synthesis prompt was wrong.

- **Without replay**: re-run everything. 50 LLM calls you already paid for. Waste.
- **With replay**: fetch, filter, and analyze ops haven't changed. Cache hit. Only the synthesis op re-executes.

**Incremental recomputation over nondeterministic processes.**

### 7.2 Branching decisions (exploration as a tree)

House compiler: at `select_layout`, the system chose layout B from five candidates. Buyer asks: "What if we'd gone with option D?"

- **Without replay**: start over. Re-run layout generation (30 minutes). Get the same five options. Pick D. Re-run everything.
- **With replay**: fork the run at the decision point. Inject decision D. Everything upstream is cached. Only downstream re-executes.

**Linear processes become decision trees you can navigate after the fact.** This is genuinely novel — build systems don't do this (no decisions to vary), workflow engines don't do this (decisions aren't first-class replayable entities).

### 7.3 Auditable provenance (the compliance property)

For any artifact, answer: **What produced this? From what inputs? With what decisions? By which version of which op?**

The event log gives a complete causal chain from final output to initial inputs. Every decision recorded. Every intermediate artifact content-addressed and retrievable. Not replay as "run it again." Replay as **forensic reconstruction.**

### 7.4 Deterministic production (discovery to hardened pipeline)

- **Week 1 (Discovery)**: building a new pipeline. Trying different prompts, strategies. Each run makes decisions.
- **Week 4 (Stabilization)**: found a configuration that works. Every decision has been made and recorded.
- **Week 5+ (Production)**: replay with stored decisions. The run is deterministic. No expensive calls for pinned decisions.

Without replay, the transition from experiment to production requires rewriting as a different system. **With replay, it's the same system — you stop making new decisions and start injecting recorded ones.**

### 7.5 Efficient what-if analysis

House compiler: a full run took 2 hours and $15 in compute. The buyer explores "what if we used a different roof type?" "What if we added a bathroom?" "What if cheaper materials?" Each what-if re-uses everything upstream of the changed decision. Cost: minutes and cents, not hours and dollars.

### 7.6 Regression detection

Upgrade an LLM from GPT-4 to GPT-4.5. Replay the last 10 runs with the new model. The decisions will differ, but the DAG structure, inputs, and all deterministic ops stay the same. **The variable is isolated. Outputs can be diffed structurally.**

### Summary

| Capability | Without Replay | With Replay |
|-----------|---------------|------------|
| Change one step in a pipeline | Re-run everything | Re-run only what changed |
| Explore alternative choices | Start over | Fork at the decision point |
| Audit how an output was produced | Hope you logged enough | Complete causal reconstruction |
| Move from experiment to production | Rewrite as a different system | Pin decisions, same system |
| Test a model upgrade | Re-run and eyeball it | Controlled comparison, isolated variable |
| Explore a design space | N full runs at full cost | N partial runs at marginal cost |

**The event log isn't a debug log — it's the process itself, reified as data, explorable after the fact.**

---

## 8. Architecture

### 8.1 Tech stack

- **Elixir/OTP** for the control plane and orchestration
- **ETS** for hot metadata (artifact index, cache, run state) — rebuilt from event files on startup
- **Filesystem** for artifact blobs (content-addressed, Git-style sharding)
- **JSONL files** for event logs (one per run, canonical JSON per RFC 8785, hash-chained)
- **`:pg`** (OTP process groups) for event broadcasting — zero-dependency pub/sub
- **Ports/containers/NIFs** for compute plane (heavy ops stay off the BEAM scheduler)
- **Jason** for JSON encoding/decoding (the single non-OTP dependency)

Future additions when needed:
- **Phoenix LiveView** for the observation UI (Phase 4)
- **Oban + Postgres** for scheduled runs (Phase 6)
- **Rust NIFs** (via Rustler) for geometry kernels (House Compiler)
- **LanceDB** for vector index (Radar, file-based, embeddable)

### 8.2 Supervision tree

```
Liminara.Supervisor (one_for_one)
├── Liminara.Artifact.Store          GenServer — owns filesystem blob store
├── Liminara.Event.Store             GenServer — owns JSONL event log directory
├── Liminara.Decision.Store          GenServer — owns decision record directory
├── Liminara.Cache                   GenServer — owns ETS named table
├── :pg (:liminara scope)            OTP process groups for event broadcasting
├── Liminara.Run.Registry            Registry (unique keys: run_id → pid)
└── Liminara.Run.DynamicSupervisor   DynamicSupervisor
    ├── Run.Server ("run-1")         GenServer — owns one run's lifecycle
    │   └── Task.Supervisor          per-run, supervises op Tasks
    │       ├── Task (op "fetch")
    │       ├── Task (op "normalize")
    │       └── ...
    ├── Run.Server ("run-2")
    │   └── Task.Supervisor
    └── ...
```

Each run is an isolated supervision subtree. Crash one run, the others don't notice. Crash an op within a run, the Run.Server decides what to do (retry, fail the node, fail the run). This is free with OTP.

### 8.3 The Run.Server

A GenServer that owns one run's lifecycle. The pattern is always: **record event → update state → check what's ready → dispatch**.

```elixir
defmodule Liminara.Run.Server do
  use GenServer

  def handle_info({:node_completed, node_id, outputs}, state) do
    state =
      state
      |> record_event(:node_completed, %{node_id: node_id, outputs: outputs})
      |> store_artifacts(outputs)
      |> maybe_dispatch_ready_nodes()
    {:noreply, state}
  end

  def handle_info({:gate_resolved, node_id, response}, state) do
    state =
      state
      |> record_event(:gate_resolved, %{node_id: node_id, response: response})
      |> record_decision(node_id, response)
      |> complete_node(node_id, response)
      |> maybe_dispatch_ready_nodes()
    {:noreply, state}
  end
end
```

### 8.4 Executors

Ops declare their executor:

| Executor | Description | Use case |
|----------|-------------|----------|
| `:inline` | Runs in the Run.Server process | Fast, pure Elixir ops (JSON transforms) |
| `:task` | Runs as a supervised Task | Medium ops, still Elixir |
| `:port` | Runs as an OS process via Port | Heavy native code (Rust/C++) |
| `:nif` | Runs as a NIF via Rustler | Geometry kernels needing low-latency interop |
| `:container` | Runs in a Docker container | Isolated environments, external tools |

The runtime doesn't care which executor an op uses. It dispatches, waits for completion, collects artifacts. The executor is a detail of the pack, not the runtime.

### 8.5 What Elixir/OTP brings

**Process isolation.** Each run, each op execution is a separate process. Memory isolation. Crash isolation. No shared mutable state between runs.

**Supervision.** "Let it crash" means you write the happy path and let OTP handle recovery. A network timeout in a fetch op? The task crashes, the supervisor restarts it, the Run.Server retries.

**Concurrency.** Fan-out in the DAG becomes parallel Tasks. The BEAM scheduler handles thousands of lightweight processes without threads, locks, or thread pools.

**Message passing.** The Run.Server communicates with op workers, the artifact store, the event log, and the observation layer all via messages. No shared database connections, no mutex.

**Hot code loading.** Update a pack's op implementations without stopping running runs.

### 8.6 Event broadcasting and observation

Every event the Run.Server records gets broadcast via `:pg`:

```elixir
defp broadcast(run_id, event) do
  :pg.get_members(:liminara, {:run, run_id})
  |> Enum.each(&send(&1, {:run_event, run_id, event}))
end
```

Subscribers can be: a Phoenix LiveView rendering a real-time DAG, an ex_a2ui WebSocket provider, a CLI progress printer, a log writer, a metrics collector. The observation layer is a **consumer** of the event stream, not part of the core. You can run Liminara headless or with a full dashboard.

### 8.7 Observation layer architecture (Phase 4)

```
:pg event stream (from Run.Server)
        │
        ▼
Observation.Server (GenServer per run)
  - subscribes to :pg
  - maintains view model: DAG structure, node states, timing, artifacts, decisions
  - renderer-agnostic
        │
        ├──► Phoenix PubSub ──► LiveView ──► HTML/SVG (primary renderer)
        │
        └──► A2UI Provider ──► ex_a2ui WebSocket ──► A2UI client (experimental)
```

What gets built:
- Phoenix app (`liminara_web`) in the umbrella — LiveView-based, responsive layout
- Runs dashboard — list all runs with live status updates
- SVG-based DAG visualization — nodes, edges, real-time state changes, click-to-inspect
- Node inspector — inputs, outputs, decisions, timing, cache status
- Event timeline — chronological, filterable by type and node

### 8.8 Crash recovery

**Op crash:** An op that raises, exits, or hangs is caught by the Run.Server via `Task.Supervisor.async_nolink`. The Task crashes, Run.Server marks the node as `:failed`, continues dispatching other ready nodes.

**Run.Server crash:** A new server started with the same `run_id` detects existing events in the event log. It rebuilds state: completed nodes from `op_completed` events, failed nodes from `op_failed` events, in-progress nodes reset to `:pending`. The hash chain continues correctly from the last event.

### 8.9 The dependency test

What does the core runtime actually depend on?

```
Elixir/OTP:  ETS, :pg, Registry, Task, GenServer, :crypto, File
External:    Jason (JSON encoding)
```

That's it. No database, no message broker, no web framework. Artifacts on disk, metadata in ETS, events in files, pub/sub via `:pg`.

---

## 9. Data Model

Defined in Phase 0 as a canonical specification that both the Python SDK and Elixir runtime implement. This prevents cross-language drift.

### 9.1 Hash algorithm

```
SHA-256, encoded as "sha256:{64 lowercase hex chars}"
```

Every reference to a stored object — artifact, event, decision — is a SHA-256 hash in this encoding.

### 9.2 Canonical serialization

All structured data is serialized using **RFC 8785 JSON Canonicalization Scheme (JCS)**:

- Keys sorted lexicographically (Unicode code point order)
- No whitespace between tokens
- UTF-8 encoding
- Numbers: no trailing zeros, no scientific notation for integers

This produces a unique, deterministic byte representation for any given JSON value. The SHA-256 of this representation is stable across languages and platforms.

### 9.3 Artifact storage

```
{store_root}/
  {hex[0:2]}/
    {hex[2:4]}/
      {hex}          ← raw bytes, no extension
```

Git-style two-level sharding. Content is raw bytes with no envelope. Identity = `sha256(raw_bytes)`. Write-once: if the file exists, it is identical by definition. Metadata is stored separately in the event log.

### 9.4 Event log

```
{runs_root}/{run_id}/events.jsonl
```

JSONL format — one canonical JSON object per line, `\n`-terminated. Append-only.

Event schema:

| Field | Type | Description |
|-------|------|-------------|
| `event_hash` | string | SHA-256 of canonical JSON of `{event_type, payload, prev_hash, timestamp}` |
| `event_type` | string | One of the defined event types |
| `payload` | object | Event-specific data |
| `prev_hash` | string \| null | `event_hash` of the previous event. `null` for the first event |
| `timestamp` | string | ISO 8601, UTC, millisecond precision |

The `prev_hash` links each event to the previous event's hash. Any modification to any event invalidates all subsequent hashes. This is tamper-evidence without a blockchain.

### 9.5 Run seal

The `event_hash` of the `run_completed` event is the **run seal**. It cryptographically commits to the entire run history.

```
{runs_root}/{run_id}/seal.json
```

### 9.6 Decision records

```
{runs_root}/{run_id}/decisions/{node_id}.json
```

Canonical JSON (RFC 8785). One file per nondeterministic op execution. Fields: `node_id`, `op_id`, `op_version`, `decision_type`, `inputs`, `output`, `recorded_at`, `decision_hash`.

### 9.7 Event types

| Event type | Payload keys |
|------------|-------------|
| `run_started` | `run_id`, `pack_id`, `pack_version`, `plan_hash` |
| `op_started` | `node_id`, `op_id`, `op_version`, `determinism`, `input_hashes` |
| `op_completed` | `node_id`, `output_hashes`, `cache_hit`, `duration_ms` |
| `op_failed` | `node_id`, `error_type`, `error_message` |
| `decision_recorded` | `node_id`, `decision_hash`, `decision_type` |
| `artifact_produced` | `artifact_hash`, `node_id`, `content_type`, `size_bytes` |
| `run_completed` | `run_id`, `outcome`, `artifact_hashes` |
| `run_failed` | `run_id`, `error_type`, `error_message` |

### 9.8 Directory layout

```
{liminara_root}/
  store/
    artifacts/
      {hex[0:2]}/{hex[2:4]}/{sha256_hex}   ← artifact blobs
  runs/
    {run_id}/
      events.jsonl                ← append-only event log
      seal.json                   ← run seal
      decisions/
        {node_id}.json            ← one decision per recordable op
```

---

## 10. Domain Packs

Domain packs are how Liminara becomes useful in specific domains. A pack provides ops and a plan function — the runtime provides everything else (scheduling, caching, replay, crash recovery, event broadcasting).

### 10.1 Pack tiers

| Tier | Packs | Status |
|------|-------|--------|
| **Active** | Report Compiler (fixture), Radar (product), House Compiler (validation) | On the critical path |
| **Hobby** | Software Factory | Learning pack, built at hobby pace |
| **Related** | Process Mining, FlowTime Integration | Build when FlowTime is ready |
| **Far horizon** | Agent Fleets, Population Sim, Behavior DSL, Evolutionary Factory, LodeTime | Aspirations. Documented but not scheduled. |

### 10.2 Report Compiler (toy/test fixture)

The first pack. Exercises every core concept in miniature: pure/recordable/side-effecting ops, gates, binary artifacts, caching, replay. It exists to prove the plumbing works, not to deliver value to users.

### 10.3 Radar / Omvärldsbevakning (first real product)

**Pack ID:** `radar.omvarldsbevakning`

A research intelligence system — not just a newsletter generator. Continuously monitors a curated set of sources (RSS, websites, APIs like Hacker News), detects novelty, clusters themes, and produces briefings with provenance.

**IR pipeline:**

```
Source Plan (IR0) → Source Snapshots (IR1) → Normalized Documents (IR2) →
  Extracted Items (IR3) → Clusters & Rankings (IR4) → Briefing (IR5)
```

**Op catalog:**

| Op | Determinism | Purpose |
|----|-------------|---------|
| `radar.resolve_sources` | Pure | Expand source lists, validate schema |
| `radar.fetch_snapshot` | Pinned env / side-effect | Fetch external URLs, store snapshots |
| `radar.normalize` | Pure | Strip boilerplate, extract text |
| `radar.extract_items` | Recordable | LLM/heuristic entity extraction |
| `radar.cluster_rank` | Pure | Cluster and rank items |
| `radar.summarize_briefing` | Recordable | Generate briefing narrative |
| `radar.publish` | Side-effecting | Deliver briefing (gated in production) |

**Two-layer architecture:**

- **Collection layer** — continuous, persistent, side-effecting. Discovery mode. Produces a growing artifact corpus and vector index.
- **Analysis layer** — triggered (scheduled or on-demand), pipeline mode. Takes an immutable snapshot of the corpus. Fully replayable and cacheable.

**Vector integration:** LanceDB (file-based, embeddable). Embedding is a `pure` op. Semantic search is a `pure` op. Index update is `side_effecting`. The vector index file IS the artifact.

**Key Radar capabilities (beyond basic omvärldsbevakning):**
- Discovers new sources — directed crawler behavior
- Finds connections across adjacent fields — cross-domain semantic proximity
- Serendipity detection — unexpected proximity between corpus items and distant sources
- Historical search — "has this problem been solved before?"

### 10.4 House Compiler (proof of generality)

**Pack ID:** `house_compiler`

Transforms a design (e.g., SketchUp model) into manufacturable outputs: structural analysis, manufacturing plans, PDF drawings, CNC machine files, bills of materials, and compliance artifacts.

Deliberately chosen as the second real pack because it is as far from LLM text processing as possible: geometry kernels, rule engines, optimizers, binary artifacts. If the same five concepts handle both Radar and this, the architecture is genuinely domain-agnostic — not just "an AI orchestrator."

**IR pipeline:**

```
Design Input Snapshot (IR0) → Semantic Building Model (IR1) →
  Structural/Simulation Results (IR2) → Manufacturing Model (IR3) → Outputs (IR4)
```

**DAG structure:**

```
params ──→ semantic ──→ structural ──→ manufacture ──┬──→ drawings (PDF)
                  │         ↑                        ├──→ nc_files (BTL)
location ──→ loads ─────────┘                        └──→ bom
                     [ruleset]
```

**Executors:** Load lookup is `:inline`. Semantic model is `:task`. Structural check is `:port` or `:nif` (Rust/C++). PDF rendering is `:port`. The control plane / compute plane split handles heterogeneous executors naturally.

**Reference data:** Eurocode 5 (structural), SMHI snow loads (geographic), BBR (energy). Registered via `Pack.init/0`, versioned. When regulations change, the pack version updates, cache keys invalidate, designs re-evaluate automatically.

**Has a buyer.**

### 10.5 Software Factory

**Pack ID:** `software_factory`

LLM-assisted software development: planning, code changes, tests, reviews, publishing. Exercises discovery mode — the plan is built step by step as the LLM decides what to do next.

```
task ──→ analyze ──→ [plan_next] ──→ (dynamic: code_gen, test, review, iterate...)
                     expand: true
```

Not competing with Claude Code, Cursor, or Copilot — orchestrating *over* them with provenance and decision recording. You can "replay a coding session" deterministically by loading decisions from a successful run.

### 10.6 FlowTime Integration

**Pack ID:** `flowtime.integration`

FlowTime (github.com/23min/flowtime) is a flow modeling platform: visualizes and simulates how work moves through complex systems. Written in C#/.NET 9, Blazor WebAssembly UI, MCP server.

**The relationship is three integration models:**

1. **FlowTime as an Op executor** — FlowTime is the geometry kernel for flows, the way a structural solver is the geometry kernel for the house compiler. Liminara orchestrates; FlowTime computes.

2. **FlowTime's model-building process as a Liminara pipeline** — Building a FlowTime model from a real system involves choosing what telemetry to ingest (Decision), how to decompose the system (Decision), parameter calibration (Decision), validation against historical data (Op). Liminara orchestrates the construction and evolution of FlowTime models.

3. **Shared philosophical DNA** — Both systems share core convictions about determinism, DAG evaluation, explainability, time as structure, and immutability. They operate at different scales: FlowTime models the continuous operation of a system (thousands of time bins); Liminara models the discrete process of producing an output.

**Natural packs using FlowTime:**

- **System Modeler Pack** — telemetry → AI-assisted model building → validation → calibration → model artifact
- **Capacity Planner Pack** — model → scenario generation → FlowTime simulations → analysis → recommendations
- **Incident Analyzer Pack** — alert → fetch telemetry → replay FlowTime model → identify bottleneck → propose remediation
- **What-If Explorer Pack** — model → parameter variations → batch simulations → comparison → selection

**Process Mining connection:** Process Mining discovers what actually happens (from event logs). FlowTime simulates what could happen. Liminara orchestrates the chain and records decisions at every step. Together: end-to-end from raw telemetry to actionable what-if analysis, with full provenance.

### 10.7 Process Mining

**Pack ID:** `process_mining`

Ingest event logs (XES/OCEL), discover process models, analyze variants/bottlenecks, perform conformance checking. Technology: pm4py (Python, production-ready) as a `:port` executor.

**Meta-level connection:** Liminara's own event logs are exactly the kind of event logs process mining consumes. You could mine Liminara's own execution patterns to optimize pipeline designs — the system analyzing itself.

### 10.8 Far-horizon packs

Documented in `docs/domain_packs/` but not scheduled:

| Pack | Domain |
|------|--------|
| Agent Fleets | Multi-agent coordination |
| Population Simulation | Agent-based modeling |
| Behavior DSL | Behavioral specification language |
| Evolutionary Factory | Genetic algorithms / evolutionary computing |
| LodeTime | Development tooling |
| GA Sandbox | Genetic algorithm test fixture |
| Ruleset Lab | Rule engine test fixture |

---

## 11. Competitive Landscape

### 11.1 The four lanes

The orchestration space has fractured into four distinct lanes. Every one of them treats nondeterminism as someone else's problem:

| Lane | Players | What they do | What they don't do |
|------|---------|-------------|-------------------|
| **Streaming/Integration** | Crosser, n8n, Kafka, Flink | Move data continuously between systems | No artifacts, no provenance, no replay |
| **Data Pipeline** | Dagster, Prefect, Airflow | Schedule batch jobs, asset lineage | No decision recording, no nondeterminism handling |
| **Durable Execution** | Temporal, Restate, Inngest | Make code survive crashes | No content-addressing, no determinism classes |
| **Agent Frameworks** | LangGraph, CrewAI, Burr, Google ADK | Wire up LLM calls | No immutable artifacts, no true replay |

### 11.2 Market validation

| Company | Valuation / Revenue | Signal |
|---------|-------------------|--------|
| **Temporal** | $5B (Series D, $300M) | Durable execution is a proven category |
| **n8n** | $2.5B ($180M Series C) | $40M ARR, 75% of customers use AI features |
| **Dagster** | $49M raised | Software-defined assets ≈ closest philosophical match |
| **Prefect** | $43.6M raised, $13.1M rev | ControlFlow (archived) was closest AI workflow product |
| **Restate** | $7M seed (2024) | "Durable async/await" in Rust |
| **Crosser** | Acquired by AVEVA ~$45-90M | Hybrid streaming/edge, Swedish origin |
| **AWS** | Lambda Durable Functions | Hyperscalers entering the space |

### 11.3 Deep comparison: Burr

Apache Burr (entered incubator May 2025, ~1.4K stars, used by Coinbase, TaskHuman) models applications as state machines, not DAGs.

| Aspect | Liminara | Burr |
|--------|----------|------|
| Graph model | Data-flow DAG (artifacts on edges) | Control-flow state machine (shared state) |
| Core abstraction | Artifact (immutable, content-addressed) | State (immutable updates, single object) |
| Nondeterminism | First-class (4 classes, Decision records) | Invisible (framework-agnostic) |
| Persistence | Event sourcing (append-only log) | State checkpointing (snapshots) |
| Replay | Deterministic (inject stored decisions) | Fork from checkpoint (re-execute, may differ) |
| Caching | Content-addressed (hash of op + input hashes) | Manual / not built-in |
| Cycles | No (DAG; use fixed-point wrapper) | Yes (state machine with loops) |

**Critical insight:** Burr saves state snapshots. Liminara saves events. Event sourcing gives time-travel and "what happened between minute 3 and minute 7" for free. **Burr cannot replay deterministically.** It has no concept of recording nondeterministic choices.

### 11.4 Post-mortem: Prefect ControlFlow

ControlFlow was archived August 2025 (merged into Marvin 3.0). Cautionary lessons:

1. Tight Prefect coupling destroyed standalone usability
2. No deployment strategy
3. Orchestration freezing with >2 tasks
4. Naming collision with Prefect's own concepts
5. Abstracted too heavily toward LLM-driven flows

**Lesson for Liminara:** Keep the core zero-dependency. ControlFlow died partly because of tight coupling.

### 11.5 Decision recording as an emerging need

Several recent projects converge on the problem Liminara addresses:

- **AgentRR** (arXiv:2505.17716, 2025) — Record-and-replay for AI agent frameworks
- **R-LAM** (arXiv:2601.09749, 2026) — Reproducibility-constrained large action models for scientific workflows
- **Sakura Sky's "Missing Primitives for Trustworthy AI"** blog series — describes almost exactly Liminara's architecture
- **LangGraph Time Travel** — Checkpoint-based state replay for debugging
- Academic papers on ML reproducibility, audit trails for LLMs, and scientific workflow provenance

**Nobody has built the full picture.** Content-addressed artifacts + decision records + DAG execution + determinism classes as a unified system does not exist.

### 11.6 Comparative summary

| Capability | Liminara | Burr | ControlFlow | Temporal | Dagster |
|-----------|----------|------|-------------|----------|---------|
| Decision recording | First-class | None | None | None | None |
| Deterministic replay | Yes | No (fork only) | No | No | No |
| Content-addressed artifacts | Yes | No | No | No | Partial (assets) |
| Determinism classes | 4 classes | None | None | None | None |
| Event sourcing | Yes | No (checkpoints) | No | Event history | No |
| OTP supervision | Yes | No (Python) | No (Python) | No (Go) | No (Python) |
| Schema validation on outputs | Gap (should add) | No | Yes (Pydantic) | No | Yes |

---

## 12. Intellectual Ancestors

Liminara sits at the intersection of several intellectual traditions.

### 12.1 The Memex lineage (Bush, Engelbart, Nelson)

**Vannevar Bush — "As We May Think" (1945):** Described the Memex — a device that stored a researcher's library and let them create associative trails through it. The Radar pack is the Memex finally buildable: corpus is content-addressed, the trail is a Liminara run, decisions along the trail are recorded.

**Douglas Engelbart — "Augmenting Human Intellect" (1962):** Wanted to capture the structure of thought, not just conclusions. His NLS had a "journal" — an append-only record of all work. Decision records are Engelbart's journal.

**Ted Nelson — Xanadu:** Content-addressed artifacts are Xanadu-style permanent addressing. The provenance graph is a two-way link.

### 12.2 Formal models

**Petri nets (1962):** A Liminara plan is a workflow net — a well-studied Petri net subclass. Petri net theory gives formal tools for verifying the scheduler.

**Process mining:** Discovers Petri nets from event logs. Liminara produces exactly the kind of event log process mining consumes. Run a pack a hundred times, feed the event logs into pm4py, get back a formal Petri net of your actual process.

**Category theory:** A DAG of typed ops with artifact types is a category. Artifact types are objects, ops are morphisms, composition is pipeline chaining.

**Process calculi (CSP, π-calculus):** Formal languages for concurrent communicating systems. The BEAM's message-passing model descends from CSP.

### 12.3 Content addressing (the family)

| System | What's addressed | Extension over predecessors |
|--------|-----------------|---------------------------|
| **Git** | Files, trees, commits | Revision control via content identity |
| **Nix** | Build inputs (source, compiler, flags) | Reproducible builds via total input-addressing |
| **IPFS** | Content via CID (multihash) | Distributed content-addressed storage |
| **Bazel** | CAS + action cache (command + inputs → outputs) | Scalable hermetic builds |
| **Liminara** | Artifacts + decisions + events | Content-addressing extended to nondeterministic computation |

Liminara extends Nix's model: Nix controls determinism by controlling inputs; Liminara controls determinism by recording choices. That's more general because it handles irreducible nondeterminism.

### 12.4 Hash chains and tamper-evidence

**Certificate Transparency (Google, 2013):** A global, publicly auditable, hash-chained log of TLS certificates. This is the architecture Liminara's event log follows: not a blockchain, but a hash-chained log verifiable by any auditor.

**Merkle trees:** A Merkle root over a run's artifact set enables efficient provenance proofs.

### 12.5 Rich Hickey's ideas

**"Values, not places"** — Immutable values with stable identities make reasoning tractable. Liminara's artifacts are values, identified by hash.

**"The Database as a Value"** — A database where you can ask "what did this look like at time T?" The event log gives Liminara this for every run.

**Datomic** — Event-sourced, append-only database with Datalog queries. The architectural parallel to Liminara's event log + ETS projection is direct.

### 12.6 The technology synthesis pattern

| System | Components | What was new |
|--------|-----------|-------------|
| Git | Content addressing + DAG + SHA-1 | Revision control that works |
| Bitcoin | Hash chains + Merkle trees + proof of work | Distributed trustless consensus |
| BEAM/OTP | Actors + supervision trees + hot code loading | Fault-tolerant telecom |
| Nix | Content addressing + functional builds | Reproducible system configuration |
| **Liminara** | **Content-addressed artifacts + decision recording + event sourcing + OTP + determinism classes** | **Reproducible nondeterministic computation** |

---

## 13. EU AI Act and Compliance

### 13.1 The regulatory tailwind

The EU AI Act entered into force 1 August 2024 with phased enforcement:

| Date | What takes effect |
|------|-------------------|
| 2 Feb 2025 | Prohibited AI practices ban + AI literacy obligations |
| 2 Aug 2025 | Governance rules + GPAI model obligations |
| **2 Aug 2026** | **Main deadline: High-risk AI system requirements enforceable** |
| 2 Aug 2027 | Full scope applies |

### 13.2 Liminara's position

Liminara itself is **minimal risk** under the EU AI Act (infrastructure tooling). But it is the kind of tool that high-risk AI system providers **need** to comply. Compliance enabler, not regulated entity.

### 13.3 Article 12 mapping

Article 12 requires automatic, tamper-resistant logging for all high-risk AI systems. Enforcement: **2 August 2026** (5 months from now).

| Article 12 Requirement | Liminara Feature |
|------------------------|-----------------|
| Automatic event recording | Append-only event log per run |
| Tamper-resistant logs | Content-addressed artifacts + hash-chained events |
| Trace outputs to inputs | DAG of artifacts with content-addressed edges |
| Record model versions | Decision records capture model IDs, prompts, token usage |
| Identify nondeterminism | Determinism classes flag which ops are nondeterministic |
| 6-month retention | Event files on filesystem, retained by policy |
| Facilitate monitoring | Observation layer (real-time event stream) |

Fines for non-compliance: up to EUR 35 million or 7% of global revenue.

### 13.4 Compliance is a consequence, not the product

Liminara's architecture was designed for reproducibility, but it also happens to be exactly what Article 12 requires. The actual value proposition is reproducibility, replay, caching, and decision recording. Compliance falls out for free.

Anyone could build equivalent compliance-only tooling (decorators writing JSONL with hash chains) in a weekend. Liminara's actual value is what compliance alone cannot do: replay, caching, orchestration.

### 13.5 Compliance layer architecture

Three integration models for existing systems:

| Model | Mechanism | Coverage | Effort |
|-------|-----------|----------|--------|
| **SDK / Python Decorator** | Decorate existing functions with `@liminara.op(...)` | Per-function | Lowest |
| **OpenTelemetry Bridge** | Consume OTel spans with Liminara-specific attributes | Full pipeline (if orchestrator emits spans) | Medium |
| **Event Bridge** | Consume rich events from a message bus | Complete DAG provenance | Highest |

### 13.6 The pitch for funding

> "Liminara is a provenance engine for nondeterministic computation — it makes AI-driven workflows reproducible, auditable, and cacheable by recording every nondeterministic choice. Its architecture (content-addressed artifacts, decision records, determinism classes) naturally satisfies EU AI Act Article 12 requirements for automatic, tamper-resistant logging — compliance is a built-in consequence, not a bolt-on."

---

## 14. Build Plan

### 14.1 Development philosophy

**Build a product first and extract the platform second.** Don't build "Liminara the platform" and put Radar on top. Build "Radar the product" and extract the core runtime as it proves itself. The Report Compiler is the test fixture, not the product. Radar is the product.

**Platform emergence model:** Rails from Basecamp. React from Facebook's newsfeed. Terraform from HashiCorp's own infra needs. The platform emerges from the friction of building real things.

### 14.2 Phase sequence

#### Phase 0: Data model definition ✅

Define the on-disk format once: hash algorithm, canonical serialization, event log format, artifact storage layout, decision records. Both the Python SDK and the Elixir runtime implement this model.

#### Phase 1: Python SDK / data model validation

Validate the data model spec by implementing it in Python. The compliance reporting it produces (Article 12 reports, tamper-evidence) is a consequence of the architecture. Primary deliverable: validated data model, runnable demo for pitches.

**Status:** Not started.

#### Phase 2: Elixir walking skeleton ✅

The minimal Elixir runtime exercising every core concept. Zero external dependencies — pure BEAM. Artifact.Store, Event.Store, Plan, Run.Server, Op behaviour.

#### Phase 3: OTP runtime layer ✅

Promote the synchronous walking skeleton into a proper OTP application. Run.Server GenServer, DynamicSupervisor, concurrent fan-out, `:pg` event broadcasting, crash recovery, property-based stress testing.

**Test suite:** 8 properties + 229 tests, 0 failures.

#### Phase 4: Observation layer (current)

See what's happening inside a run. Observation.Server GenServer subscribing to `:pg`, maintaining a view model, publishing updates. Phoenix LiveView for rich UI. SVG-based DAG visualization.

**Status:** Active.

#### Phase 5: Radar pack (first real product)

Daily-use research intelligence system. Real HTTP fetching, real LLM summarization. Oban for scheduled recurring runs. Cache layer. Two-layer architecture: continuous collection + triggered analysis.

#### Phase 6: Oban + Postgres (scheduling)

Scheduled runs, persistent job queues, cross-run queries.

#### Phase 7: House Compiler (proof of generality)

Second real pack in a completely different domain. `:port`/`:nif` executors for heavy compute. Binary artifacts (PDF, NC files). Pack-managed reference data. Fan-out DAG.

#### Beyond Phase 7

| Pack | Trigger |
|------|---------|
| FlowTime ConsultingPack | When FlowTime is consulting-usable AND observation layer is built |
| Software Factory | Hobby pace, after House Compiler |
| Process Mining | When FlowTime is ready for integration |
| Far-horizon packs | When external contributors or customers need them |

### 14.3 What exists today (post-Phase 3)

The runtime can:

- Execute arbitrary DAGs with concurrent fan-out/fan-in
- Record every nondeterministic choice as a decision record
- Replay any run deterministically by injecting stored decisions
- Cache pure operation results across runs
- Pause at gate nodes and resume on external input
- Broadcast every event to subscribers in real-time via `:pg`
- Recover from crashes by rebuilding state from the event log
- Produce tamper-evident, hash-chained event logs in JSONL format
- Store artifacts in a content-addressed filesystem

All on pure BEAM — zero external dependencies beyond Jason.

### 14.4 Module map

```
liminara_core/lib/
├── liminara.ex                    Public API: run/3, replay/4
└── liminara/
    ├── application.ex             OTP Application, supervision tree
    ├── op.ex                      Op behaviour (4 callbacks)
    ├── pack.ex                    Pack behaviour (4 callbacks)
    ├── plan.ex                    DAG data structure + validation
    ├── run.ex                     Synchronous executor + subscribe/unsubscribe
    ├── run/
    │   └── server.ex              GenServer: async executor, gate, crash recovery
    ├── executor.ex                Dispatches op execution
    ├── cache.ex                   ETS-based memoization
    ├── hash.ex                    SHA-256 hashing
    ├── canonical.ex               RFC 8785 canonical JSON
    ├── artifact/
    │   └── store.ex               Content-addressed blob storage
    ├── event/
    │   └── store.ex               Append-only hash-chained JSONL event logs
    └── decision/
        └── store.ex               Decision record storage
```

---

## 15. Licensing and Business Model

### 15.1 License

**Apache 2.0 for the core runtime.**

Rationale:
- Maximum community adoption — no copyleft concerns for corporate users
- EU funding compatible — EIC Accelerator and Vinnova strongly prefer open source
- Includes explicit patent grant
- Does not constrain domain packs — House Compiler, Radar can be proprietary/commercial

### 15.2 Commercial model

The commercial moat is the domain packs and domain expertise, not the runtime code. The runtime being open source accelerates adoption; the domain packs being proprietary preserve commercial value.

What's being sold: the House Compiler is the *product* (revenue). Radar is a *demonstration* and daily-use tool. The platform is the *enabler* of future packs.

### 15.3 Lessons from HashiCorp

HashiCorp built Terraform, Consul, Vault, Nomad, etc. — each solving one infrastructure layer. IPO'd at ~$14B, acquired by IBM for $6.4B.

**What validates Liminara's approach:**
- Starting with a walking skeleton and hardening as patterns emerge
- "One tool per concern, composable" philosophy
- DAG-based, state-tracked, cacheable execution works at massive scale

**What to avoid:**
- Terraform's state file became its Achilles' heel (Liminara's event sourcing is better)
- BSL license change destroyed community trust overnight. License decisions are existential.
- "Compose our tools together" was always harder than the marketing suggested

---

## 16. Funding Paths

### 16.1 Vinnova "Innovative Startups" (start here)

- **Grant:** Up to ~SEK 1M (~EUR 90K)
- **Eligibility:** Swedish AB, max 10 employees
- **Barrier:** Low. Single applicant. Rolling/periodic calls.
- **Fit:** Perfect for early validation funding

### 16.2 EIC Accelerator (the big one)

- **Grant:** Up to EUR 2.5M
- **Equity:** EUR 1-10M (optional)
- **2026 budget:** EUR 634M total
- **TRL required:** 6-8 (working prototype demonstrated)
- **Success rate:** 3-7%
- **Target:** September or November 2026 cutoff (by then MVP should be running)

### 16.3 Horizon Europe (consortium required)

- **Relevant call:** HORIZON-CL4-2026-04-DATA-06 "Efficient and compliant access to and use of data"
- **Budget:** EUR 46.5M (3 projects)
- **Requires:** 3+ partners across multiple countries
- **Contact:** Vinnova NCPs Johan Lindberg, Jeannette Spuhler

### 16.4 AI Factories (free compute)

- Sweden: MIMER AI Factory
- Finland: LUMI AI Factory (accessible to Nordic companies)
- Up to 50,000 GPU hours free

### 16.5 Positioning angles

1. **Reproducibility** — the core value
2. **Compliance as consequence** — Article 12 urgency without being the whole story
3. **Technical differentiation** — combination nobody else offers
4. **Open-source sovereignty** — EU favors open-source for digital sovereignty

---

## 17. What's Deferred

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
| Activatable runs (explicit stop/restart API) | A pack needs runs spanning hours+ |
| Enhanced gate API (webhooks, timeouts, delegation) | Real-world-facing packs need external event resolution |
| MCP client op | FlowTime consulting pack is being built |
| Visual DAG designer | Write tool is a different product entirely; observation (read-only) comes first |
| Schema validation on artifact types | Lesson from ControlFlow — should add |
| Lifecycle hooks / fork API | Lesson from Burr — should add |

---

## 18. Recognized Architectural Patterns

Patterns the existing architecture already supports (or nearly supports) but that aren't on the immediate build path.

### 18.1 Activatable runs (long-running processes)

The Run.Server doesn't need to be alive between events. Event sourcing means any run can be reconstructed from its event log. For long-running processes (supply chains, business workflows):

```
Event arrives (gate resolved, webhook, timer, Oban job)
    → Start Run.Server, rebuild state from event log
    → Dispatch newly ready nodes
    → Execute or wait
    → If nothing to dispatch, stop the GenServer
    → Event log persists on disk. Run state is safe.
```

This is how Ethereum smart contracts work — state persists on chain, computation only happens on activation. Liminara already has every piece: event sourcing, crash recovery, gates. The missing piece is an explicit API for intentional stop/restart.

### 18.2 Gates as a primary mechanism

For long-running and real-world processes, gates become the dominant interaction mechanism:

- Shipment confirmations, inspection results, payment receipts (supply chain)
- Client reviews, sign-offs, feedback (consulting workflows)
- External API callbacks, webhook notifications (integrations)
- Timeout-based progression (auto-approve after N days)

### 18.3 Simulation / live duality

The same DAG can run in two modes:

- **Simulation mode:** All nondeterministic ops use synthetic data or inject stored decisions. Instant. Used for planning, optimization, cost estimation.
- **Live mode:** Ops are gated by real-world events. Takes days/months. Used for tracking actual execution.

Decision records enable: `diff(simulation.decisions, live.decisions)` shows exactly where reality diverged from the plan.

### 18.4 Supply chains as computation

The mapping is structural, not metaphorical:

| Supply chain | Liminara |
|-------------|----------|
| Raw materials | Input artifacts |
| Manufacturing step | Op |
| Quality inspection | Gate (human approval) |
| Bill of materials | Plan (DAG) |
| Purchase order | Run |
| Audit trail | Event log (hash-chained) |
| Recall / trace-back | Artifact provenance |
| Certificate of compliance | Run seal |

A supply chain run might take weeks to months. Between steps, the run is dormant — just an event log on disk. The computation per step is trivial; the elapsed time is determined by the physical world.

### 18.5 Graph execution as a universal pattern

The same structural pattern appears across domains:

| System | Artifact type | Nondeterminism | Time scale |
|--------|--------------|----------------|------------|
| Build systems | Files | Banned | Seconds–minutes |
| Data pipelines | Datasets | Ignored | Minutes–hours |
| Smart contracts | State transitions | Banned | Milliseconds–indefinite |
| Supply chains | Physical goods | Accepted | Days–years |
| Scientific workflows | Datasets, papers | Acknowledged | Hours–weeks |
| **Liminara** | Any (content-addressed) | **First-class. Recorded.** | **Any** |

---

## 19. Open Questions

| Question | Status | Notes |
|----------|--------|-------|
| Hash-chained event log: add to v1 or v2? | Open | Adds tamper-resistance; low overhead |
| W3C PROV export: when? | Open | High interop value for compliance market |
| FlowTime Pack integration: timeline? | Open | Co-evolve; earliest opportunity |
| Funding: Vinnova Innovative Startups | Open | Check next call opening |
| EIC Accelerator Step 1: target date? | Open | September or November 2026 |
| Schema validation on artifact types? | Open | Lesson from ControlFlow |
| "Auditable computation" beyond AI? | Open | Pharma, aerospace, financial services have similar needs |

---

## Origins

The project started as an exploratory conversation about language choice for LLM-assisted generative programming. Key decisions along the way:

1. **Language choice:** Elixir, specifically for OTP supervision trees, fault tolerance, and lightweight processes. A deliberate, contrarian bet on the BEAM's strengths.
2. **Architecture direction:** An "agent runner" with durable event log and checkpoint/resume.
3. **Hybrid interaction model:** Agents support both autonomous and interactive modes via gates.
4. **A2UI discovery:** ex_a2ui (https://a2ui.org/) for declarative, streaming agent UIs.
5. **Scope reduction:** Focus on Radar (omvärldsbevakning) as the first real pack — monitoring sources for developments.
6. **Cost consciousness:** LLM costs matter. Architecture evolved toward "mostly data pipeline, LLM only on cluster representatives."

The recurring tension: building something useful (product: Radar) vs. building a reusable platform (the runtime). Resolution: build Radar first, extract the platform from it.

---

*This document consolidates information from the full `docs/` directory. For details on specific topics, see:*

- *Architecture: `docs/architecture/01_CORE.md`*
- *Build plan: `docs/architecture/02_PLAN.md`*
- *Phase 3 reference: `docs/architecture/03_PHASE3_REFERENCE.md`*
- *Landscape analysis: `docs/analysis/02_Fresh_Analysis.md`*
- *Strategic synthesis: `docs/analysis/10_Synthesis.md`*
- *Why replay: `docs/analysis/05_Why_Replay.md`*
- *EU AI Act: `docs/analysis/03_EU_AI_Act_and_Funding.md`*
- *Compliance layer: `docs/analysis/07_Compliance_Layer.md`*
- *Data model spec: `docs/analysis/11_Data_Model_Spec.md`*
- *Adjacent technologies: `docs/research/ADJACENT_TECHNOLOGIES.md`*
- *FlowTime relationship: `docs/analysis/06_FlowTime_and_Liminara.md`*
- *Graph execution patterns: `docs/research/graph_execution_patterns.md`*
- *Domain packs: `docs/domain_packs/`*
