# Roadmap

Sequencing principle (D-013): `Radar correctness -> Radar hardening -> VSME -> platform generalization`.
Status labels (D-014): items marked `[validated]`, `[decided next]`, or `[directional thesis]`.

Historical note: the Phase 5 split was introduced after initial Radar implementation work exposed correctness gaps. Some Phase 5b work was completed before the sequence was revised. Read Phases 5a-5c as the current forward order from here, not as a claim that all completed work originally happened in that order.

## Phase 0: Data Model — Complete [validated]

- [x] E-01 Data Model Spec

## Phase 1: Python SDK / Data Model Validation — Complete [validated]

- [x] E-02 Python SDK (data model validation + demo artifact)
- [x] E-03 LangChain Integration

## Phase 2: Elixir Walking Skeleton — Complete [validated]

- [x] E-04 Elixir Project Scaffolding + Golden Fixtures
- [x] E-05 Storage Layer (Artifact Store + Event Store + Decision Store)
- [x] E-06 Execution Engine (Plan + Op + Run.Server + Cache)
- [x] E-07 Integration and Replay (end-to-end, Pack behaviour, interop)

## Phase 3: OTP Runtime Layer — Complete [validated]

- [x] E-08 OTP Runtime (supervision tree, Run.Server GenServer, :pg broadcasting, crash recovery, property-based stress testing, toy pack)

## Phase 4: Observation Layer — Complete [validated]

- [x] E-09 Observation Layer (Observation.Server, Phoenix LiveView UI, DAG visualization, inspectors, A2UI experimental renderer)
  - [x] M-OBS-01 Observation Server — renderer-agnostic event projection
  - [x] M-OBS-02 Phoenix scaffolding + runs dashboard
  - [x] M-OBS-03 SVG DAG visualization with real-time updates
  - [x] M-OBS-04a Node inspector + artifact viewer + dashboard layout
  - [x] M-OBS-04b Event timeline + decision viewer
  - [x] M-OBS-05a Gate demo + LiveView gate interaction
  - [x] M-OBS-05b A2UI exploration + integration

## Phase 5a: Radar Correctness — Complete [validated]

Fix the core replay contract before building on top of it.

- [x] M-RAD-06 Replay Correctness (milestone inside E-11)
  - [x] Decision.Store multi-decision support (list per node_id, backward compatible)
  - [x] Run.Server replay restores multi-decision recordable ops
  - [x] End-to-end Radar replay test (discovery → replay → identical artifacts)
  - [x] Executor.Port env whitelist (clean env, no VIRTUAL_ENV leakage)
  - Rank determinism: resolved in M-RAD-03 (reference_time as explicit plan input)
  - M-RAD-03 tracking accuracy: resolved in M-RAD-03 (scope amendment, known limitations documented)

## Phase 5b: Radar Complete — Complete [validated]

Finish the Radar pack as a working local MVP.

- [x] E-10 Port Executor (prerequisite — `:port` executor for Python ops via Erlang Ports)
  - [x] M-PORT-01 Port protocol + executor + Python runner
  - [x] M-PORT-02 Integration test (all determinism classes)
- [x] E-11 Radar Pack (daily intelligence briefing pipeline)
  - [x] M-RAD-01 Pack + source config + fetch (~47 sources)
  - [x] M-RAD-02 Extract + embed + dedup pipeline
  - [x] M-RAD-03 Cluster + rank + render (forward execution; replay fixed in M-RAD-06)
  - [x] M-RAD-04 Web UI + scheduler (LiveView + GenServer scheduler per D-008)

## Phase 5c: Radar Hardening — In progress [active]

Tightly scoped to capabilities Radar has already proven it needs for production deployment on a single VM.

- [x] E-20 Execution Truth
  - First blocking Phase 5c slice after M-RAD-04 is finished and validated
  - [x] M-TRUTH-01 Execution spec + outcome design
  - [x] M-TRUTH-02 Core runtime contract migration
  - [x] M-TRUTH-03 Radar semantic cleanup
- [ ] E-19 Warnings & Degraded Outcomes
  - [ ] First-class warning/degraded-success contract for ops and runs
  - [ ] Observation + UI surfacing of cause, severity, remediation, and output impact
  - [ ] Radar adoption for placeholder/fallback paths and briefing annotations
- [ ] E-12 Op Sandbox (Layers 2-3) — audit hooks, Landlock, capability declarations in execution spec `isolation` section, sandbox metadata in run events
  - [ ] M-ISO-01 Executor isolation (audit hooks, Landlock)
  - [ ] M-ISO-02 Provenance & documentation (sandbox config in events, docs)
- [ ] Recovery mode — "resume from last success" (create new run from failed run, skip completed nodes)
- [ ] Lightweight topic config — YAML/JSON config listing topics (sources, focus, schedule, paths); Radar.Pack.plan/1 takes topic config and namespaces file paths; GenServer scheduler iterates topics
- [ ] Observation UI: topic filter — tag runs with topic ID, filter in dashboard

