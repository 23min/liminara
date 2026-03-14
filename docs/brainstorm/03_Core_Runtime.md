# Core Runtime Substrate Specification (Elixir/OTP control plane)

**Status:** Draft (v0.3)  
**Last updated:** 2026-03-02  
**Scope:** The reusable runtime (“core engine”) that all domain packs target.

This document consolidates and expands the concepts in `ARCHITECTURE_REQUIREMENTS_BRIEF.md` into a buildable, implementation-oriented spec. It is written for an Elixir/OTP implementation where the BEAM is the **control plane**, not the heavy compute substrate.

---

## 0. Summary

The core runtime is a **durable, observable execution substrate** for heterogeneous workloads (LLM-driven, computational, and hybrid). It standardizes:

- **Ops**: typed operations that transform inputs → outputs
- **Artifacts**: immutable, content-addressed run products
- **Runs**: durable executions with a traceable event stream
- **Decision records**: capturing nondeterminism (LLMs, randomness, human decisions)
- **Plan DAG vs Execution DAG**: planning and dynamic graph expansion
- **A2UI**: a UI surface protocol for inspection and human-in-the-loop

The core provides **the minimal kernel** to support all domain packs:
compiler pipelines, agent fleets, dynamic graphs, GA loops, interactive flows, and simulations.

---

## 1. Goals and non-goals

### 1.1 Goals (must-haves)

1. **Durability**
   - A run can resume after crash/restart.
   - Runs are replayable (exact / verify / selective refresh).
   - Long-running workflows are supported via checkpoints and event history.

2. **Artifact-first execution**
   - Every meaningful intermediate is an artifact.
   - Artifacts are versioned and referenceable across runs (caching/reuse).

3. **Determinism discipline**
   - Ops declare determinism class and side-effect policy.
   - Nondeterminism must be captured as decision records.

4. **Hybrid agent interaction**
   - Support both autonomous agents and human-in-the-loop gates.
   - First-class interrupt/resume, approvals, and edits.

5. **Distributed scaling**
   - Run across multiple nodes for throughput.
   - Scheduling, tenancy isolation, and quotas are core-level concepts.

6. **Composable “domain packs”**
   - Packs register schemas + op definitions.
   - Packs build plan DAGs and define their IR pipelines.

7. **Security-by-design**
   - Multi-tenant safety boundaries.
   - Tool allowlists, secret isolation, and strong auditability.

### 1.2 Non-goals (explicitly out of scope)

- Building a general container orchestrator (Kubernetes replacement).
- Hot-loading untrusted Elixir code as a domain-pack mechanism.
- Providing an end-user IDE replacement as the primary product.
- “True” exactly-once side effects everywhere (we aim for idempotency + gated effects).

---

## 2. Core concepts

(These match and extend the brief.)

### 2.1 Agent (conceptual, not necessarily 1 process)
An **Agent** is an entity that:
- has state (possibly checkpointed),
- consumes stimuli or inputs,
- produces outputs (artifacts / actions),
- may call tools, and
- may use an LLM.

In practice, an “agent” can be:
- one BEAM process,
- a group of processes,
- or a purely logical entity implemented as a series of Ops inside a Run.

### 2.2 Op (Operation)
An **Op** is a typed function with:
- declared input artifact types,
- declared output artifact types,
- determinism class,
- side-effect policy,
- execution requirements (executor class, resource needs).

Ops are the unit of scheduling, retries, caching, and replay.

### 2.3 Artifact
An **Artifact** is an immutable output of an Op (or a decision record), stored in the artifact store and addressed by content hash + type + version.

Artifacts are the backbone of:
- provenance graphs,
- caching,
- replay and debugging,
- A2UI previews.

### 2.4 Run
A **Run** is a durable execution instance with:
- Run manifest (input refs, config, budget),
- event history,
- execution DAG,
- artifacts produced,
- decision records produced,
- status.

### 2.5 Plan DAG vs Execution DAG
- **Plan DAG**: the “intended” graph; may contain abstract nodes and placeholders (e.g. “for each URL do fetch+normalize”).
- **Execution DAG**: concrete nodes expanded from the plan as data becomes known (dynamic expansion).

