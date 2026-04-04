# The Liminara Core

## What is Liminara?

**Liminara is a runtime for reproducible nondeterministic computation.**

It records every nondeterministic choice — LLM responses, human approvals, stochastic selections — so any run can be replayed exactly, audited completely, and cached intelligently.

Technically: a directed acyclic graph of operations producing immutable, content-addressed artifacts. Nondeterminism is captured as decision records. The execution engine is supervised by Elixir/OTP.

---

## The mental model

### The build system as a starting point

The best analogy for understanding Liminara is the **build system** — a class of tools that has existed since Stuart Feldman wrote Make at Bell Labs in 1976. Make, and its descendants (Bazel, Nix, Gradle, Buck), all solve the same problem: given a set of inputs and a set of transformation rules, produce the correct outputs — and don't redo work that hasn't changed.

A build system has three concepts: **targets** (things to produce), **rules** (how to produce them), and **dependencies** (what each target needs as input). Here's a Makefile:

```makefile
report.pdf: report.md references.bib
    pandoc report.md -o report.pdf
```

`report.pdf` is a target (an artifact). `pandoc ...` is a rule (an operation). `report.md` and `references.bib` are dependencies (input artifacts). Make walks the dependency graph, builds what's stale, skips what's cached. This model is nearly fifty years old and it scales from a single C program to Google's entire codebase (via Bazel).

Why does this matter for Liminara? Because the core properties of a build system are exactly the properties Liminara needs:

- **Dependency tracking** — know what depends on what, so you can re-execute the minimum necessary when an input changes
- **Caching** — if the inputs haven't changed, don't redo the work
- **Reproducibility** — given the same inputs and rules, get the same output
- **Incrementality** — change one thing, rebuild only what's downstream

These properties are well-understood, battle-tested, and formally sound. Liminara inherits all of them.

### Where build systems stop

But traditional build systems assume all rules are **deterministic** — same inputs, same output, always. This is true for compiling C code or rendering a PDF. It is not true for:

- Asking an LLM to summarize a document (different every time)
- A human approving or rejecting a design (a judgment call)
- A genetic algorithm selecting candidates (stochastic)
- Fetching a web page (changes over time)

