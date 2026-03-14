# Agent Runtime Architecture & Requirements Brief

**Status:** Draft (v0.2)

**Audience:** Product + engineering stakeholders building a reusable agent runtime (“core engine”) and the first three domain packs:
- Omvärldsbevakning
- Software factory
- House compiler (SketchUp → analysis → design → PDFs + NC + BOM)

**Purpose of this document:** Capture the agreed architecture direction and the requirements we’ve converged on so far. This is **not** a full implementation spec; it is a **solution architecture + requirements brief** that should survive early iteration and guide design choices.

---

## 1. Problem statement

We want a **general runtime for heterogeneous agent workloads**—LLM-driven and computational—such that multiple “domain packs” can be mapped onto it without rewriting the core.

Key objectives:
- Support *different workload shapes*: pipelines (“compiler passes”), agent fleets, dynamic graphs, GA optimization loops, and interactive human-in-the-loop flows.
- Provide **deterministic replay** and **auditability** for any run, even when parts of the original run were nondeterministic (LLM calls, stochastic optimization, live web fetches).
- Support **multi-artifact compilation**: a single run can produce many artifacts (reports, PDFs, NC files, code repos, datasets) with strong provenance.
- Provide an **A2UI** (agent-to-UI) layer for monitoring, inspection, intervention, overrides, and controlled reruns.

Non-goals (for the core engine):
- The core engine is not “an LLM product” and should not assume LLMs are always present.
- The core engine should not bake in domain rules (construction codes, news topics, software build steps). Those belong in packs.

---

## 2. Terms and concepts

### 2.1 Agent
A supervised, addressable capability provider. An agent can wrap:
- LLM inference
- deterministic calculations
- a geometry kernel via NIF/Port/external process
- data/ruleset lookup
- file/PDF/NC generation
- I/O integration (fetching, publishing, notifications)
- a **human gate** (A2UI interaction step)

### 2.2 Op (Operation)
A unit of work executed by an agent/worker. An Op has:
- Inputs (artifact references + parameters)
- Declared outputs (artifact types)
- Declared properties (determinism class, side effects, resource requirements)
- Implementation identity (version)

### 2.3 Artifact
An immutable content object produced or consumed by Ops.
- Content-addressed (hash)
- Strong metadata (source, timestamps, tool versions, ruleset versions, schema versions)

### 2.4 Run
A concrete execution instance:
- Inputs + configuration + selected rulesets
- Execution DAG (“what actually happened”)
- Output artifacts
- Complete provenance and decision trace

### 2.5 Execution DAG vs Plan DAG
Most interesting workflows are dynamic.
- **Plan DAG:** the abstract/desired workflow definition.
- **Execution DAG:** the concrete unrolled graph that actually ran (including chosen branches, evaluated GA candidates, tool calls, retries).

Deterministic replay is based on the **Execution DAG**.

### 2.6 Decision record
A persistent record of a nondeterministic choice, e.g.:
- An LLM response (raw + parsed)
- A GA selection/mutation event
- A human approval/override

On replay, the engine can **inject** recorded decisions instead of rediscovering them.

---

## 3. Design principles

1. **Graph-first execution**
   - Everything reduces to “build/extend a graph of Ops, then execute it.”

2. **Artifact + provenance first**
   - If it isn’t captured as an artifact or event, it didn’t happen.

3. **Determinism is a contract, not a hope**
   - Each Op declares a determinism class (see §6).

4. **Separation of concerns: runtime vs domain packs**
   - Runtime provides generic orchestration, replay, provenance, UI hooks.
   - Packs provide domain IRs, rule engines, generators, and backends.

5. **Human-in-the-loop is a first-class workflow primitive**
   - A2UI is not “bolted on.” Decisions and overrides are part of the run graph.

6. **Safe execution boundaries**
   - NIFs/ports/external tools must be isolated with clear resource limits and failure handling.

---

## 4. High-level architecture

### 4.1 Core runtime components

- **Scheduler**
  - Time-based runs (cron-style), event-based triggers, backfills.

- **Graph Builder APIs**
  - Domain packs define workflows and/or dynamic graph expansion logic.

- **Execution Engine**
  - Executes Ops respecting dependencies.
  - Manages retries, backoff, timeouts.
  - Parallelism control.

- **Agent/Worker Registry**
  - Routes Ops to suitable agents/workers.
  - Supports pools for heavy workloads (geometry kernels, renderers).

- **Artifact Store**
  - Content-addressed storage + metadata index.
  - Supports large binary artifacts (PDF/NC).

- **Event Log / Trace Store**
  - Append-only record of execution events sufficient to reconstruct the Execution DAG.

- **Cache**
  - Memoization keyed by (Op implementation version + input artifact hashes + config).

- **Policy Engine**
  - Replay modes, refresh rules, side-effect gating, environment pinning rules.

- **A2UI Gateway**
  - Real-time event streaming and state queries.
  - Human approvals/overrides integrated as decision records.

- **Connectors / Integrations**
  - Web fetchers, email/slack delivery, repo interactions, storage, etc.