*Scope rule (D-012): only items Radar has already proven it needs. No broad platform abstractions.*

## Phase 6: VSME — Not started [decided next]

First compliance pack. Validates that the hardened runtime works for a second pack with different domain pressures.

- [ ] E-13 VSME Pack (SME sustainability reporting — CSRD/EFRAG VSME standard)

What VSME should prove:
- The pack model generalizes beyond Radar
- Provenance and replay are valuable outside news/intelligence workflows
- The hardening work was not Radar-specific glue

*Pack plan: see [14_VSME_Pack_Plan.md](../docs/analysis/14_VSME_Pack_Plan.md)*

## Phase 7: Platform Generalization — Not started [directional thesis]

Promote only cross-pack-proven concerns into reusable runtime abstractions. Items move here from demand-driven when both Radar and VSME prove the need.

- [ ] E-14 Persistence + Scheduling
  - [ ] Postgres for event log + artifact metadata persistence
  - [ ] Oban for job scheduling (one recurring job per pack instance)
  - [ ] Artifact index separation — decouple artifact indexing from execution (Flyte DataCatalog / Bazel action cache pattern)
- [ ] E-15 PackRegistry — generalize topic config into runtime-level pack instances
  - [ ] PackRegistry with `register/1` API
  - [ ] Pack behaviour evolution: `init/1` (config), `plan/2` (inputs, config)
  - [ ] Instance-scoped storage partitioning at runtime level
  - [ ] Observation UI: full instance selector, per-instance run timelines
- [ ] E-16 Dynamic DAGs
  - [ ] Add nodes to a running plan mid-execution
  - [ ] Scheduler handles growing DAGs (find ready -> dispatch -> collect loop unchanged)
  - [ ] New events: `nodes_added`, `plan_extended` in the event log
  - [ ] Enables: Radar serendipity (M-RAD-05), House Compiler iterations
- [ ] E-17 Container Executor + Pluggable Storage
  - [ ] `:container` executor — Docker-based op execution with dependency isolation
  - [ ] Pluggable artifact store interface (filesystem -> S3 backend)
  - [ ] Op `resources/0` in execution spec `execution` section
- [ ] E-xx Time-Travel Debugging UI
  - [ ] Step through a run's event history, seeing DAG state at each event
  - [ ] Inspect intermediate artifacts and decisions at any point in the run
  - [ ] Visual diff between runs (same plan, different decisions)
- [ ] E-11b Radar Serendipity (depends on E-16 dynamic DAGs)
  - [ ] M-RAD-05 Serendipity exploration: select novel/outlier items, search related coverage and counterpoints, follow links, merge relevant discoveries before clustering, and recommend new sources for human review

## Phase 8: House Compiler — Not started [directional thesis]

Second domain pack. Proves generality beyond LLM/text workflows (geometry, structural analysis, manufacturing).

- [ ] E-18 House Compiler Pack (design -> manufacturing pipeline)

## Demand-Driven (not sequenced — built when a customer needs it)

### Scale Executors [directional thesis]
- [ ] `:k8s_pod` executor — Kubernetes pod execution for isolated, GPU-capable ops
- [ ] `:ray_task` executor — Ray cluster execution for distributed ML training/inference
- [ ] `:slurm_job` executor — SLURM batch jobs for bare-metal HPC/GPU clusters

### Formal Contracts (CUE) [directional thesis]
*Trigger: when `:container` executor lands and multi-source constraints become load-bearing, or earlier if cross-pack composition demands it.*
- [ ] CUE constraint schemas for op inputs/outputs and resource declarations
- [ ] Cross-pack compatibility validation via lattice unification
- [ ] Decision space schemas for recordable ops

### Selective Re-Run [directional thesis]
*Trigger: when daily Radar operation reveals the need, or when debugging complex packs.*
- [ ] "Re-run from this node" — invalidate one node's cache, re-execute it and all downstream
- [ ] Observation UI action: click a node -> "re-run from here"

### Op Heartbeats [directional thesis]
*Trigger: when ops legitimately run for minutes/hours (GPU training, heavy geometry computation).*
- [ ] Long-running ops emit periodic liveness signals
- [ ] Scheduler distinguishes "hung" from "slow but working"

### Access Control [directional thesis]
*Trigger: when multi-user deployments are real.*
- [ ] Per-instance access rules (user -> instance ID mapping)
- [ ] Observation UI filtered by user permissions

*Research context:*
- *[cue_language.md](../docs/research/cue_language.md) — CUE constraint language analysis*
- *[flyte_architecture.md](../docs/research/flyte_architecture.md) — Flyte deep dive*
- *[scale_and_distribution_strategy.md](../docs/research/scale_and_distribution_strategy.md) — scale and executor strategy*
- *[16_Orchestration_Positioning.md](../docs/analysis/16_Orchestration_Positioning.md) — orchestration landscape positioning*
