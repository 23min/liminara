# Domain Pack: FlowTime Integration Pack

**Status:** Draft  
**Last updated:** 2026-03-02  
**Pack ID:** `flowtime.integration`

---

## 1. Purpose and value

Treat FlowTime (your flow/queue/bottleneck modeling tool) as a first-class domain pack: compile flow specs, run simulations, and export artifacts and telemetry bundles.

This pack is the bridge between your existing “flow systems” work and the new runtime substrate.

### Fit with the core runtime

FlowTime already feels compiler-shaped: spec → model → run → telemetry. The pack makes those stages explicit IR artifacts.

### Non-goals

- Re-implement FlowTime inside the core runtime.
- Support every simulation feature in v0.

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

### Flow Spec (`IR0`)

Input FlowTime DSL/spec and parameters.

**Artifact(s):**
- `flow.spec.v1`

### Compiled Model (`IR1`)

Validated internal model graph ready for simulation.

**Artifact(s):**
- `flow.model_ir.v1`

### Simulation Run (`IR2`)

Simulation results, traces, queue stats, bottleneck summaries.

**Artifact(s):**
- `flow.sim_result.v1`
- `flow.sim_trace.v1`

### Calibration / Inverse Modeling (`IR3`)

Parameter inference results (fit to observed data), with confidence bands.

**Artifact(s):**
- `flow.calibration.v1`

### Reports (`IR4`)

Rendered charts and reports.

**Artifact(s):**
- `flow.report_md.v1`
- `flow.report_pdf.v1`

---

## 4. Op catalog (core-executed contract)

Each Op must declare determinism and side-effects (see core spec).

- **`flow.compile`** — *Pure deterministic*, *no side-effects*
  - Parse and validate FlowTime spec; produce model IR.
  - Inputs: `flow.spec.v1`
  - Outputs: `flow.model_ir.v1`
- **`flow.simulate`** — *Pure deterministic*, *no side-effects*
  - Run simulation with pinned seed/scheduler policy.
  - Inputs: `flow.model_ir.v1`
  - Outputs: `flow.sim_result.v1`, `flow.sim_trace.v1`
- **`flow.inverse_model`** — *Nondeterministic but recordable*, *no side-effects*
  - Fit parameters to observed data using GA/optimizer; record seeds and steps.
  - Inputs: `flow.model_ir.v1`, `flow.observed_data.v1`
  - Outputs: `flow.calibration.v1`
- **`flow.render_report`** — *Pure deterministic*, *no side-effects*
  - Render report artifacts.
  - Inputs: `flow.sim_result.v1`
  - Outputs: `flow.report_md.v1`, `flow.report_pdf.v1`

---

## 5. Decision records and replay

This pack produces/consumes decision records for nondeterministic steps:

- **Inverse modeling optimization trajectory**: GA/optimizer decisions (seeds, selected candidates).
  - Stored as: `decision.ga_step.v1`
  - Used for: Replay of inferred parameters.

---

## 6. A2UI / observability

Recommended A2UI surfaces:

- Model graph viewer (nodes/queues/resources).
- Telemetry explorer (time series, bottlenecks).
- Calibration diagnostics (fit quality, residuals).

---

## 7. Executor and tool requirements

This pack may require external executors (ports/containers/remote workers).

- FlowTime engine executor (in-BEAM if already Elixir, otherwise port).
- Optional Python/R plotting executor.

---

## 8. MVP plan (incremental, testable)

- Compile a FlowTime spec into a model IR artifact.
- Run simulation and produce queue/bottleneck summary artifacts.
- Render a simple report.
- Add 'inverse modeling' later.

---

## 9. Should / shouldn’t

### Should

- Keep simulation deterministic via explicit seed and tick ordering policy.
- Store traces separately from summaries to manage storage.

### Shouldn’t

- Don’t treat trace logs as UI messages; store as artifacts and stream slices.

---

## 10. Risks and mitigations

- **Risk:** Trace volume
  - **Why it matters:** Sim traces can be huge.
  - **Mitigation:** Sampling; compression; store aggregates by default.
- **Risk:** Mismatch between observed data and model
  - **Why it matters:** Inverse modeling can overfit.
  - **Mitigation:** Regularization; holdout validation; explicit uncertainty reporting.

---

## Appendix: Related work and competitive tech

- [FlowTime repo](https://github.com/23min/flowtime) — User project.
- [AnyLogic](https://www.anylogic.com/) — Commercial simulation platform.
- [SimPy](https://simpy.readthedocs.io/en/latest/) — Discrete-event simulation in Python.
