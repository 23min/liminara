# Domain Pack: Population Simulation Pack

**Status:** Draft  
**Last updated:** 2026-03-02  
**Pack ID:** `population_sim`

---

## 1. Purpose and value

Provide an agent-based simulation framework for modest to large populations (starting with ~1,000 individuals), with durable epochs, snapshots, and replay.

This pack is the bridge between “agent” metaphors and your interest in flow systems, bottlenecks, and inverse modeling.

### Fit with the core runtime

Simulation is expressed as epoch Ops: simulate K steps → snapshot → metrics. BEAM-native is possible for modest sizes; external compute remains an option.

### Non-goals

- Compete with mature ABM suites in all features.
- Require process-per-individual; support sharded execution as well.

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

### Sim Spec (`IR0`)

Population config, environment, rules, seeds, epoch length, snapshot cadence.

**Artifact(s):**
- `sim.spec.v1`

### Behavior Programs (`IR1`)

Behavior definitions per agent type (DSL text → checked AST → optional compiled form).

**Artifact(s):**
- `sim.behavior_dsl.v1`
- `sim.behavior_checked.v1`
- `sim.behavior_compiled.v1`

### World State Snapshot (`IR2`)

State at a point in time (epoch boundary).

**Artifact(s):**
- `sim.world_state.v1`

### Epoch Results (`IR3`)

State delta, events, and metrics for an epoch.

**Artifact(s):**
- `sim.epoch_result.v1`
- `sim.metrics.v1`

### Run Report (`IR4`)

Charts, summaries, anomaly detection.

**Artifact(s):**
- `sim.report_md.v1`
- `sim.report_pdf.v1`

---

## 4. Op catalog (core-executed contract)

Each Op must declare determinism and side-effects (see core spec).

- **`sim.compile_behavior`** — *Pure deterministic*, *no side-effects*
  - Parse/validate behavior DSL into checked form (optionally compile).
  - Inputs: `sim.behavior_dsl.v1`
  - Outputs: `sim.behavior_checked.v1`, `sim.behavior_compiled.v1`
- **`sim.init_world`** — *Nondeterministic but recordable*, *no side-effects*
  - Initialize world state from spec; record seed.
  - Inputs: `sim.spec.v1`
  - Outputs: `sim.world_state.v1`
- **`sim.run_epoch`** — *Pure deterministic*, *no side-effects*
  - Advance simulation for K ticks with explicit ordering policy; output next world state and epoch metrics.
  - Inputs: `sim.world_state.v1`, `sim.behavior_checked.v1`
  - Outputs: `sim.world_state.v1`, `sim.epoch_result.v1`, `sim.metrics.v1`
- **`sim.render_report`** — *Pure deterministic*, *no side-effects*
  - Render report artifacts.
  - Inputs: `sim.metrics.v1`
  - Outputs: `sim.report_md.v1`, `sim.report_pdf.v1`

---

## 5. Decision records and replay

This pack produces/consumes decision records for nondeterministic steps:

- **Seeds and initialization choices**: Random seeds and sampled initial distributions.
  - Stored as: `decision.seed.v1`
  - Used for: Exact replay.
- **Behavior authoring (if LLM-generated)**: LLM-generated DSL programs for behaviors.
  - Stored as: `decision.llm_output.v1`
  - Used for: Replay and safety review.

---

## 6. A2UI / observability

Recommended A2UI surfaces:

- World inspector (state slices, filters).
- Metrics dashboards (time-series).
- Playback of epochs (snapshots).
- Behavior program viewer (DSL + AST).

---

## 7. Executor and tool requirements

This pack may require external executors (ports/containers/remote workers).

- BEAM-native execution for modest size; switchable to sharded processes.
- Optional external simulator executor for larger scale.

---

## 8. MVP plan (incremental, testable)

- Define sim spec + world state schema.
- Implement epoch runner with deterministic ordering.
- Support 1–2 simple behavior primitives (move, consume, emit event).
- Basic A2UI metrics + snapshot playback.

---

## 9. Should / shouldn’t

### Should

- Avoid per-agent mailbox explosions; prefer epoch-level aggregation.
- Keep behavior DSL safe (bounded evaluation).

### Shouldn’t

- Don’t rely on Elixir eval_string for behavior programs.

---

## 10. Risks and mitigations

- **Risk:** Performance ceiling
  - **Why it matters:** Process-per-agent can hit overhead when many are runnable each tick.
  - **Mitigation:** Shard agents; event-driven sims; external compute option.
- **Risk:** Nondeterminism via concurrency
  - **Why it matters:** Scheduling differences can change outcomes.
  - **Mitigation:** Explicit tick ordering and RNG; single-threaded epoch loop or deterministic shard merge.

---

## Appendix: Related work and competitive tech

- [Mesa](https://mesa.readthedocs.io/) — Python ABM framework.
- [NetLogo](https://www.netlogo.org/) — Widely used ABM platform.
- [GAMA](https://gama-platform.org/) — Open-source spatial ABM environment.
- [AnyLogic](https://www.anylogic.com/) — Commercial multimethod simulation.