### 4.2 Suggested implementation substrate
- Elixir/OTP for concurrency, supervision, fault tolerance.
- GenServers/GenStages/Broadway as appropriate for streaming stages.
- Heavy compute via:
  - Rust NIFs (Rustler) when safe and bounded
  - Ports/external processes when isolation is required

---

## 5. Domain pack model

A “domain pack” is a deployable module that provides:

1. **IR Schemas**
   - Serialized intermediate representations between passes.

2. **Op Catalog**
   - Named Ops + determinism/side-effect declarations.

3. **Workflow/Graph Builders**
   - Static pipeline definitions and/or dynamic expansions.

4. **Rulesets & Datasets (versioned)**
   - Domain data (tables, codes, heuristics) treated as versioned inputs.

5. **A2UI Extensions**
   - Optional UI panels: specialized viewers, diffing, domain-specific override forms.

### 5.1 “Compiler-shaped” packs
Many packs are best structured as compiler passes:
- IR0 → IR1 → IR2 → … → outputs

This enables deterministic testing, isolation, and replay.

---

## 6. Determinism, replay, and side effects

### 6.1 Determinism classes (per Op)

1. **Pure deterministic**
   - Same inputs + same op version ⇒ same outputs.

2. **Deterministic with environment pinning**
   - Deterministic if tool versions + environment are pinned.

3. **Nondeterministic but recordable**
   - LLM inference, stochastic search, “live web” unless snapshotted.
   - Must emit decision records.

4. **Side-effecting**
   - Produces external effects (publish, send, commit).
   - Must be idempotent or guarded by the runtime.

### 6.2 Replay modes

- **Exact replay**
  - Reuse recorded outputs for all Ops; intended for audit/debug.

- **Verify replay**
  - Re-run deterministic Ops; verify output hashes match.
  - Inject recorded nondeterministic decisions.

- **Selective refresh**
  - Recompute only a chosen subset (e.g., refetch sources, rerun summaries, reevaluate fitness with a new ruleset), while reusing recorded decisions elsewhere.

### 6.3 “Once decisions are made, we get a DAG”

The runtime should:
- Capture the **Execution DAG** during the first run.
- Persist every nondeterministic decision as an artifact/decision record.

Replay then becomes:
- Execute the same DAG.
- For nondeterministic nodes: inject the recorded decision/output.
- For deterministic nodes: optionally recompute and verify.

### 6.4 Snapshotting external inputs
For replay to work, external inputs must become artifacts:
- Web fetches → snapshot artifacts
- Files (SketchUp, PDFs) → immutable stored inputs
- Tool outputs → captured artifacts

---

## 7. A2UI requirements

A2UI is the user’s “compiler debugger” across packs.

### 7.1 Core A2UI capabilities
- Live run dashboard with DAG visualization
- Node inspection:
  - inputs/outputs (artifact previews)
  - op version + environment + ruleset versions
  - metrics/logs
- Rerun controls:
  - rerun subtree from node
  - switch replay mode
  - selective refresh policies
- Override/approval steps:
  - create a decision override artifact
  - rerun downstream
- Diff runs:
  - compare outputs and explain differences based on changed artifacts/decisions

### 7.2 Pack-provided A2UI extensions (examples)
- Omvärldsbevakning: “why did I get this alert?”, topic tuning, source trust controls
- Software factory: PR view, test failures, code review summaries
- House compiler: viewers for IR, part lists, drawing previews, manufacturability checks

---

## 8. Mapping the three domain packs onto the runtime

### 8.1 Omvärldsbevakning (recommended first pack)
**Primary value:** validates scheduling, ingestion, snapshotting, provenance, dedup, ranking, delivery, human feedback loops.

Compiler-shaped IR example:
- IR0: `SourceSnapshot`
- IR1: `NormalizedDocument`
- IR2: `Items/Events`
- IR3: `RankedBriefing`
- Output artifacts: brief (md/pdf), citations, delivery receipts

Nondeterministic nodes:
- LLM summarization and/or relevance classification (record decisions)

Side effects:
- Delivery (email/slack/etc), tracked as exactly-once or idempotent

### 8.2 Software factory
**Primary value:** validates tool execution, sandboxing, compilation/test determinism, artifact packaging, repo side effects.

Nondeterministic nodes:
- LLM planning/coding

Deterministic nodes:
- builds/tests/formatters

Side effects:
- commits, PR creation, CI triggers (must be guarded)

### 8.3 House compiler
**Primary value:** validates multi-artifact compilation (PDF/NC/BOM), heavy compute (geometry), strict audit/replay, versioned rulesets.

Compiler-shaped IR example:
- IR0: `InputIntent` (parameters + site + template choices)
- IR1: `SemanticBuildingModel` (walls/roof/openings/load paths)
- IR2: `StructuralMemberModel` (studs/joists/rafters/beams)
- IR3: `ManufacturingModel` (parts, machining ops, panelization)
- Output artifacts: PDFs, NC files, BOM, compliance report