These are **nondeterministic** steps — the output depends on *choices* that aren't captured in the inputs. Make can't handle this. Neither can Bazel or Nix. They would either refuse to cache the result (losing the main benefit) or cache it incorrectly (pretending the output is stable when it isn't).

### Make + a tape recorder

Liminara adds one concept to the build system model: the **decision record**. When an operation makes a nondeterministic choice (asks an LLM, picks a GA candidate, waits for human approval), it records that choice. Now:

- **First run (discovery):** Execute operations, make choices, record everything. You end up with a fully-determined DAG.
- **Replay:** Re-execute the same DAG, but inject the stored decisions instead of making new ones. Deterministic.

That's the whole insight. After all decisions are recorded, every run is a deterministic build. Replay is just `make` with cached choices. The nondeterminism hasn't been eliminated — it's been *captured*.

### Excel

Make is the execution model. But the *feeling* I want is closer to Excel:

- You can **see everything** — every value, every formula, every dependency
- You can **trace backwards** — click a cell, see its formula, click its inputs, see their formulas
- You can **change an input** and see what would change downstream

Liminara should have this transparency. The DAG viewer is the spreadsheet. Each node is a cell. Each artifact is a value. Each op definition is a formula. You can inspect anything, trace anything.

### Unix

And the composition model comes from Unix:

- Small operations that do one thing
- A universal interface between them (artifacts, like Unix's text streams)
- Composition via the graph (like pipes, but branching and merging)
- Each operation is isolated (a process, like Unix processes)

### OTP

And the reliability model is pure Elixir:

- Each run is a supervision tree
- Operations crash? Supervisor restarts them
- Run crashes? Resume from the last recorded event
- Everything is isolated. Nothing is silently lost.

---

## Five concepts

The core has five concepts. Not twenty. Five.

### 1. Artifact

An immutable, content-addressed blob.

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

An artifact is a value. It doesn't change. If you have its hash, you have its identity. Same hash = same content, always. Artifacts are the edges in the DAG — they flow between operations.

Small artifacts (JSON, structs, configs) live in ETS (in-memory, fast). Large artifacts (PDFs, NC files, geometry models) live on the filesystem, addressed by hash. Both are content-addressed. No external database needed.

### 2. Op

A typed function: artifacts in, artifacts out.

The pre-Phase 5c runtime represented ops through separate callbacks and helper structs. The canonical contract now being locked in E-20 is `execution_spec/0`, which makes identity, determinism, execution, isolation, and output contracts explicit in one place.

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

The determinism class controls caching and replay:

| Class | Meaning | Cache? | Replay? |
|---|---|---|---|
| `pure` | Same inputs → same output, always | Yes | Re-execute |
| `pinned_env` | Same inputs + same environment → same output | Yes (with env hash in key) | Re-execute with pinned env |
| `recordable` | Nondeterministic, but we record the decision | No | Inject stored decision |
| `side_effecting` | Changes the outside world | No | Must re-execute (or skip) |

Four classes. Clean, exhaustive, actionable.

An op doesn't know about scheduling, retry, supervision, or storage. It's just a function with a truthful execution contract. The runtime handles everything else.

During the M-TRUTH-02 migration, the older `name/0`, `version/0`, `determinism/0`, and tuple-return callback surface still exists in some code paths. That legacy surface is not the contract new work should build on.

### 3. Decision

A recorded nondeterministic choice.

```elixir
%Decision{
  node_id: "summarize_cluster_3",
  op: :llm_summarize,
  input_hash: "sha256:def456...",   # hash of the inputs that led to this choice
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

Human approvals are decisions too. A human gate is just an op with `determinism: :recordable` where the "choice" is whatever the human decided. On replay, the stored decision is injected and the gate is skipped.

GA selections are decisions. LLM responses are decisions. Random seeds are decisions. Anything nondeterministic that affects the DAG is a decision.

### 4. Run

An execution: a plan being walked.

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

A run is fundamentally **an append-only event log**. Everything else — the current state, which nodes are complete, which artifacts exist — is a projection of that log.

Events:

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

Why event sourcing? Because it gives you replay, debugging, and time-travel for free. You can reconstruct the state of a run at any point in its history. You can ask "what happened between minute 3 and minute 7?" The events ARE the run.

**Hash-chained event log:** Each event includes `prev_hash` — the SHA-256 of the previous event. This creates a tamper-evident chain: modifying any event invalidates all subsequent hashes. The final event's hash is the **run seal**, cryptographically committing to the entire run history. This gives EU AI Act Article 12 tamper-evidence as an architectural consequence, not a bolt-on feature. See [11_Data_Model_Spec.md](../analysis/11_Data_Model_Spec.md) for the canonical format.

**On-disk format:** Events are stored as JSONL (one canonical JSON object per line, RFC 8785) in `{runs_root}/{run_id}/events.jsonl`. Canonical JSON ensures deterministic hashing across languages — the same event produces the same hash whether written by the Python SDK or the Elixir runtime.

### 5. Pack

A module that provides ops and knows how to plan work.

```elixir
defmodule Liminara.Pack do
  @callback id() :: atom()
  @callback version() :: String.t()
  @callback ops() :: [module()]
  @callback plan(input :: term()) :: Plan.t()

  # Optional: register reference data (rulesets, material databases, geographic lookups)
  @callback init() :: :ok
end
```

Five callbacks (one optional). A pack tells the runtime:
1. Who it is
2. What version it is
3. What op modules it can perform, each exposing the canonical `execution_spec/0`
4. How to build a plan for a given input
5. (Optional) What reference data it ships with

That's the entire pack contract. No middleware chains, no registration protocols. Just: "here are my ops, here's my data, here's how I plan."

Reference data deserves a note: the house compiler needs material properties, span tables, geographic load maps. These aren't produced by a run — they're **versioned datasets** the pack brings with it. `init/0` registers them as artifacts in the store. Ops reference them as literal inputs. When the pack upgrades and the dataset changes, the version changes, cache keys invalidate, downstream ops re-execute automatically. Clean — the cache mechanics handle versioned knowledge for free.

---

## The plan: a DAG you can read

A plan is a graph of nodes. Each node names an op and declares its inputs — either literal values or references to other nodes' outputs. Here's the Radar pack — a research intelligence pipeline that fetches sources, normalizes them, deduplicates, summarizes with an LLM, and delivers a briefing:

```elixir
# Radar pack plan
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

You can read this. Five nodes, a linear pipeline. The determinism classes tell you exactly what's cacheable (everything except the LLM summarization) and what's nondeterministic (the summarization — recorded as a decision).

But not all plans are linear. The architecture must handle branching, fan-out, and heterogeneous workloads. The **house compiler** is a deliberately chosen stress test — a pack that compiles architectural parameters into structural analysis, manufacturing plans, PDF drawings, CNC machine files, and bills of materials. It is as far from LLM text processing as possible, which is exactly why it's the second real pack: if the same five concepts handle both, the architecture is genuinely domain-agnostic.

```elixir
# House compiler plan — branching DAG with fan-out
Plan.new()
|> Plan.node(:loads,      :lookup_loads,         location: literal(location))
|> Plan.node(:semantic,   :build_semantic_model, params: literal(params))
|> Plan.node(:structural, :structural_check,     model: ref(:semantic), loads: ref(:loads), ruleset: literal(ruleset))
|> Plan.node(:thermal,    :thermal_check,        model: ref(:semantic), ruleset: literal(ruleset))
|> Plan.node(:mfg,        :manufacture_plan,     model: ref(:semantic), structural: ref(:structural))
|> Plan.node(:drawings,   :render_drawings,      mfg: ref(:mfg))
|> Plan.node(:nc,         :render_nc,            mfg: ref(:mfg))
|> Plan.node(:bom,        :extract_bom,          mfg: ref(:mfg))
```

```
                    [location]
                        │
[params] → semantic ────┤──→ structural ──→ manufacture ──┬──→ drawings
                        │         ↑            ↑          ├──→ nc_files
                        └──→ thermal    [ruleset]         └──→ bom
```

Same model. Same scheduler loop. But now with fan-out (manufacture → three parallel outputs), fan-in (structural depends on both semantic and loads), binary artifacts (PDFs, NC files), and heavy compute ops running via `:port` or `:nif` executors. The plan IS the documentation.

For discovery mode (agents that decide what to do next):

```elixir
# Software factory — plan is discovered step by step
Plan.new()
|> Plan.node(:analyze, :analyze_task,   task: literal(task_description))
|> Plan.node(:next,    :plan_next_step, analysis: ref(:analyze), expand: true)
```

The `expand: true` flag means: this node's output includes new nodes to add to the plan. The scheduler adds them and keeps going. Same loop, same infrastructure.

**Two modes, one mechanism:**

| | Pipeline mode | Discovery mode |
|---|---|---|
| Plan | Known upfront | Built incrementally |
| DAG | Static | Growing |
| Examples | Radar, house compiler | Software factory, agent fleets |
| Planning | Once, before execution | Interleaved with execution |
| Result | Same thing: a DAG of artifacts with recorded decisions |

---

## The scheduler: ten lines

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

Find nodes whose inputs are all available. Dispatch them. Collect results. Repeat. That's the scheduler.

Each dispatched node becomes a supervised Task (for short ops) or a GenServer (for long-running/streaming ops). When it completes, it sends a message back to the Run server, which records the event and re-evaluates.

This loop handles:
- **Linear pipelines** — each node resolves one at a time
- **Fan-out** — multiple nodes become ready simultaneously, dispatched in parallel
- **Fan-in** — a node waits until all upstream nodes complete
- **Discovery** — an `expand` node adds new nodes, which the loop picks up next iteration
- **Gates** — a gated node stays in `:waiting` until a human resolves it
- **Failure** — a failed node triggers the run's error policy (retry, skip, fail)

No special cases. The loop is the same for all workload shapes.

---

## How it maps to OTP

This is where Elixir earns its keep.

### Supervision tree

```
Liminara.Supervisor
├── Liminara.Artifact.Store          # ETS tables + filesystem, content-addressed
├── Liminara.Event.Store             # append-only event files
├── Liminara.Run.Registry            # maps run IDs to processes (Registry)
├── Liminara.Run.DynamicSupervisor   # supervises active runs
│   ├── Run.Server (run_abc)         # manages one run
│   │   └── Op.TaskSupervisor        # supervises op executions
│   │       ├── Task (fetch)
│   │       ├── Task (normalize)
│   │       └── ...
│   ├── Run.Server (run_def)
│   └── ...
├── Liminara.A2UI.Supervisor         # optional: ex_a2ui observation layer
│   └── ExA2UI.Server                # WebSocket server (Bandit)
└── Oban.Supervisor                  # optional: add when you need scheduling
```

Everything above the optional line is zero-dependency — pure BEAM, no external services. The walking skeleton needs only the first four children. ex_a2ui and Oban plug in when you're ready for them.

Each run is an isolated supervision subtree. Crash one run, the others don't notice. Crash an op within a run, the Run.Server decides what to do (retry? fail the node? fail the run?). This is free with OTP — you don't build it, you get it.

### The Run.Server

A GenServer that owns one run's lifecycle:

```elixir
defmodule Liminara.Run.Server do
  use GenServer

  # A node completed — record event, check what's ready next
  def handle_info({:node_completed, node_id, outputs}, state) do
    state =
      state
      |> record_event(:node_completed, %{node_id: node_id, outputs: outputs})
      |> store_artifacts(outputs)
      |> maybe_dispatch_ready_nodes()

    {:noreply, state}
  end

  # A node failed — apply error policy
  def handle_info({:node_failed, node_id, error}, state) do
    state =
      state
      |> record_event(:node_failed, %{node_id: node_id, error: error})
      |> apply_error_policy(node_id, error)

    {:noreply, state}
  end

  # Human resolved a gate — record decision, unblock node
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

The pattern is always: **record event → update state → check what's ready → dispatch**. Every message follows this shape. The event log grows monotonically. State is derived.

### What Elixir is genuinely good at here

**Process isolation.** Each run, each op execution is a separate process. Memory isolation. Crash isolation. No shared mutable state between runs. This is the #1 reason to use the BEAM.

**Supervision.** The "let it crash" philosophy means you write the happy path and let OTP handle recovery. A network timeout in a fetch op? The task crashes, the supervisor restarts it, the Run.Server retries. You don't write try/catch/retry logic — you write supervision policies.

**Concurrency.** Fan-out in the DAG becomes parallel Tasks. The BEAM scheduler handles thousands of lightweight processes without threads, locks, or thread pools. GA optimization with 100 candidates? Spawn 100 Tasks. Done.

**Message passing.** The Run.Server communicates with op workers, the artifact store, the event log, and the observation layer all via messages. No shared database connections, no mutex, no race conditions by construction.

**Hot code loading.** Update a pack's op implementations without stopping running runs. Deploy a new version of the structural checker while the radar is mid-run. OTP supports this natively.

### What Elixir is NOT good at here

**Heavy computation.** Eurocode 5 structural calculations with floating point? Geometry kernel operations? PDF rendering? These should NOT run on the BEAM scheduler — they'd block it and degrade all other processes.

**Solution:** Ops declare their executor:
- `:inline` — runs in the Run.Server process (fast, pure Elixir ops like JSON transforms)
- `:task` — runs as a supervised Task (medium ops, still Elixir)
- `:port` — runs as an OS process via Port (heavy native code, Rust/C++)
- `:nif` — runs as a NIF via Rustler (geometry kernels that need low-latency interop)
- `:container` — runs in a Docker container (isolated environments, external tools)

The runtime doesn't care which executor an op uses. It dispatches, waits for completion, collects artifacts. The op's executor is a detail of the pack, not the runtime.

---

## Caching: Bazel's gift

Caching falls out naturally from content addressing and determinism classes.

```
cache_key = hash(op_name, op_version, hash(input_artifacts), env_hash?)
```

On execution:
1. Compute cache key from op + inputs (+ environment for `pinned_env` ops)
2. Check if a result exists for this key
3. **Hit:** skip execution, return cached artifacts. Emit `node_completed` with `cached: true`.
4. **Miss:** execute, store result, index by cache key.

| Determinism | Cache behavior |
|---|---|
| `pure` | Always check cache. Always safe. |
| `pinned_env` | Check cache with env hash. Safe if env matches. |
| `recordable` | Don't cache. Always execute, record decision. |
| `side_effecting` | Don't cache. Always execute. |

This is Bazel's model (action cache + CAS), applied to knowledge work. It means:

- Re-running the radar with the same sources? All pure ops are cached. Only the LLM summarization re-executes (and might produce a different briefing, which gets recorded as a new decision).
- Tweaking the house roof pitch from 27° to 30°? The load lookup is cached (same location). The semantic model re-runs. Structural check re-runs. Everything downstream re-runs. Everything upstream is cached.
- Replaying a run with stored decisions? Every node is either cached (pure/pinned) or injected (recordable). Nothing actually executes. Instant replay.

---

## Observation: the Excel quality

Every event the Run.Server records gets broadcast via Erlang's `:pg` (process groups) or `Registry`:

```elixir
defp record_event(state, type, payload) do
  event = %Event{type: type, payload: payload, timestamp: DateTime.utc_now()}
  Event.Store.append(state.run_id, event)
  broadcast(state.run_id, event)
  %{state | events: [event | state.events]}
end

defp broadcast(run_id, event) do
  :pg.get_members(:liminara, {:run, run_id})
  |> Enum.each(&send(&1, {:run_event, run_id, event}))
end
```

No Phoenix needed. `:pg` is built into OTP — zero dependencies for pub/sub. Any process that joins the group receives events. Subscribers can be:

- An **ex_a2ui provider** that translates events into declarative UI components over WebSocket
- A CLI process that prints progress
- A log writer
- A metrics collector

The A2UI layer (via [ex_a2ui](https://github.com/23min/ex_a2ui)) translates events into declarative JSON components:

```
node_started  → spinner on node, "Running structural check..."
node_completed → green checkmark, artifact preview
gate_requested → interactive form, "Approve these assumptions?"
decision_recorded → decision badge with expandable details
```

ex_a2ui runs on Bandit + WebSock — lightweight, no framework overhead. One process per connection, supervised by OTP. The observation UI is just another A2UI provider, started alongside the runtime or not at all.

The observation layer is a **consumer** of the event stream, not part of the core. You can run Liminara headless (just events to a log file) or with a full A2UI dashboard. The core doesn't know or care.

This is the Excel quality: everything is visible, traceable, inspectable. Click a node, see its op definition, its inputs (with hashes), its output, its decision (if any). Click an artifact, see where it came from, what consumed it. Click a run, see the DAG with all values displayed.

---

## Replay: discovery vs re-execution

The user's own framing is the clearest:

> "Once the non-deterministic parts have been made, then we get a DAG. On the replay we just replay the decisions, we don't have to discover them."

Two modes:

**Discovery** (first run):
1. Execute the plan
2. When an op is nondeterministic, let it make its choice
3. Record the decision
4. Continue
5. Result: a fully-determined DAG + a log of decisions

**Replay** (subsequent runs):
1. Load the decision log from a previous run
2. Execute the plan
3. When an op is nondeterministic, inject the stored decision instead of making a new choice
4. Continue
5. Result: identical output (if pure/pinned ops are deterministic)

That's it. No complex replay taxonomy. Discovery records decisions, replay injects them. The same scheduler loop handles both — the only difference is whether `recordable` ops call their executor or read from the decision store.

**What "selective refresh" becomes:** You want to re-run one op with new logic but keep everything else? Load the decision log, mark that one op as "force re-execute" (don't inject its decision), and re-run. Downstream ops will re-execute because their input hashes changed. Upstream ops will cache-hit because their inputs didn't change. The DAG structure handles this naturally — no special replay mode needed.

---

## How the domain packs map

The acid test: do the domain packs fit naturally, or does the model bend? Three packs, chosen to cover maximum architectural variety — an LLM text pipeline, a computational engineering compiler, and an agentic coding assistant.

### Radar (research intelligence)

```
sources ──→ fetch ──→ normalize ──→ dedup ──→ rank+summarize ──→ deliver
         (pinned)    (pure)       (pure)    (recordable/LLM)   (side_effect)
```

- **Plan:** Static pipeline, known upfront. Pipeline mode.
- **Nondeterminism:** LLM summarization is `recordable`. Everything else is deterministic.
- **Scheduling:** Oban cron job triggers a run every N hours.
- **Caching:** Source snapshots cached by URL+timestamp. Normalization cached by content hash. Only summarization re-executes.
- **Observation:** A2UI shows: sources fetched → documents normalized → briefing generated → delivered.
- **Gate:** Optional approval before delivery ("review briefing before sending").

**Fit: perfect.** This is a straightforward pipeline.

### House compiler (proof of generality)

The house compiler is deliberately chosen as the second real pack because it is as far from LLM text processing as possible: it takes architectural parameters and compiles them into structural analysis, manufacturing plans, PDF drawings, CNC machine files, and bills of materials. No LLMs in the core pipeline. Heavy computation. Binary artifacts. If the same five concepts handle both Radar and this, the architecture is general — not just "an AI orchestrator."

```
params ──→ semantic ──→ structural ──→ manufacture ──┬──→ drawings (PDF)
                  │         ↑                        ├──→ nc_files (BTL)
location ──→ loads ─────────┘                        └──→ bom
                     [ruleset]
```

- **Plan:** Static DAG with fan-out. Pipeline mode.
- **Nondeterminism:** Almost none in the core pipeline. GA optimization (if used) is `recordable`. Design ambiguity resolution is `recordable`.
- **Executors:** Load lookup is `:inline` (database query). Semantic model is `:task` (Elixir). Structural check is `:port` or `:nif` (Rust/C++). PDF rendering is `:port` (external tool). NC generation is `:task` (Elixir, format writing).
- **Caching:** Load lookup cached by location. Structural check cached by (model_hash, loads_hash, ruleset_hash, solver_version). Change the roof pitch → semantic model cache miss → everything downstream re-runs → loads cache hit.
- **Observation:** A2UI shows: model built → structural OK/FAIL → manufacturing plan → outputs generated. Inspector views for each IR stage.
- **Artifacts:** Mix of JSON (semantic model, BOM), binary (PDF, NC files), and structured data (structural report). All content-addressed.

**Fit: natural.** The compiler-pass model maps literally. Each IR stage is a node in the DAG. The control plane / compute plane split handles the heterogeneous executors.

**The convergence issue:** Structural sizing affects thermal performance, which might affect structural sizing. This is a coupled loop, not a DAG. Two options:

*Option A: Fixed-point wrapper.* The pack's `plan/1` generates a subgraph that runs iteratively until outputs stabilize:

```elixir
Plan.node(:converge, :fixed_point,
  subgraph: [:semantic, :structural, :thermal],
  max_iterations: 3,
  convergence_check: &artifacts_unchanged?/2
)
```

The runtime treats `fixed_point` as a special op that manages a sub-DAG internally. It runs the subgraph, checks convergence, re-runs if needed. From the outside, it's one node.

*Option B: Constraint propagation as a pre-pass.* Add a `:derive_constraints` node before the main pipeline that analytically derives minimum requirements (e.g., climate zone 1 → minimum 200mm insulation → minimum stud depth). The main pipeline runs once with these constraints pre-baked. No iteration needed for 90% of cases.

I'd start with Option B (simpler) and add Option A only if real designs need it.

### Software factory

```
task ──→ analyze ──→ [plan_next] ──→ (dynamic: code_gen, test, review, iterate...)
                     expand: true
```

- **Plan:** Discovered step by step. Discovery mode.
- **Nondeterminism:** LLM decisions throughout. All `recordable`.
- **Gates:** "Review this code before committing" — human approval gate.
- **Observation:** A2UI shows the growing DAG: each step appears as the agent decides what to do next.
- **Replay:** Load decisions from a successful run. The same sequence of LLM choices produces the same code. You can "replay a coding session" deterministically.

**Fit: good, with a caveat.** The discovery model works. The caveat: an agent that makes 50 sequential LLM calls produces a very long, thin DAG with 50 decision records. This is fine for the runtime, but the UX needs to compress this into a meaningful view (not 50 individual nodes). The A2UI layer should group sequential discovery steps into "episodes."

### Verdict

All three packs map onto the model without bending it. The same five concepts (Artifact, Op, Decision, Run, Pack), the same scheduler loop, the same event log, the same caching semantics. The differences are in:
- Which executor ops use (inline vs port vs NIF)
- Whether the plan is static or discovered
- How much nondeterminism there is
- What the artifacts look like (JSON vs binary)

These are all variation points that the model handles naturally. No special cases.

---

## What's actually hard

Honesty section. Where does this get difficult?

### 1. The artifact store under load

Every op produces artifacts. Every artifact gets hashed and stored. For a GA optimization with 100 candidates × 50 generations, that's 5,000+ artifacts per run. For radar with 200 sources, thousands of artifacts per day.

The store itself is simple (hash → blob). The hard part is the **metadata index** — querying provenance chains, finding cache hits, garbage collecting unreferenced artifacts.

**What I'd do — the BEAM-native storage stack:**

```
Hot data:    ETS          (artifact metadata, cache index, run state)
Blobs:       Filesystem   (hash → file, Git-style: /store/a1/b2/a1b2c3...)
Events:      JSONL files  (one file per run, canonical JSON per line — see 11_Data_Model_Spec.md)
Persistence: DETS or periodic ETS dump (rebuild from event files on startup)
```

Why ETS over SQLite/Postgres? ETS is built into the BEAM. Concurrent reads from any process. No serialization overhead. No external dependency. For a single-node system, ETS is the natural choice for all hot metadata — artifact indexes, cache lookups, run state projections.

The trick: ETS is in-memory, lost on restart. But since the event log is the source of truth, you rebuild ETS tables on startup by replaying event files. This takes milliseconds for thousands of events. The event files are the durable store; ETS is the fast read cache.

For artifact blobs: filesystem, always. Content-addressed files (`/store/a1/b2/a1b2c3d4e5...`). Stream large files through `:crypto.hash_update` — never load multi-MB blobs into BEAM process heaps.

**When to add Postgres:** When you need Oban (scheduled jobs) or cross-run queries that ETS can't handle efficiently ("find all artifacts of type X produced in the last 30 days across all runs"). That's weeks or months away. ETS + files gets you very far.

**Mnesia?** Mnesia adds persistence and distribution to ETS, which sounds perfect. In practice: Mnesia has sharp edges with large datasets, fragile network partition handling, and a learning curve that's not worth it for a single-node system. If you need persistent ETS, use DETS (simple disk-backed ETS) or just replay from event files. Save Mnesia for if/when you actually need multi-node state.

Add GC only when storage becomes a problem (it won't be for months — storage is cheap).

### 2. Large binary artifacts

PDFs, NC files, geometry models don't fit nicely in a database row. They need streaming writes, streaming reads, and content hashing without loading into BEAM memory.

**What I'd do:** Store large artifacts as files on disk, referenced by hash. Stream through a hashing function on write (`IO.stream` + `:crypto.hash_update`). Never load a multi-MB file into an Elixir process heap.

### 3. Nondeterminism recording granularity

An LLM call with tool use is a tree of nondeterminism: the LLM chose a response, which included a tool call, which returned a result, which the LLM responded to. Do you record the whole thing as one decision, or each step separately?

**What I'd do:** Record at the **op boundary**. An op that calls an LLM is one decision record, regardless of how many internal tool-use steps happened. The op is the unit of nondeterminism for the runtime. If you need finer granularity, the op can store sub-decisions in its output artifact.

### 4. Environment pinning for `pinned_env` ops

"Same environment" means same Elixir version, same NIF library version, same Rust toolchain, same OS, same CPU architecture (for float determinism). How do you capture and verify this?

**What I'd do:** Define an `%Environment{}` struct that captures the relevant versions. Hash it. Include the hash in cache keys for `pinned_env` ops. Let each op declare what parts of the environment it depends on — the structural checker depends on the solver version, the PDF renderer depends on the rendering engine version, etc.

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

### 5. The software factory's long chains

An agent that makes 50 sequential decisions produces a 50-node chain. Each node depends on the previous. No parallelism possible. The run takes 50× the latency of one LLM call.

This isn't a bug — it's inherent to the workload. You can't parallelize sequential reasoning. But you can:
- Stream intermediate results to the UI (so the user sees progress)
- Cache pure computation between LLM calls
- Use gates to let humans redirect the chain early

### 6. Pack-managed reference data

The house compiler needs material databases, span tables, geographic load maps. These aren't artifacts produced by a run — they're **versioned datasets** that packs bring with them. This is handled by the pack `init/0` callback (see Pack contract above). Reference data becomes artifacts in the store, and the cache mechanics handle version transitions automatically.

```elixir
# In HouseCompiler.Pack.init/0:
Artifact.Store.register(:eurocode5_se_annex, "v12", eurocode_data())
Artifact.Store.register(:smhi_snow_loads, "2026-01", snow_data())
Artifact.Store.register(:bbr_energy_reqs, "v31", bbr_data())
```

When BBR transitions to new regulations (July 2026), you update the pack version, `init/0` registers the new ruleset, cache keys change, and every design re-evaluates against the correct rules. The runtime doesn't need to know about Swedish building codes — it just sees versioned artifacts.

---

## What's deferred

From the original brainstorm specs, deferred until needed:

1. **Multi-tenancy enforcement.** The data model carries `tenant_id` from day one, but it's always `"default"`. Namespace isolation, auth, and quotas are added when the second customer exists. The schema is ready; the enforcement layer waits.

2. **Distributed execution.** Single BEAM node. Distributed Erlang is a trap — easy to start, brutal to debug. If you need more compute, use `:port` or `:container` executors to call remote services. The control plane stays local.

3. **The Wasm executor.** No practical value yet. `:port` and `:container` cover every real use case.

4. **Discovery mode.** Massively more complex than pipeline mode. Defer until pipeline mode is proven. Ops can internally use loops; the runtime always sees a DAG trace.

5. **The three-mode replay taxonomy.** Discovery + replay is sufficient. "Verify" and "selective refresh" are optimizations you can add later by varying which decisions to inject vs re-execute.

6. **The complex executor contract.** Ops are functions. They receive input artifacts (by hash or by value), produce output artifacts, and optionally record decisions. That's the contract. No heartbeats, no resource negotiation, no streaming protocols in v0.

7. **Budget enforcement.** Track costs (log LLM token usage, wall-clock time). Don't enforce limits in v0. Enforcement is a policy layer you add after you understand your actual cost patterns.

**Domain pack tiers** (see [10_Synthesis.md](../analysis/10_Synthesis.md) § 8 for full rationale):

| Tier | Packs | Status |
|------|-------|--------|
| Active | Report Compiler (fixture), Radar (product), House Compiler (validation) | On the critical path |
| Hobby | Software Factory | Learning pack, built at hobby pace after House Compiler |
| Related | Process Mining, FlowTime Integration | Build when FlowTime is ready |
| Far horizon | Agent Fleets, Population Sim, Behavior DSL, Evolutionary Factory, LodeTime | Aspirations, documented in `docs/domain_packs/` |

---

## Build sequence

See [02_PLAN.md](02_PLAN.md) for the living build plan with current phase, sequencing, and deferral triggers.

The key architectural insight for sequencing: the walking skeleton needs **zero external dependencies** — pure BEAM (ETS, `:pg`, Registry, Task, GenServer, `:crypto`, File). Postgres arrives with Oban (scheduling). Everything else plugs in when needed.

---

## The dependency test

What does the walking skeleton actually depend on?

```
Elixir/OTP:  ETS, :pg, Registry, Task, GenServer, :crypto, File
External:    nothing
```

That's it. The core runtime is pure BEAM. No database, no message broker, no web framework. Artifacts on disk, metadata in ETS, events in files, pub/sub via `:pg`. You can `mix new liminara` and start building.

ex_a2ui adds: Bandit, WebSock, Jason. Three small deps for the observation UI.
Oban adds: Postgres. One external service, only when you need scheduling.

The dependency count is a proxy for operational complexity. A system that needs Postgres + Redis + Elasticsearch + a web framework to start is a system that fights you. A system that needs the BEAM and a filesystem is a system that works.

---

## The elegance test

Is this system simple enough?

**Five concepts** — Artifact, Op, Decision, Run, Pack. Can you hold them all in your head? Yes.

**One execution model** — find ready nodes, dispatch, collect, repeat. Can you explain it to someone in two minutes? Yes.

**One data structure** — the append-only event log. Everything else is derived. Can you debug a run by reading its events? Yes.

**Zero external dependencies** for the core. ETS + filesystem + OTP. Add Postgres and ex_a2ui when you need them, not before.

**Three analogies** that reinforce the mental model:
- It's **Make** for the execution model (DAG of targets with rules)
- It's **Excel** for the observation model (everything visible and traceable)
- It's **OTP** for the reliability model (supervision, isolation, recovery)

**One principle** that ties it together: after all decisions are recorded, every run is a deterministic build. Nondeterminism is not chaos — it's just decisions you haven't recorded yet.

---

*See also:*
- *[02_PLAN.md](02_PLAN.md) — living build plan and sequencing*
- *[../analysis/10_Synthesis.md](../analysis/10_Synthesis.md) — settled strategic decisions*
- *[../analysis/11_Data_Model_Spec.md](../analysis/11_Data_Model_Spec.md) — canonical on-disk format (Phase 0)*
- *[../analysis/07_Compliance_Layer.md](../analysis/07_Compliance_Layer.md) — compliance integration architecture*