A plan is stable enough to explain; the execution DAG is what actually ran.

### 2.6 Decision record
A **Decision record** captures nondeterminism:
- LLM outputs (and tool traces),
- random seeds and sampling choices,
- human approvals/overrides,
- external-state snapshots.

Decision records allow exact replay and safe selective refresh.

---

## 3. Execution semantics

### 3.1 Node lifecycle
Each Op instance (node) transitions:

`pending → ready → running → (succeeded | failed | cancelled | gated)`

Core responsibilities:
- dependency tracking,
- concurrency limits,
- retries + backoff,
- timeouts,
- cancellation propagation,
- heartbeats (for long nodes),
- output validation.

### 3.2 Retries and idempotency
- Pure ops may be retried freely.
- Pinned-env ops may be retried if executor is stable.
- Side-effecting ops must be:
- **gated** (human or policy approval), and
- **idempotent** via explicit idempotency keys.

### 3.3 Dynamic expansion
Dynamic graphs are supported by:
- **expander ops** that produce lists (e.g. URLs, candidates),
- the scheduler “materializes” new nodes based on emitted artifacts.

Design rule:
- expansion *must* be driven by artifacts (not hidden in code).

### 3.4 Budgets
Runs and deployments include budgets:
- LLM token budgets,
- compute time budgets,
- artifact storage budgets,
- wall-clock deadlines.

Budget violations cause:
- soft stop (no new nodes),
- or hard stop (cancel running nodes),
- with an explicit run failure reason.

---

## 4. Determinism and replay

The core runtime uses the determinism classes from the brief (formalized):

1. **Pure deterministic**
   - Given identical input artifacts, output artifacts are identical.

2. **Deterministic with pinned environment**
   - Deterministic if the executor image/toolchain/version is pinned and recorded.
   - Example: `pandoc@X`, `python@Y`, `solver@Z`.

3. **Nondeterministic but recordable**
   - Outputs can vary, but the exact chosen outputs are stored as decision records.
   - Example: LLM summarization, random initialization.

4. **Side-effecting**
   - Interacts with external world (publishing, payments, PRs).
   - Requires gating + idempotency.

### 4.1 Replay modes
- **Exact replay**: reuse stored decision records and snapshots; should produce identical outputs.
- **Verify replay**: recompute and compare against stored artifacts; report diffs.
- **Selective refresh**: recompute a subset of nodes while reusing stable artifacts/decisions.

### 4.2 External snapshotting
The runtime strongly prefers:
- *snapshot external inputs* → then process locally
- rather than directly consuming external services in later passes.

This is critical for Radar and any pack that reads the web.

---

## 5. The runtime kernel: components

(An implementation sketch; packs should not depend on internal module names, only contracts.)

### 5.1 Scheduler / Run Engine (OTP)
- Owns run state machine.
- Persists node state transitions and event history.
- Issues work to executors.
- Manages retries, timeouts, budgets.

Implementation direction:
- `RunSupervisor` (dynamic supervisor per run or per tenant).
- `RunCoordinator` GenServer managing node state.
- Persistent store for run graph state.

### 5.2 Artifact Store + Metadata Index
- Artifact blobs: S3/minio/local disk (content addressed).
- Metadata: Postgres (artifact graph, types, provenance, indexes).
- Support “artifact handles” in run state (not raw blobs in memory).

Required operations:
- `put_blob`, `get_blob`
- `register_artifact(metadata, blob_hash)`
- `link(run_id, node_id, artifact_id)`
- `garbage_collect(retention_policy)`

### 5.3 Event Log
- Append-only run events:
- node started/finished,
- tool calls,
- LLM token streams (optional),
- gate requests and approvals.
- Enables time-travel debugging and replay.

Store options:
- Postgres table (append-only) for MVP,
- or Kafka/NATS/Redpanda later.