Key nondeterministic nodes:
- GA optimization (record evolution/selection decisions)

Key deterministic (or pinned) nodes:
- code checks, BOM extraction, PDF generation, exporters

---

## 9. Key challenges and risks

### 9.1 Geometry/detail correctness (house compiler)
The hardest domain problem is reliably turning semantic intent into manufacturable, correct framing and part breakdown. This is deterministic but complex.

Mitigation:
- template-based framing and junction libraries
- golden test cases (“this wall with this opening yields exactly these members”)

### 9.2 Ruleset/version management (house compiler)
Construction rules/regulations evolve. The system must:
- pin rulesets per run
- support running the same input against a different ruleset snapshot
- produce audit-ready evidence (what ruleset was applied)

### 9.3 Concurrency and accidental nondeterminism
Even pure Ops can become nondeterministic if aggregation order changes.

Mitigation:
- stable ordering before reduction
- deterministic serialization
- environment pinning for sensitive tools

### 9.4 NIF safety and isolation
NIF crashes can take down the BEAM.

Mitigation:
- prefer ports for risky/heavy operations
- supervise pools
- strict timeouts/memory caps

### 9.5 Side-effect correctness
Avoid duplicate emails, duplicate commits, duplicate exports.

Mitigation:
- idempotency keys
- “commit” phase separated from “compute” phase
- store external receipts

---

## 10. Requirements

### 10.1 Functional requirements (core runtime)

**MUST**
- Execute Ops as dependency graphs (DAG execution)
- Persist run manifests, artifacts, and execution events
- Provide deterministic replay modes (exact, verify, selective refresh)
- Support human approval/override as first-class decision nodes
- Support scheduled runs and manual runs
- Provide A2UI event stream and query APIs

**SHOULD**
- Support dynamic graph expansion
- Support caching/memoization for deterministic Ops
- Provide structured error handling and retries
- Provide run diffing (artifact + decision deltas)

**MAY**
- Support distributed execution across nodes
- Support priority queues and resource-aware scheduling

### 10.2 Non-functional requirements

**MUST**
- Fault tolerant (supervision, isolation)
- Observable (structured logs, metrics, traces)
- Secure artifact access (authz, encryption at rest if needed)

**SHOULD**
- Scale to many concurrent Ops
- Handle large binary artifacts efficiently

---

## 11. Data model sketches (illustrative)

### 11.1 Artifact
```json
{
  "artifact_id": "sha256:…",
  "type": "pdf|nc|bom|snapshot|ir",
  "schema_version": "…",
  "bytes": 123456,
  "metadata": {
    "source": "…",
    "created_at": "…",
    "tool": {"name": "…", "version": "…"},
    "ruleset": {"name": "…", "version": "…"}
  }
}
```

### 11.2 Run manifest
```json
{
  "run_id": "…",
  "workflow": {"name": "…", "version": "…"},
  "inputs": ["sha256:…"],
  "config": {"…": "…"},
  "op_versions": {"op_name": "git_sha_or_semver"},
  "rulesets": {"…": "…"},
  "environment": {"…": "…"},
  "policy": {"replay_mode": "verify"}
}
```

### 11.3 Op execution event
```json
{
  "event": "op_finished",
  "run_id": "…",
  "op_id": "…",
  "op_name": "…",
  "op_version": "…",
  "inputs": ["sha256:…"],
  "outputs": ["sha256:…"],
  "metrics": {"duration_ms": 1234}
}
```

### 11.4 Decision record
```json
{
  "decision_id": "sha256:…",
  "type": "llm_response|ga_step|human_override",
  "inputs": ["sha256:…"],
  "payload": "sha256:…",
  "metadata": {"created_at": "…"}
}
```

---

## 12. Suggested incremental roadmap

1. **Walking skeleton (core)**
   - artifact store + run manifest + event log + basic DAG executor + A2UI stream

2. **Omvärldsbevakning v0**
   - snapshot ingestion + dedup + ranking + briefing output + delivery
   - enforce IR discipline and decision recording

3. **House “spike” (minimal)**
   - small deterministic geometry/parts generator → BOM + one PDF
   - validates multi-artifact outputs and binary artifacts

4. **Scale packs in parallel**
   - software factory: tool execution + tests + repo effects
   - house compiler: expand IR, detailing, exporters, GA optimization

---

## 13. Open questions

- Where does IR live (in artifact store only vs also in a queryable database)?
- How to represent “capabilities” and agent selection (routing) cleanly?
- What is the minimal stable API between core engine and packs?
- What is the strategy for environment pinning (containers, Nix, toolchains)?
- What is the operational model for distributed execution?

---

## 14. Appendix: Agent types (taxonomy)

- **LLM Agent:** prompts + tool orchestration; outputs recorded decisions
- **Compute Agent:** deterministic/pinned functions; often pure
- **IO Agent:** fetch/publish; must snapshot inputs and guard side effects
- **Tooling Agent:** compilers/tests/renderers; pinned determinism
- **Human Gate Agent:** A2UI-mediated approval/override; creates decision records

