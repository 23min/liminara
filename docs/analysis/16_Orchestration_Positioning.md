# Orchestration Landscape Positioning

**Date:** 2026-04-02
**Context:** Strategic analysis of where Liminara sits relative to the workflow orchestration landscape. Triggered by the question: "Why would anyone pick Liminara if Flyte already exists?" This document synthesizes the Flyte deep dive, scale research, and our existing architectural analysis into a positioning statement.

**Prerequisite reading:**
- [flyte_architecture.md](../research/flyte_architecture.md) — technical deep dive on Flyte
- [scale_and_distribution_strategy.md](../research/scale_and_distribution_strategy.md) — scale and executor strategy
- [build_vs_buy.md](../research/build_vs_buy.md) — original build vs buy analysis
- [10_Synthesis.md](10_Synthesis.md) — Liminara's settled identity

---

## 1. The Landscape

### The Players

| System | Primary problem | Built with | Deployment | Scale target |
|--------|----------------|------------|------------|-------------|
| **Airflow** | Schedule and monitor data pipelines | Python | K8s, Celery, local | Enterprise ETL |
| **Dagster** | Software-defined assets with lineage | Python | K8s, local | Data platform teams |
| **Prefect** | Modern Airflow with better DX | Python | Cloud-hosted, K8s | Data engineering |
| **Flyte** | Reproducible ML pipelines at scale | Go + Python SDK | K8s (required) | ML platform teams |
| **Temporal** | Durable execution of long-running workflows | Go | K8s, self-hosted | Microservices, transactions |
| **Ray** | Distributed compute fabric | Python + C++ | K8s, bare metal, cloud | ML training and serving |
| **LangGraph** | LLM agent orchestration with checkpoints | Python | Any | AI agent developers |
| **Liminara** | Reproducible nondeterministic computation | Elixir/OTP | Single node | Domain packs |

### What They Have in Common

All of these systems (except Ray, which is compute fabric) solve some version of: "Define a DAG of operations, execute them reliably, handle failures." They all have:
- DAG-based execution (explicit or implicit)
- Some form of caching or memoization
- Retry/failure handling
- A web UI for monitoring
- Python as primary or supported SDK

### What Differentiates Them

The variation points that matter:

| Variation | Systems that do it well |
|-----------|------------------------|
| **Type safety** | Flyte (Protobuf-backed), Dagster (Python types + Pandera) |
| **Asset-centric lineage** | Dagster (Software-Defined Assets) |
| **Durable execution** | Temporal (event-sourced workflows), LangGraph (checkpoints) |
| **GPU scheduling** | Ray (native), Flyte (via Ray/K8s plugins) |
| **Container isolation** | Flyte (per-task containers), Airflow K8s executor |
| **Human-in-the-loop** | Temporal (signals), Flyte (signals), LangGraph (interrupts) |
| **Content-addressed artifacts** | **Liminara only** |
| **Decision records** | **Liminara only** |
| **Determinism classes** | **Liminara only** |
| **Hash-chained event logs** | **Liminara only** |
| **Replay with decision injection** | **Liminara only** |

---

## 2. Liminara Is Not a Workflow Orchestrator

This is the critical positioning insight. The landscape above groups Liminara with workflow orchestrators, but that's a category error.

**Workflow orchestrators answer:** "How do I reliably run this DAG?"

**Liminara answers:** "How do I prove what happened during a computation that involved choices?"

The orchestration (running the DAG) is necessary infrastructure, but it's not the product. The product is **decision provenance** — the ability to replay, audit, branch, and cryptographically verify computations that involve nondeterministic choices.

### An Analogy

Git is not a file synchronization tool. Dropbox synchronizes files. Git provides content-addressed history with branching and merging. You could use Dropbox to share code, but you'd lose the ability to diff, blame, bisect, and branch.

Similarly, you could run a Radar-like pipeline on Flyte. It would fetch, embed, summarize, deliver. But you'd lose:
- The ability to replay the run with the exact same LLM responses
- The ability to branch at a decision point and explore an alternative
- Cryptographic proof that the run wasn't tampered with
- Automatic cache invalidation based on determinism class

**Liminara is to Flyte as Git is to Dropbox.** Same underlying operations (file storage / DAG execution), fundamentally different model (content-addressed history / decision provenance).

---

## 3. The "Tack It On" Question

### Can you add decision provenance to Flyte?

You can get ~60-70% of the way:
- ✅ Log LLM responses in a side-store (Flyte Agent plugin)
- ✅ Record human approvals (Flyte Signals + logging)
- ✅ Cache deterministic tasks (DataCatalog, already works)
- ✅ Retry failures (two-tier retries, recovery mode)

You cannot get the remaining 30-40%:
- ❌ **Sub-task decision granularity.** Flyte records at task boundaries. A task with 3 internal decisions is opaque. Splitting every decision into its own task creates DAG explosion with 5-30s pod overhead per decision.
- ❌ **Event sourcing.** Flyte stores state snapshots in PostgreSQL, not append-only event logs. No time-travel, no reconstruction from events, no hash-chaining.
- ❌ **Content addressing.** Artifacts in blob storage with UUIDs. Same content stored per-execution. No deduplication, no cryptographic identity.
- ❌ **Determinism-aware caching.** Flyte caches assume all tasks are deterministic. No way to declare "this task is recordable — don't cache it, record its decision."
- ❌ **Lightweight execution.** Flyte can't run a trivial op in microseconds. Everything is a container. This makes it impractical for plans with many small pure ops.