### 5.4 Policy / Gate system
- Central policy checks:
- tool allowlists,
- tenant quotas,
- side-effect gates,
- secret access constraints.
- Gates can be resolved by:
- humans (A2UI),
- pre-approved policies,
- or external approval services.

### 5.5 A2UI Gateway
A2UI is the “observation surface”:
- subscribe to run events,
- show nodes and artifacts,
- collect human inputs (gate approvals, edits),
- render pack-provided views.

You can implement A2UI by:
- exposing the core as an A2UI host,
- serving pack UIs (safe sandbox),
- and allowing bidirectional events.

---

## 6. Executor model (control plane vs compute plane)

The BEAM is the control plane. Ops execute via **executors**:

### 6.1 Executor classes
- **BEAM local**: safe, fast ops (parsing, small transforms).
- **Port executor**: external binaries via Erlang ports (recommended default for non-trivial compute).
- **Container executor**: run a pinned container image locally or in a cluster.
- **Remote worker executor**: a worker pool (Rust/Python/Go) that implements an RPC contract.
- **Wasm executor**: sandboxed execution of compiled DSLs (via Wasmex) when applicable.

### 6.2 Why ports/container by default
- NIFs can crash the VM; dirty schedulers help but don’t remove risk.
- Ports and containers isolate failures and resource usage.

### 6.3 Executor contract (minimum viable)
Define a stable contract (JSON over stdio or gRPC/HTTP):

- `execute_op(op_name, op_version, inputs, env, budget) -> outputs + logs + events`
- `heartbeat(run_id, node_id)`
- `cancel(run_id, node_id)`

All stdout/stderr and structured logs become artifacts/events.

---

## 7. Multi-tenancy and workspaces

### 7.1 Tenant namespace model
A tenant (“subscription”) isolates:
- artifacts,
- runs,
- secrets,
- workspaces,
- quotas.

Every stored object is namespaced by `(tenant_id, project_id)`.

### 7.2 Workspace model
Workspaces are **ephemeral execution sandboxes** with a safe filesystem boundary:

- Each run node that needs FS access gets a workspace:
`workspaces/<tenant>/<run>/<node>/`
- The workspace is disposable and can be reconstructed from artifact inputs.
- Large inputs are materialized by “artifact mount” (copy-on-write if possible).

Workspace policies:
- default read-only,
- writes produce new artifacts (patchsets, outputs),
- direct external writes are gated.

---

## 8. Context management (LLM)

The runtime should treat LLM “context” as a first-class engineering problem:

- Prefer **artifact references** (IDs + previews) over pasting raw text.
- Use derived IR artifacts (indexes, summaries) to keep prompts small.
- Capture the exact prompt+response in decision records for replay.
- Allow “context compilation”: a pack-defined op that builds the prompt payload.

Core should provide:
- prompt templates versioning,
- prompt caching keys (provider-specific if available),
- token budgeting and truncation policies.

Streaming tokens:
- stream partial outputs into the event log,
- but finalize a stable artifact at completion.

---

## 9. Observability and debugging

Minimal must-have instrumentation:
- run timeline,
- node status,
- structured logs,
- artifact graph visualization,
- diffing between runs,
- “why did this happen” links (inputs + decision record).

Recommended:
- OpenTelemetry traces (each node as a span),
- metrics for executor latency and cost,
- run-level cost accounting (tokens, CPU time).

---

## 10. Data model (illustrative)

You can implement these as Postgres tables or event-sourced projections.

- `tenants`
- `projects`
- `packs` (name, version, schema versions)
- `op_defs` (pack_id, name, determinism, side_effect, inputs, outputs, executor_class)
- `runs` (tenant_id, status, created_at, budgets, manifest)
- `run_nodes` (run_id, op_def_id, state, attempt, timings, executor_ref)
- `artifacts` (tenant_id, type, version, hash, size, created_at, metadata_json)
- `artifact_edges` (from_artifact_id, to_artifact_id, edge_type)
- `decisions` (run_id, type, hash, payload_ref)
- `events` (run_id, seq, ts, kind, payload_json)
- `gates` (run_id, node_id, policy, requested_by, status, resolution)

