# FlowTime and Liminara: How They Relate

## What FlowTime Is

FlowTime (github.com/23min/flowtime) is a modeling platform that lets you visualize and simulate how work moves through complex systems — whether that's orders in a supply chain, cases in a service process, patients through a healthcare pathway, or requests between microservices.

You describe your system as a simple model (think: a flow diagram with queues and routing rules), and FlowTime deterministically computes where bottlenecks form, where queues build up, and what happens to throughput over time. It can replay what actually happened based on existing telemetry — measurement data already being collected — and run what-if scenarios: "What happens if we double capacity here?" or "What if volume triples?"

It works for any kind of complex system where measurement data exists, not just IT systems. But FlowTime is more than a simulation tool — it's a shared language, a "flow literacy," for talking about flows, resilience, and risk in a unified way across domains. By bringing telemetry, architecture, scenarios, and business impact into the same model, everyone from engineering to business gets a shared picture of how work moves, where it gets stuck, and what it costs.

Two modes:
- **Engine mode** ("what-is/what-was"): ingest telemetry from a real system, build a model, time-travel through historical state
- **Sim mode** ("what-if"): generate scenarios from templates, explore alternatives

Written in C#/.NET 9 with a Blazor WebAssembly UI and MCP server for AI interaction. Technically: a deterministic discrete-time graph engine — bin-by-bin evaluation across a time grid, topological order, with explicit retry modeling and queue dynamics. Same inputs always produce same outputs.

## The Relationship Isn't Simple

FlowTime is not just a Pack, and it's not just a node in a DAG. There are three integration models, and they're not mutually exclusive.

## Model 1: FlowTime as an Op (Node in the DAG)

The simplest integration. A Liminara pipeline uses FlowTime as a computation engine — one of those "heterogeneous agents" where the runtime doesn't care what's inside.

Example — a **capacity planning pack**:

```
collect_telemetry → build_flowtime_model → run_scenarios → analyze_results → recommend → human_gate → report
```

`build_flowtime_model` and `run_scenarios` are Ops that call FlowTime's API. FlowTime does the flow modeling. Liminara orchestrates the larger process — deciding which scenarios to run (Decision), caching expensive simulation results (Artifact), recording the human approval of recommendations (Decision), and enabling replay ("what if we'd run different scenarios?").

FlowTime is the geometry kernel for flows, the way a structural analysis engine would be the geometry kernel for the house compiler. Liminara doesn't need to understand queue dynamics. It just needs to send artifacts in and get artifacts out.

This works, but it underuses both systems.

## Model 2: FlowTime's Model-Building Process as a Liminara Pipeline

This is more interesting. FlowTime's engine is deterministic — same inputs, same outputs. But the process of **building a FlowTime model from a real system** is not deterministic. It involves:

- Choosing what telemetry to ingest (Decision)
- Choosing how to decompose the system into services/queues/routers (Decision — could be AI-assisted)
- Choosing retry parameters, queue capacities, dispatch schedules (Decisions)
- Validating the model against historical data (Op — deterministic comparison)
- Iterating: adjusting the model when it doesn't match reality (more Decisions)

That model-building process is exactly the kind of thing Liminara orchestrates well — a DAG of operations with genuine nondeterminism that you want to record, replay, and branch.

A **system modeling pack**:

```
ingest_telemetry → detect_services → [AI: propose_model] → validate_against_history →
  [human: adjust_model] → validate_again → [AI: calibrate_parameters] → final_model
```

The output is a FlowTime model definition. The Decisions record how the model was built — which services were identified, what parameters were chosen, what adjustments the human made. Now you can:

- **Branch**: "What if we'd modeled the retry logic differently?" Fork at that decision, get a different model, compare both against historical data.
- **Replay**: When the system changes, replay the model-building process with new telemetry but the same structural decisions. Only the calibration step re-runs.
- **Audit**: Six months later, someone asks "Why does our model assume 3 retries with 500ms backoff?" The event log shows exactly which telemetry data led to that decision.

**Liminara orchestrates the construction and evolution of FlowTime models. FlowTime executes them.**

## Model 3: Shared Philosophical DNA, Complementary Domains

Both systems share core convictions:

| Principle | FlowTime | Liminara |
|-----------|----------|----------|
| Determinism | Same inputs → same outputs, guaranteed | Same inputs + same decisions → same outputs |
| DAG evaluation | Nodes in topological order, bin-by-bin | Ops in dependency order, artifacts flowing between |
| Explainability | Warnings are first-class; wrongness is visible | Event log is the run; every decision recorded |
| Time as structure | Discrete time grid, time-travel through history | Event log is append-only, replayable |
| Immutability | Evaluated bins don't mutate | Artifacts are content-addressed, immutable |

But they operate at different scales of time and abstraction:

- **FlowTime** models the *continuous operation* of a system — thousands of time bins, entity flows per second/minute/hour, queue depths evolving over days. It answers: "How does this system behave over time?"
- **Liminara** models the *discrete process* of producing an output — a DAG of operations that runs once (or is replayed). It answers: "How was this artifact produced, and what choices led here?"

FlowTime is a **microscope** — it looks at the fine-grained dynamics of a system's flow behavior. Liminara is a **workshop** — it orchestrates the process of building, analyzing, and deciding.

## The Concrete Architecture

Given all three models, here's how it would actually be structured:

**FlowTime becomes a first-class executor type in Liminara** — like LLMs, geometry kernels, or rule engines. Not a Pack (too narrow — a Pack is a specific domain pipeline). Not just a single Op (too simple — FlowTime has its own rich internal model). An executor that Packs can use.

Then multiple Packs use FlowTime:

### System Modeler Pack (Model 2)

```
telemetry → AI-assisted model building → validation → calibration → model artifact
```

Decisions: model structure, parameter choices, human adjustments. Output: a FlowTime model definition as an immutable Artifact.

### Capacity Planner Pack (Model 1)

```
model artifact → scenario generation → FlowTime simulation runs → analysis → recommendations
```

Decisions: which scenarios to run, which recommendations to accept. Uses FlowTime as a compute engine.

### Incident Analyzer Pack

```
incident alert → fetch telemetry window → build/replay FlowTime model for that window →
  AI: identify bottleneck → AI: propose remediation → human gate → action
```

Decisions: how to scope the analysis, which remediation to pursue. FlowTime provides the "what happened" view; Liminara orchestrates the "what do we do about it" process.

### What-If Explorer Pack

```
existing model → parameter variations → batch FlowTime simulations →
  comparison analysis → visualization → human: select preferred configuration
```

This is where Liminara's replay branching and FlowTime's simulation combine powerfully. Each what-if is a branch at a decision point. The FlowTime simulations are cached as artifacts. The human explores the decision tree interactively.

## Where FlowTime's Core Vision Fits

FlowTime's vision: observe a complex system through telemetry, have AI help build a deterministic model, then use that model for what-if simulations.

That's a three-phase process:

1. **Observe** — ingest telemetry (side-effecting Op)
2. **Model** — AI constructs a deterministic FlowTime model from observations (recordable Op — the AI's modeling choices are Decisions)
3. **Simulate** — run what-if scenarios against the model (pure Op — deterministic once model is fixed)

Phase 1 is data ingestion. Phase 2 is the creative/nondeterministic step — this is where Liminara's Decision recording is most valuable, because the modeling choices are the things you want to branch on, replay, and audit. Phase 3 is pure computation — FlowTime's strength.

**Liminara provides the orchestration skeleton. FlowTime provides the simulation engine. Decisions record the modeling choices that bridge observation to simulation.**

## Process Mining: The Natural Feeder

The Process Mining Pack (see `docs/domain_packs/05_Process_Mining.md`) is a natural companion to FlowTime. The connection forms a feedback loop:

```
Real system → event logs → Process Mining Pack (discover model)
  → FlowTime (simulate, optimize) → changed process → Real system → ...
```

1. **Process Mining discovers** what actually happens — from XES/OCEL event logs, it discovers Petri nets, DFGs, or BPMN models with variant analysis and bottleneck detection.
2. **FlowTime simulates** what *could* happen — takes a discovered model and runs what-if scenarios (add capacity, change routing, remove bottleneck).
3. **Liminara orchestrates** the entire chain and records decisions at every step: which mining algorithm, which model variant, which simulation parameters, which optimization the human selected.

The Process Mining Pack's `pm.export_flow.v1` artifact type is the bridge — a discovered process model exported in a format FlowTime can ingest as a simulation model. This is where observation meets simulation.

**Meta-level connection:** Liminara's own event logs (JSONL, timestamped, with node IDs and op types) are exactly the kind of event logs process mining consumes. You could mine Liminara's own execution patterns to optimize pipeline designs — the system analyzing itself.

Technology: pm4py (Python, production-ready) as a `:port` executor from the BEAM. No need to reimplement mining algorithms.

## The Combination Is Stronger Than Either Alone

- FlowTime without Liminara can simulate but can't track how or why a model was built.
- Liminara without FlowTime can orchestrate but can't do flow-level simulation.
- Process Mining without either can discover models but can't simulate improvements or record the analysis chain.
- Together: end-to-end system from raw telemetry to actionable what-if analysis, with full provenance.

FlowTime validates a key Liminara claim: that the runtime is domain-agnostic. Flow modeling through queues and services is about as far from "knowledge work" as you can get while still involving AI-assisted decisions. If the same five concepts (Artifact, Op, Decision, Run, Pack) can orchestrate both a radar intelligence pipeline and a FlowTime model-building process, the architecture is genuinely general.
