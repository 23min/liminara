# Umbrella: Multi-Pack Agent Runtime (Vision, Fit, and Project Approach)

**Status:** Draft (v0.3)  
**Last updated:** 2026-03-02

This is the “big picture” document: why this platform exists, how the core accommodates all domain packs, and how to approach the project without painting yourself into a corner.

---

## 1. What we are building

A reusable runtime substrate:

- **Elixir/OTP control plane**: durable orchestration, supervision, distributed coordination, and observation surfaces.
- **Pluggable compute plane**: ports/containers/remote workers for heavy compute and unsafe code.
- **Domain packs**: small “compilers” that map domain problems onto the substrate via IR passes, ops, artifacts, and A2UI views.

The kernel idea is: **make work inspectable and replayable** by forcing it through artifacts and decision records.

---

## 2. The domain packs we discussed

(Each has its own spec doc; see `README.md`.)

- Radar / Omvärldsbevakning
- Software Factory
- House Compiler
- FlowTime Integration
- LodeTime Dev Process pack
- Process Mining
- Agent Fleets
- Population Simulation
- Behavior DSL pack
- Evolutionary Software Factory
- Toy packs: Report Compiler, Ruleset Lab, GA Sandbox

---

## 3. Three ways to sort the packs (useful for planning)

### 3.1 By “workload shape” (what the core must support)

- **Compiler-shaped pipelines**
  - Radar, House Compiler, Report Compiler, Ruleset Lab, Process Mining, LodeTime
- **Long-lived / scheduled / continuous**
  - Agent Fleets, Radar (as scheduled runs), LodeTime (daily checks)
- **Optimization loops**
  - GA Sandbox, Evolutionary Factory, FlowTime inverse modeling (optional)
- **Simulation / many-entity**
  - Population Simulation, FlowTime (simulation), Process Mining (observed traces)

This is the most important sorting for core design.

### 3.2 By “core validation value” (how good they are as substrate tests)

- **High validation, low domain risk**
  - Report Compiler, Ruleset Lab, GA Sandbox
- **High validation, moderate domain risk**
  - Radar, Process Mining, FlowTime Integration
- **High validation, high domain risk**
  - Software Factory, House Compiler, Population Simulation

Use this to choose what to build first.

### 3.3 By “risk profile” (what can kill the project)

- **Security-heavy**
  - Software Factory, Radar (web injection), Agent Fleets
- **Correctness/liability-heavy**
  - House Compiler, Ruleset Lab (compliance implications)
- **Scale/performance-heavy**
  - Population Simulation, GA loops at scale
- **Integration-heavy**
  - Process Mining (formats and tooling), LodeTime (language tooling)

This sorting tells you where to be conservative.

---

## 4. How the core accommodates all packs (without compromise)

The runtime is shaped around *common denominators*:

1. **IR pipelines**
    - Every pack becomes a series of passes.
    - Passes produce artifacts; artifacts are inspectable in A2UI.

2. **Determinism discipline**
    - Packs can be nondeterministic (LLMs, randomness), but must record decisions.
    - Side effects are gated and idempotent.

3. **Dynamic expansion**
    - Packs can start with a plan and expand into a concrete execution DAG.
    - This supports: “for each URL”, “for each candidate”, “for each agent”, etc.

4. **Executor abstraction**
    - Packs can require different compute: CAD, Python, solvers, renderers.
    - The control plane remains stable; only executors vary.

5. **A2UI integration**
    - Each pack can provide specialized views.
    - The core provides the “run debugger” baseline and event stream.

6. **Multi-tenancy and workspaces**
    - Packs can safely operate on files and external resources inside tenant sandboxes.

This is why it can support both “agent fleets” and “compiler passes”: both are just different ways to generate and execute DAG-shaped work.

---

## 5. Does anything like this already exist?

Yes — parts of it exist. An honest breakdown:

### 5.1 Durable workflow engines
- Temporal, Azure Durable Functions: event-sourced workflows + replay.
- Prefect/Flyte/Argo/Airflow: workflow scheduling and execution, different tradeoffs.

These solve “run my workflows reliably”, but they generally do *not* enforce:
- artifact-first IR discipline across heterogeneous packs,
- decision record capture for LLM nondeterminism,
- a unified “compiler debugger” UX (A2UI) across packs.

### 5.2 Data/ML lineage systems
- MLflow: run tracking + artifacts.
- OpenLineage: lineage standard (jobs/runs/datasets).
- AiiDA: provenance graph + caching for scientific workflows.

These solve “track results and lineage”, but typically don’t provide:
- interactive agent gates,
- generalized tool sandboxing for agentic workflows,
- multi-pack compiler-style IR pipelines.

### 5.3 Agent frameworks and agent tooling
- OpenAI Agents SDK / Swarm, AutoGen, CrewAI: agent coordination and patterns.
- MCP: standardized tool/context integration.
- Claude Code, Copilot agents, Cursor, Aider: “coding agents” and IDE tools.

These solve “how to write agents”, but often assume:
- a host runtime (you still need a substrate),
- weaker provenance discipline,
- less explicit replay semantics (varies),
- and vendor/platform coupling.

### 5.4 So… should you build your own?

**Only if you need the combination**:
- durable orchestration + replay,
- artifact/provenance graphs,
- pack-defined compiler pipelines,
- hybrid HITL UX,
- local-first / cost-controlled operation,
- and a BEAM-native control plane you can reuse across many “exotic” domains.

Otherwise, you should strongly consider adopting:
- Temporal for durability,
- Prefect/Flyte/Argo for workflows,
- a Python agent framework for orchestration,
- and treat your work as “just another app”.

Building a generic platform is high risk.

---

## 6. Why an Elixir/OTP control plane is (and isn’t) smart

**Where Elixir shines for this platform**:
- Supervision trees for long-lived coordinators and workers.
- Lightweight processes for control-plane state machines.
- Distributed Erlang for cluster membership and messaging.
- Fault tolerance as a default posture.
- Good fit for “agent fleet” and “many runs with lots of state transitions”.

**Where Elixir is a liability**:
- Heavy compute inside BEAM hurts latency and scheduler health.
- Ecosystem for CAD/solvers/ML is not as rich as Python.
- Many integrations will be ports/containers anyway.

The design decision to keep BEAM as **control plane only** is what makes this reasonable.

---

## 7. Project approach (how to keep it solo-dev feasible)

Key strategy: **kernel discipline + toy packs**.

1. Implement the minimal core (runs, ops, artifacts, event log, executor contract).
2. Validate with toy packs (report compiler, ruleset lab, GA sandbox).
3. Build Radar as the first “real” product and daily driver.
4. Only then attempt Software Factory (read-only first).
5. Keep House Compiler as a later PoC with correctness scaffolding.

Principle: *each new pack must not require core changes that break existing packs*.

---

## Appendix: Competitive and research links

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
- [Claude Code docs](https://code.claude.com/docs/en/overview) — Coding agent tool.
- [GitHub Copilot coding agent](https://docs.github.com/en/copilot/concepts/agents/coding-agent/about-coding-agent) — Hosted PR workflow agent.
- [OpenAI Agents SDK](https://openai.github.io/openai-agents-python/) — Agent framework.
- [AutoGen](https://github.com/microsoft/autogen) — Multi-agent framework.
- [CrewAI](https://github.com/crewAIInc/crewAI) — Multi-agent automation framework.
- [Dagster assets](https://docs.dagster.io/concepts/assets/software-defined-assets) — Asset-based orchestration.
- [Argo Workflows](https://argo-workflows.readthedocs.io/en/latest/) — Kubernetes-native workflows.
- [OpenLineage](https://openlineage.io/) — Lineage platform + standard.