---

## 11. Core risks (objective)

1. **Scope creep**
   - A generic platform invites endless features.
   - Mitigation: kernel discipline + pack boundaries + toy packs first.

2. **Security**
   - Agents + tools + web content is a large attack surface.
   - Mitigation: strong allowlists, secret isolation, gating.

3. **Distributed complexity**
   - Multi-node execution introduces partial failures and consistency issues.
   - Mitigation: keep control plane event-sourced and simple; start single-node.

4. **Reproducibility trade-offs**
   - Perfect reproducibility is expensive.
   - Mitigation: explicit replay modes; accept “verify” not always “exact”.

---

## 12. Incremental roadmap (recommended)

1. **Walking skeleton**
   - Implement core artifacts, runs, ops, executor contract.
   - One trivial op pipeline.

2. **Toy pack 1: Report Compiler**
   - Validate pinned toolchains, binary artifacts, publishing gate.

3. **Prototype 1: Radar**
   - Validate snapshotting, LLM decisions, schedules/fleet-like operation.

4. **Toy pack 2: Ruleset Lab**
   - Validate rules-as-data and run diffing/waivers.

5. **Prototype 2: House compiler PoC**
   - Minimal compile path; correctness scaffolding.

6. **Prototype 3: Software factory read-only**
   - Secure workspace tools; then gated writes.

---

## Appendix: References used by this spec

- [A2UI GitHub](https://github.com/google/A2UI) — Agent-to-UI open standard; pack UI extensions target this.
- [A2UI protocol doc (v0.8)](https://github.com/google/A2UI/blob/main/specification/v0_8/docs/a2ui_protocol.md) — Protocol spec.
- [Temporal Event History](https://docs.temporal.io/encyclopedia/event-history) — Durable execution via event sourcing + replay.
- [Prefect interactive workflows](https://docs.prefect.io/v3/advanced/interactive) — Pause/suspend/resume workflows.
- [LangGraph durable execution](https://docs.langchain.com/oss/python/langgraph/durable-execution) — Persisted state per step.
- [MLflow Tracking (runs & artifacts)](https://mlflow.org/docs/latest/ml/tracking/) — Run metadata + artifact store pattern.
- [OpenLineage spec](https://github.com/OpenLineage/OpenLineage/blob/main/spec/OpenLineage.md) — Open lineage standard (runs/jobs/datasets).
- [AiiDA caching & provenance](https://aiida-core-pdf.readthedocs.io/en/latest/topics/provenance/caching.html) — Scientific workflow provenance and caching.
- [Azure Durable Functions constraints](https://learn.microsoft.com/en-us/azure/azure-functions/durable/durable-functions-code-constraints) — Determinism constraints for replay.
- [Model Context Protocol (MCP) spec](https://modelcontextprotocol.io/specification/2025-11-25) — Standard tool/context integration protocol.
- [Bazel hermeticity](https://bazel.build/basics/hermeticity) — Hermetic execution rationale.
- [Nix content-addressed store objects](https://nix.dev/manual/nix/2.26/store/store-object/content-address) — CA store for reproducibility/caching.
- [SLSA provenance](https://slsa.dev/spec/v1.0/provenance) — Supply-chain provenance model.
- [Erlang Ports](https://www.erlang.org/doc/system/ports.html) — Safe boundary to external programs.
- [Erlang NIFs & dirty schedulers](https://www.erlang.org/doc/apps/erts/erl_nif.html) — Native integration risks and mitigations.
- [Wasmex](https://hexdocs.pm/wasmex/Wasmex.html) — Wasm runtime for Elixir (wasmtime via NIF).
- [Elixir Code (eval/compile warnings)](https://hexdocs.pm/elixir/Code.html) — Do not eval/compile untrusted strings.

    ---

    ## Note on alignment with the brief

    The brief remains a high-level guide. This document formalizes the runtime requirements it describes:
    ops/artifacts/runs/decision records, determinism classes, replay modes, A2UI integration, and the domain pack model.
