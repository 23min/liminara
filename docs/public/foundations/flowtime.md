# FlowTime Integration — System Flow Modeling and What-If Analysis

**Can we record the reasoning behind a system model, not just the simulation results?**

Research | [FlowTime](https://github.com/23min/flowtime), discrete-time simulation, bottleneck analysis, model provenance, .NET interop

---

## The scenario

Norrland Logistik runs three warehouses along the E4 corridor between Sundsvall and Umeå, handling parcel sorting and last-mile dispatch for Nordic e-commerce. Six months ago they migrated from their legacy WMS to a cloud-based system. Since the migration, throughput at the Härnösand hub has dropped 30%. Parcels that used to clear sorting in 45 minutes now take over an hour. The backlog builds through the afternoon and doesn't clear until the night shift.

They have telemetry — timestamps on every scan event, queue depths from the conveyor PLCs, processing times per sorting station. Thousands of data points per hour. But the data tells them *what* is slow, not *why*. The operations manager suspects the new system's batch-processing interval is too long. The IT team thinks it's a network latency issue. The shift supervisor says they just need a second sorting line.

Everyone has a theory. Nobody has a model. And nobody can test their theory without spending money.

---

## Three integration models

FlowTime and Liminara relate in three ways simultaneously. They are not mutually exclusive — they compose.

### Model 1: FlowTime as computation engine

The simplest view. FlowTime is a `:port` executor — a C#/.NET 9 process that Liminara calls through stdin/stdout, the same way the House Compiler calls a Rust geometry kernel. Artifacts go in, simulation results come out. Liminara doesn't understand queue dynamics. It doesn't need to.

### Model 2: Model-building as a Liminara pipeline

More interesting. FlowTime's simulation is deterministic — same model, same inputs, same outputs. But *building the model from a real system* is not deterministic. It involves genuine choices: how to decompose the system into services and queues, what retry parameters to assume, where to draw boundaries. These are decisions worth recording.

### Model 3: Shared philosophical DNA

Both systems share core convictions — determinism, DAG evaluation, immutability, explainability, time as structure — but operate at different scales. FlowTime is a microscope (fine-grained flow dynamics over continuous time). Liminara is a workshop (discrete process of producing and deciding). They complement rather than compete.

FlowTime and Liminara share an author and are co-evolving. FlowTime is written in C#/.NET 9 with a Blazor WebAssembly UI.

---

## The pipeline

```
PHASE 1: INGEST AND MODEL (decisions are here)
══════════════════════════════════════════════════════════════════

telemetry ──→ ingest ──→ detect_services ──→ propose_model ──→ validate ──→ calibrate ──→ model
(PLC logs,    (side-      (pure)              (recordable)      (pure)       (recordable)
 scan events,  effecting)
 timestamps)

                           │                   │                              │
                           │  identified:       │  AI proposes:                │  parameter fit:
                           │  5 services        │  "inbound dock modeled       │  sorting station
                           │  3 queues          │   as M/D/2 queue,            │  μ = 47s (±3s)
                           │  2 routers         │   sorting as 4 parallel      │  confidence: 94%
                           │                    │   servers with shared         │
                           │                    │   input queue"                │  DECISION RECORDED
                           │                    │  DECISION RECORDED            │  (seeds, iterations,
                           │                    │                               │   convergence path)


PHASE 2: SIMULATE AND COMPARE (computation is here)
══════════════════════════════════════════════════════════════════

model ──→ scenario_baseline ──→ ┐
           (pure)               │
                                ├──→ compare ──→ recommend ──→ report
model ──→ scenario_second_line ─┤     (pure)     (recordable)   (pure)
           (pure)               │
                                │
model ──→ scenario_batch_fix ───┘
           (pure)

           │                          │                │
           │  FlowTime simulates:      │  throughput     │  LLM synthesizes:
           │  24h of warehouse ops     │  comparison:    │  "Second sorting line
           │  at 1-minute granularity  │                 │   improves throughput 22%
           │  1440 time bins           │  baseline: 847  │   but batch interval fix
           │  deterministic            │  +line:   1034  │   recovers 26% at 1/10th
           │                           │  +batch:  1068  │   the cost"
           │                           │                 │
           │                           │                 │  DECISION RECORDED
```

**Phase 1 — Ingest and Model:**

- `ingest` (side-effecting): Pull 7 days of telemetry from Härnösand's PLC historian and WMS API. 2.3M scan events, 168 hourly queue depth snapshots.
- `detect_services` (pure): Statistical decomposition of the scan event stream into logical services. Identifies: inbound dock, primary sort, secondary sort, dispatch buffer, outbound dock. Three queues between them. Two routing points (parcel type → sort line).
- `propose_model` (recordable): AI examines the detected services and proposes a FlowTime model structure — queueing disciplines, server counts, routing rules. This is the creative step. The AI's choices are recorded as a decision: "modeled primary sort as 4 parallel servers with shared FIFO queue based on observed concurrent processing pattern." A human could adjust this. The decision records exactly what was chosen and why.
- `validate` (pure): Run the proposed model against historical telemetry using FlowTime. Compare simulated queue depths against observed queue depths. Model accuracy: R² = 0.91 for primary sort queue, 0.87 for dispatch buffer. Good enough to proceed.
- `calibrate` (recordable): Optimize model parameters (service times, batch intervals, routing probabilities) to minimize the gap between simulated and observed behavior. Uses iterative search — the seeds and convergence path are recorded as decisions. Output: calibrated model with confidence intervals.

**Phase 2 — Simulate and Compare:**

- `scenario_baseline` (pure): Simulate the current system for 24 hours using FlowTime. Same model, same arrival pattern. Throughput: 847 parcels/hour during peak. Backlog clears at 22:30.
- `scenario_second_line` (pure): Clone the model, add a second sorting line (8 servers instead of 4). Simulate. Throughput: 1,034 parcels/hour (+22%). Backlog clears at 19:15.
- `scenario_batch_fix` (pure): Clone the model, reduce the batch processing interval from 300s to 60s. Simulate. Throughput: 1,068 parcels/hour (+26%). Backlog clears at 18:45.
- `compare` (pure): Tabulate results across all scenarios. Cost estimates from reference data.
- `recommend` (recordable): AI synthesizes the comparison into a recommendation. "The batch interval fix recovers more throughput at roughly one-tenth the capital cost of a second sorting line. The second line becomes relevant only above 1,200 parcels/hour sustained." Decision recorded.

Every FlowTime simulation is a **pure op** — deterministic, cacheable, replayable. The model-building and recommendation steps are **recordable** — genuine judgments that the system captures. The data ingestion is **side-effecting** — it touches the external world.

---

## What you can ask afterward

| Question | How it's answered |
|----------|-------------------|
| "Why was primary sort modeled as 4 parallel servers?" | Decision record for `propose_model`: AI examined concurrent processing patterns in scan events, found 4 simultaneous parcels in sorting at 94th percentile. Model choice recorded with reasoning and the telemetry slice it was based on. |
| "How accurate is the model?" | Validation artifact: simulated vs. observed queue depths, R² per service. The validation ran the model against 7 days of real data — the comparison is an immutable artifact, not a claim. |
| "What if the AI had modeled sort as 3 servers instead of 4?" | Fork the run at `propose_model`. Override the decision: 3 servers. Everything downstream re-executes — validation (R² drops to 0.83), calibration (different parameters), scenarios (different throughput numbers). Compare both model variants side by side. The telemetry ingestion and service detection are cached. |
| "What happens if parcel volume grows 40% next year?" | Add a fourth scenario: same calibrated model, scale arrival rate ×1.4. FlowTime simulates — pure op, deterministic. Neither the model-building decisions nor the existing scenario results change. Only the new scenario and the comparison/recommendation re-execute. |
| "Who decided the batch fix was better than the second line?" | Decision record for `recommend`: AI reasoning preserved. If a human overrode the recommendation, that override is also a recorded decision with its own rationale. |

---

## Before and after

**Today:** Norrland Logistik's operations manager argues with IT based on gut feeling. They bring in a consultant who spends three weeks building a simulation model in a commercial tool. The model lives in the consultant's license. When parameters change, they call the consultant back. Six months later, nobody remembers what assumptions went into the model. The shift supervisor's theory about the second sorting line was never tested because the consultant ran out of billable hours.

**With provenance:** The model is built from telemetry in a recorded pipeline. Every modeling choice — why 4 servers, why FIFO discipline, why 300s batch interval — is a decision with a trace to the data that motivated it. What-if scenarios are cheap: change one parameter, FlowTime re-simulates in seconds, everything else caches. When the operations manager asks "what if volume grows 40%?" six months from now, nobody needs to reconstruct the model. It's an immutable artifact. Add a new scenario, get an answer.

The batch interval fix? It was the right call. The decision record shows exactly why — and when volume eventually does hit 1,200 parcels/hour, the model is already there, ready for the next scenario.

---

*The FlowTime pack validates heterogeneous executor integration (C#/.NET 9 via `:port`), the boundary between recordable ops (model-building choices) and pure ops (deterministic simulation), and the co-evolution of two systems that share an author and a philosophy. FlowTime source: [github.com/23min/flowtime](https://github.com/23min/flowtime). Looking for operations teams and flow modeling practitioners. [Contact ->]*