### Why you'd be fighting the abstraction

The impedance mismatch is fundamental:

| Concern | Flyte's assumption | Liminara's assumption |
|---------|-------------------|----------------------|
| Unit of work | Container on K8s | Anything from inline function to GPU cluster |
| Nondeterminism | A bug (breaks caching) | A feature (recorded as decisions) |
| Run history | State snapshots | Append-only event stream |
| Artifact identity | Execution metadata (UUID) | Content hash (SHA-256) |
| Execution overhead | 5-30s per task (acceptable for ML jobs) | Microseconds–hours (varies by op type) |

You'd be building a second system inside Flyte — maintaining the decision store, the content-addressed store, the determinism class logic, the replay engine — while fighting Flyte's assumptions at every integration point. At that point, you're not using Flyte; you're working around it.

---

## 4. Where Liminara Competes and Where It Doesn't

### Liminara does NOT compete on:

| Capability | Leader | Liminara's position |
|------------|--------|-------------------|
| GPU scheduling at scale | Ray, Flyte | Delegate to Ray/K8s as executor backends |
| Enterprise data pipeline orchestration | Airflow, Dagster | Not the target market |
| Container-per-task isolation | Flyte | Future executor type, not core value |
| Multi-team workflow management | Flyte, Dagster | Single-team/single-pack for now |
| Kubernetes-native deployment | Flyte | Lightweight single-node is the feature |

### Liminara DOES compete on:

*Status note (D-014): these are architectural design properties. Multi-decision replay has a known correctness gap being fixed in Phase 5a. See gaps.md for details.*

| Capability | Nearest competitor | Liminara's advantage | Status |
|------------|-------------------|---------------------|--------|
| Decision provenance | LangGraph (checkpoints — snapshots, not decisions) | First-class decision records with determinism classes | `validated` for single-decision ops; `being fixed` for multi-decision ops |
| Reproducibility of nondeterministic computation | Temporal (durable execution — replays workflow code, not decisions) | Decision injection makes replay exact, not re-execution | `validated` for simple ops; `being fixed` for multi-output recordable ops |
| Tamper-evident audit trail | None | Hash-chained event logs with content-addressed artifacts | `validated` |
| Lightweight + heavyweight ops in same plan | None (Flyte = all heavyweight, LangGraph = all lightweight) | Executor spectrum from microseconds to hours | `validated` (`:inline`, `:task`, `:port`); `directional thesis` (`:container`, `:k8s_pod`, `:ray_task`) |
| Domain pack composability | Dagster (Software-Defined Assets) | Packs are self-contained: ops + plan builder + reference data | `validated` (Radar pack) |
| EU regulatory compliance | None built-in | Event sourcing + decision records + hash chains = Article 12 ready | `directional thesis` — runtime foundations exist, compliance-specific features not yet built |

---

## 5. The "Any Pack" Ambition

### What this requires architecturally

If Liminara should support *any* pack — including ML pipelines, not just intelligence briefings — the architecture needs:

1. **Pluggable executors** (`:inline` → `:ray_task` spectrum). Already designed, partially built.
2. **Resource declarations on ops** (`resources: [gpu: 2, memory: "32GB"]`). Not built yet.
3. **Pluggable artifact store** (filesystem → S3). Not built yet, straightforward.
4. **Formal op contracts via CUE** — constraint-based schemas for op inputs/outputs, resource declarations, and decision spaces. CUE's lattice-based validation is a better fit than Protobuf (FlyteIDL) because Liminara needs constraint *composition* (cross-pack compatibility, multi-source config, decision space validation), not code generation. See [cue_language.md](../research/cue_language.md). Not built yet.

What it does NOT need:
- Distributed BEAM (single-node orchestration, distributed compute)
- Its own GPU scheduler (delegate to Ray/K8s/SLURM)
- Its own container runtime (delegate to Docker/K8s)
- Its own data processing engine (delegate to Spark/Ray Data)

### The executor is the integration layer

A Liminara pack for ML training would look like:

```
preprocess_data (pure, :inline)     → cached, microseconds
split_train_test (pure, :inline)    → cached, microseconds
train_model (recordable, :ray_task) → decision: hyperparams tried, final weights hash, metrics
                                      dispatched to Ray cluster with 4 GPUs
evaluate_model (pure, :inline)      → cached, microseconds
human_review (recordable, :inline)  → decision: "approved for production" by reviewer X
deploy_model (side_effecting, :k8s) → skipped on replay
```

The same plan mixes microsecond inline ops with hour-long GPU training jobs. The control plane treats them identically — dispatch, wait, record events. The compute plane handles the differences.

**This is something no existing orchestrator can do.** Flyte would put every op in a container. Ray would require everything to be a Python task. Temporal would require everything to be an activity. Only Liminara's executor spectrum allows this heterogeneity without overhead.

---

## 6. What to Steal From Each System

| System | Pattern | Priority |
|--------|---------|----------|
| **Flyte** | Formal op contracts — but via CUE (constraint composition) rather than Protobuf (code-gen). See [cue_language.md](../research/cue_language.md). | Medium-term |
| **Flyte** | Recovery mode — "resume from last success" as explicit API | Near-term |
| **Flyte** | Tiered execution — agents for lightweight tasks, pods for heavy | Already have (`:inline` vs `:port`) |
| **Flyte** | DataCatalog as separate service — decouple artifact indexing from execution | Medium-term |
| **Dagster** | Software-Defined Assets — declarative "this artifact should exist and here's how" | Philosophical alignment already |
| **Dagster** | Two-level execution (launcher + executor) — separate "where does the coordinator live" from "where do steps run" | Worth studying |
| **Temporal** | Worker pull model — workers long-poll for tasks, no inbound connectivity needed | Good for future remote executors |
| **Ray** | Sub-millisecond task dispatch within a running cluster | Use Ray as executor backend |
| **Ray** | Placement groups / gang scheduling for multi-GPU ops | Delegate to Ray |
| **LangGraph** | Checkpoint-based time-travel debugging UX | Liminara's event log already enables more; steal the UX patterns |

---

## 7. The Competitive Moat

### What's defensible

1. **Decision provenance as architectural primitive.** This cannot be tacked onto an existing orchestrator (see section 3). Any competitor would need to rebuild from the ground up with decision records, determinism classes, and event sourcing as core concepts.

2. **Domain packs as the value layer.** Radar, VSME, House Compiler, DPP — these are products built on the runtime. The runtime enables them; the packs deliver value. No orchestrator provides domain-specific packs.

3. **Regulatory alignment.** EU AI Act Article 12, CSRD/VSME sustainability reporting, Digital Product Passport (Feb 2027) — all require provenance and auditability that no existing orchestrator provides natively.

4. **Lightweight deployment.** A single `mix phx.server` vs a Kubernetes cluster. For SMEs needing compliance reporting, the operational simplicity is a genuine advantage.

### What's commoditized

1. **DAG scheduling.** Every system does this. Liminara's scheduler doesn't need to be best-in-class; it needs to be correct.
2. **Retries and failure handling.** Solved by OTP supervision. Not a differentiator.
3. **Caching.** Input-hash caching is standard. Content-addressed caching is better but not a selling point on its own.
4. **Web UI.** Observation via Phoenix LiveView + A2UI is good but not a moat.

### The risk

**The risk is not Flyte.** Flyte solves a different problem for a different audience.

**The risk is that Liminara stays a runtime looking for users instead of becoming domain packs that solve real problems.** The architectural moat is strong, but architecture doesn't generate revenue. Packs do.

Priority (D-013):
1. Fix Radar correctness — multi-decision replay, determinism integrity
2. Harden Radar — sandbox, recovery, topic config
3. Ship VSME — validate the runtime generalizes
4. Platform generalization — only what both packs prove is needed
5. Don't build `:k8s_pod` or `:ray_task` executors until a paying customer needs them.

---

## 8. Positioning Statement

> **Liminara is a runtime for reproducible nondeterministic computation.**
>
> It records every choice — LLM responses, human approvals, stochastic selections — so any run can be replayed exactly, audited completely, and cached intelligently.
>
> Unlike workflow orchestrators (Flyte, Dagster, Airflow) that assume determinism, Liminara embraces nondeterminism as a first-class concept. Unlike AI agent frameworks (LangGraph, Temporal) that checkpoint state, Liminara records *decisions* — enabling exact replay, not just crash recovery.
>
> Run your ops anywhere — inline for microseconds, in containers for isolation, on GPU clusters for scale. The control plane records what happened and why, regardless of where it happened.
>
> The value is in the domain packs: intelligence briefings (Radar), sustainability compliance (VSME), computational design (House Compiler), digital product passports (DPP). The runtime enables them. The packs deliver value.

---

*See also:*
- *[10_Synthesis.md](10_Synthesis.md) — Liminara's settled identity*
- *[04_HashiCorp_Parallels.md](04_HashiCorp_Parallels.md) — Terraform parallels*
- *[02_Fresh_Analysis.md](02_Fresh_Analysis.md) — original landscape analysis*
- *[../research/flyte_architecture.md](../research/flyte_architecture.md) — Flyte technical deep dive*
- *[../research/scale_and_distribution_strategy.md](../research/scale_and_distribution_strategy.md) — scale and executor strategy*
- *[../research/build_vs_buy.md](../research/build_vs_buy.md) — Temporal, Dagster, Flyte, Prefect comparison*
- *[../research/agent_frameworks_landscape.md](../research/agent_frameworks_landscape.md) — LangGraph and Cloudflare Agents*
- *[../research/graph_execution_patterns.md](../research/graph_execution_patterns.md) — taxonomy of DAG execution systems*
