# Scale and Distribution Strategy

**Date:** 2026-04-02
**Context:** Liminara is designed as a general-purpose runtime for "any" pack — not just lightweight intelligence briefings (Radar) but potentially ML training pipelines, large-scale data processing, and compute-heavy engineering workflows. This document examines what "scale" means for different pack types, when distribution is needed, and how the executor abstraction should evolve to support it.

**Key question:** Should Liminara distribute the BEAM itself, or should it remain a single-node orchestrator that dispatches to distributed compute backends?

---

## 1. What "Scale" Means for Different Packs

Not all packs have the same compute profile. The scale requirements vary dramatically:

| Pack type | Compute profile | Data volume | Latency tolerance | GPU needed? | Single node? |
|-----------|----------------|-------------|-------------------|-------------|-------------|
| **Radar** (intelligence briefing) | Light CPU + API calls (LLM, search) | KBs–MBs per run | Minutes | No | Yes, easily |
| **VSME** (sustainability reporting) | Document processing, LLM analysis | MBs (reports, financials) | Hours | No | Yes |
| **House Compiler** (design→manufacturing) | Geometry computation, structural analysis | MBs–GBs (3D models) | Minutes–hours | Maybe (rendering) | Probably yes |
| **ML Training pack** | Multi-GPU distributed training | GBs–TBs (datasets, models) | Hours–days | **Yes, multi-GPU** | **No** |
| **Data Pipeline pack** | ETL, batch transforms | TBs (data lakes) | Hours | No | **No** (data locality) |
| **LLM Fine-tuning pack** | Multi-node GPU training | GBs (model weights, datasets) | Hours | **Yes, multi-node** | **No** |
| **Embedding Generation** (at scale) | Batch GPU inference | GBs (document corpus) | Hours | **Yes** | Depends on volume |
| **Process Mining pack** | CPU-intensive graph algorithms | GBs (event logs) | Minutes–hours | No | Probably yes |
| **DPP** (Digital Product Passport) | Light processing, compliance checks | KBs–MBs | Minutes | No | Yes |

**Observation:** The first four planned packs (Radar, VSME, House Compiler, DPP) all fit comfortably on a single node. ML training/fine-tuning and large-scale data processing are the only categories that genuinely need distributed compute — and these are *compute plane* problems, not *control plane* problems.

---

## 2. Three Planes, Three Scale Stories

### Control Plane (orchestration, scheduling, decision recording)

The DAG scheduler, event store, decision store, cache, artifact index. The "brain."

**A single OTP node handles this at any foreseeable scale.** Evidence:
- FlytePropeller is a single Go process coordinating thousands of K8s pods
- WhatsApp handled 2M+ connections per Erlang node
- Bleacher Report handled 10x traffic spikes on single-node Elixir
- Discord serves millions on Elixir (distributed, but that's for real-time state, not orchestration)
- Oban (Elixir job queue) processes hundreds of thousands of jobs on a single node with PostgreSQL-backed coordination

The control plane's job is: maintain the DAG state machine, dispatch work, record events, serve the observation UI. This is I/O-bound and coordination-heavy — exactly what OTP excels at. A single BEAM node can manage thousands of concurrent runs, each with dozens of ops, without breaking a sweat.

**When you'd need to distribute the control plane:** Only when running thousands of concurrent packs in a multi-tenant SaaS scenario. Not relevant for the foreseeable product roadmap.

### Compute Plane (where ops actually execute)

This is where scale matters — and where the executor abstraction is the key design decision.

**Current state:**
- `:inline` — in the BEAM process (microseconds, no isolation)
- `:task` — supervised OTP Task (milliseconds, crash isolation)
- `:port` — Python process via Erlang Port (seconds, process isolation, local)

**What's needed for "any pack":**
- `:container` — Docker container on the local machine (seconds, full env isolation)
- `:k8s_pod` — Kubernetes pod (5-30s overhead, cluster-scheduled, GPU-capable)
- `:ray_task` — Ray task/actor (sub-millisecond dispatch once cluster is up, GPU-aware, distributed)
- `:slurm_job` — SLURM batch job (seconds, HPC/bare-metal GPU clusters)

Each executor type has different overhead, isolation, and capability characteristics. The choice should be driven by the op's requirements, not by the pack.

### Storage Plane (artifacts, events, decisions)

Content-addressed artifacts scale with data volume:
- Small packs: local filesystem (Git-style sharded dirs). Works today.
- Medium packs: local filesystem with pruning/archival. Straightforward.
- Large packs (TBs): object storage (S3/GCS) with content-addressed keys. The SHA-256 addressing model works with any backend — swap the store implementation, keep the same hashes.

**Design implication:** The artifact store should have a pluggable backend interface. The current filesystem implementation is correct for now. An S3 backend is a natural evolution, not an architectural change.

---

## 3. The Executor Abstraction: Liminara's Key Architectural Decision

### Current Design

```
Op module                    Executor
┌──────────────┐            ┌──────────────┐
│ executor/0   │──────────► │ :inline      │ → direct function call
│ :inline      │            │ :task        │ → supervised Task
│ :port        │            │ :port        │ → Python via Port
│ :task        │            └──────────────┘
└──────────────┘
```

`Executor.run(op_module, inputs, opts)` dispatches based on `op_module.executor()`. Simple, clean.

### Target Design

```
Op module                    Executor                     Compute Backend
┌──────────────┐            ┌──────────────┐            ┌──────────────────┐
│ executor/0   │──────────► │ :inline      │──────────► │ BEAM process     │
│ resources/0  │            │ :task        │            │ OTP Task         │
│              │            │ :port        │            │ Local Python     │
│              │            │ :container   │            │ Local Docker     │
│              │            │ :k8s_pod     │            │ K8s cluster      │
│              │            │ :ray_task    │            │ Ray cluster      │
│              │            │ :slurm_job   │            │ SLURM cluster    │
└──────────────┘            └──────────────┘            └──────────────────┘
```

Key additions to the op contract:
- `resources/0` — declares resource requirements (`:cpu`, `:gpu`, `:memory`, `:gpu_type`)
- Executor selection could become automatic based on resource requirements + available backends
- **CUE constraint schemas** for op inputs/outputs, resource requirements, and executor capabilities — enabling plan-time validation that op requirements match available executor backends. Multi-source constraints (op requirements + executor capabilities + security policy) compose via lattice unification. See [cue_language.md](cue_language.md).

### The Contract

Every executor must implement the same interface:

```
execute(op_module, inputs, opts) → {:ok, outputs} | {:ok, outputs, decisions} | {:error, reason}
```

The control plane doesn't care where the op ran. It records the same events, decisions, and artifact hashes regardless of executor. This is the fundamental invariant.

### What Makes This Different From Flyte

Flyte's model: **everything is a container.** A string-hashing op gets a K8s pod. A GPU training job gets a K8s pod. The overhead is uniform (5-30s per task) regardless of task complexity.

Liminara's model: **the executor matches the op.** A pure Elixir op runs inline (microseconds). A Python embedding op runs via port (milliseconds). An ML training op runs on a Ray cluster (seconds to dispatch, hours to complete). All within the same plan.

**This is a genuine architectural advantage.** A Radar pipeline with 20 pure ops and 2 recordable LLM calls should not spawn 22 containers. It should run 20 ops inline and 2 via port, completing in seconds. Flyte cannot do this.

---

## 4. Compute Backend Options

### Ray as Executor Backend

**Best fit for:** GPU-intensive Python ops (training, fine-tuning, batch inference, large-scale embedding).

**Integration pattern:**
1. Liminara's `:ray_task` executor connects to a running Ray cluster via `ray.init(address="ray://<head>:10001")`
2. Submits a task/actor with resource requirements (`num_gpus=4`)
3. Ray handles scheduling, GPU allocation, data locality, fault tolerance
4. Executor polls for completion, retrieves outputs
5. Liminara records events/decisions as normal

**Alternatively:** Use the Ray Job Submission REST API (`POST /api/jobs/`) for heavier jobs. KubeRay's RayJob CRD for K8s-managed clusters.

**Why Ray over raw K8s:** Ray's sub-millisecond task dispatch (within a running cluster) vs K8s pod startup (5-30s). Ray handles distributed training natively (NCCL setup, checkpointing, gang scheduling). Ray is the compute fabric; K8s is the infrastructure.

**Who validates this pattern:** Flyte itself uses Ray as a backend plugin. So do Airflow, Dagster, and Prefect. OpenAI trained ChatGPT-era models on Ray. vLLM (the dominant LLM serving engine) runs on Ray.

**Scale:** Ray handles 1M+ tasks/second. Clusters of 1,000+ nodes with 10,000+ GPUs exist in production (OpenAI, ByteDance).

### Kubernetes as Executor Backend

**Best fit for:** Isolated container execution, heterogeneous environments, when Ray is overkill.

**Integration pattern:**
1. Liminara's `:k8s_pod` executor creates a K8s Job/Pod spec
2. Submits via K8s API (libraries: `k8s`, `Kazan` for Elixir)
3. Monitors pod status, streams logs
4. Retrieves outputs from shared volume or artifact store

**When to use K8s directly vs Ray:** K8s for isolated, self-contained tasks where container reproducibility matters (versioned environments, compliance requirements). Ray for fine-grained distributed compute where tasks share state or need fast communication.

### SLURM as Executor Backend

**Best fit for:** Organizations with existing bare-metal GPU clusters (research labs, universities, companies like Meta/Tesla/xAI that own hardware).

**Integration pattern:**
1. Liminara's `:slurm_job` executor submits via SLURM's REST API (`slurmrestd`, available since v20.02) or SSH + `sbatch`
2. Monitors job status via `squeue` / REST polling
3. Retrieves outputs from shared filesystem

**When relevant:** When a pack customer has SLURM infrastructure and no K8s. Not a priority for Liminara's initial packs.

### Local Container (Docker) as Executor Backend

**Best fit for:** Development, testing, dependency isolation without K8s.

**Integration pattern:**
1. Liminara's `:container` executor builds/pulls a Docker image
2. Runs `docker run` with mounted volumes for artifact I/O
3. Captures stdout/stderr, exit code, outputs

**Priority:** This should be the **first scale step** — it gives dependency isolation without K8s complexity. A natural evolution from `:port`.

---

## 5. OTP Distribution: When and How

### Arguments Against Distributing the BEAM

1. **Split-brain is hard.** BEAM has no built-in consensus. Network partitions cause split-brain that you must handle yourself. Most Elixir apps avoid this by using external coordination (PostgreSQL, Redis).
2. **Single-node capacity is enormous.** A single BEAM node handles millions of lightweight processes, hundreds of thousands of connections, thousands of concurrent runs.
3. **Distributed Erlang was designed for LAN.** Cookie-based auth, full-mesh topology (scales poorly beyond ~60-100 nodes), no encryption by default. Not designed for cloud regions with unreliable networks.
4. **Complexity.** Every distributed system must handle: message loss, reordering, duplication, partial failure, clock skew. A single-node system avoids all of this.

### Arguments For Distributing the BEAM

1. **Real-time observation across regions.** If runs execute in multiple regions, a distributed BEAM would enable real-time event streaming without an intermediary.
2. **Multi-tenant SaaS.** Many concurrent customers, each running many packs, might exceed single-node capacity.
3. **Hot failover.** If the control plane node dies, a distributed BEAM could fail over to a standby.

### The "Elixir as Orchestrator" Pattern

The research strongly points to this as the right model for Liminara:

**OTP supervises coordination state locally. Compute happens externally.**

Precedent:
- **Broadway** — Elixir consumes from RabbitMQ/SQS/Kafka, dispatches work. No BEAM distribution.
- **Oban** — Job queue backed by PostgreSQL. Horizontal scaling via DB coordination. No BEAM clustering.
- **Nx/Livebook** — Elixir orchestrates GPU computation via EXLA/XLA and Python ports.
- **K8s Elixir libraries** — Elixir manages Kubernetes resources as an external control plane.

**This is what Liminara should do:** The Run.Server GenServer manages the plan DAG. When an op needs a GPU, it dispatches to a Ray cluster. When an op is pure Elixir, it runs inline. The BEAM never needs to be distributed — it coordinates distributed compute through APIs.

### If Distribution Is Ever Needed

Start with:
1. **`pg` (process groups)** — built-in, partition-tolerant pub/sub. Already used for run observation.
2. **`libcluster`** — automatic node discovery (DNS, K8s, gossip).
3. **Horde** — distributed process registry and supervisor via delta-CRDTs.

Avoid:
- Partisan (less mature, requires replacing core networking)
- Full custom distribution (unnecessary complexity)

**Timeline:** Not before a multi-tenant SaaS deployment is needed. Single-node + external compute backends covers every planned pack.

---

## 6. The Executor Roadmap

### Phase 1: Current (done)
- `:inline` — pure Elixir ops
- `:task` — supervised OTP Tasks
- `:port` — Python via Erlang Port

Covers: Radar, VSME, DPP, most single-node packs.

### Phase 2: Container isolation (after VSME validates the runtime generalizes — platform generalization)
- `:container` — Docker on local machine
- Pluggable artifact store backend (filesystem → S3)

Covers: Packs with complex Python dependencies, reproducible environments, CI/CD.

*Note: Radar v1 and VSME use filesystem persistence and `:port` executor. Postgres, Oban, and container executor are platform generalization items (D-016, D-017, D-020) — deferred until cross-pack evidence justifies them.*

### Phase 3: Cluster compute (when a paying customer needs it)
- `:k8s_pod` — Kubernetes pod execution
- `:ray_task` — Ray cluster execution

Covers: ML training packs, large-scale embedding, GPU-intensive ops.

### Phase 4: Specialist backends (driven by demand)
- `:slurm_job` — HPC/bare-metal GPU clusters
- `:spark` — distributed data processing

Covers: Enterprise customers with existing HPC infrastructure.

### Design Principles

1. **Build executors when needed, not before.** Each executor is significant engineering investment. Don't build `:k8s_pod` until a customer needs it.
2. **The op contract is stable.** `execute(op_module, inputs, opts) → result`. New executors don't change the op interface.
3. **The control plane records everything regardless of executor.** Events, decisions, artifacts, hash chains — these are invariant. Where the op *ran* is metadata, not architecture.
4. **Resource declarations drive executor selection.** An op that declares `resources: [gpu: 2]` cannot run on `:inline`. The runtime should validate this and route to an appropriate executor.
5. **Executors are pack-agnostic.** The Radar pack doesn't know or care that `:ray_task` exists. If its embedding op grows to need a GPU, it changes `executor: :ray_task` and declares `resources: [gpu: 1]`. Everything else stays the same.

---

## 7. Scale Strategy Summary

```
┌─────────────────────────────────────────────────────────┐
│                    CONTROL PLANE                         │
│              Single OTP node (BEAM)                      │
│    ┌──────────┐ ┌──────────┐ ┌───────────┐              │
│    │Run.Server│ │Event.Store│ │Cache      │              │
│    │(GenServer)│ │(JSONL)   │ │(ETS+disk) │              │
│    └────┬─────┘ └──────────┘ └───────────┘              │
│         │ dispatch                                       │
│    ┌────▼──────────────────────────────────┐             │
│    │         EXECUTOR ROUTER               │             │
│    │  routes based on op.executor()        │             │
│    │  + op.resources() + available backends │             │
│    └────┬────┬────┬────┬────┬─────────────┘             │
│         │    │    │    │    │                             │
└─────────┼────┼────┼────┼────┼─────────────────────────── │
          │    │    │    │    │
          ▼    ▼    ▼    ▼    ▼         COMPUTE PLANE
       inline task port container  k8s/ray/slurm
       (μs)  (ms) (s)   (s)       (s-min)

       ◄── local ──► ◄── local ──► ◄── distributed ──►
```

**The thesis:** Liminara's control plane stays simple and single-node. The compute plane scales to whatever the pack needs. The executor abstraction is the bridge. Decision recording, event sourcing, and content addressing are invariant across all executors — this is the architectural moat that cannot be tacked onto Flyte or any other orchestrator.

---

*See also:*
- *[flyte_architecture.md](flyte_architecture.md) — Flyte deep dive, executor plugin model*
- *[build_vs_buy.md](build_vs_buy.md) — original build vs buy analysis*
- *[../analysis/04_HashiCorp_Parallels.md](../analysis/04_HashiCorp_Parallels.md) — Terraform parallels*
- *[ADJACENT_TECHNOLOGIES.md](ADJACENT_TECHNOLOGIES.md) — intellectual ancestors*

Sources:
- [Ray Documentation](https://docs.ray.io/)
- [Ray GitHub Repository](https://github.com/ray-project/ray)
- [SLURM Documentation](https://slurm.schedmd.com/)
- [KubeRay Project](https://github.com/ray-project/kuberay)
- [Oban — Robust Job Processing in Elixir](https://github.com/sorentwo/oban)
- [Horde — Distributed Supervisor and Registry](https://github.com/derekkraan/horde)
- [libcluster — Automatic BEAM Clustering](https://github.com/bitwalker/libcluster)
- [Broadway — Concurrent Data Ingestion](https://github.com/dashbitco/broadway)
- [Flyte Ray Plugin](https://docs.flyte.org/en/latest/flytesnacks/examples/ray_plugin/index.html)
- [Dagster Executor Documentation](https://docs.dagster.io/deployment/executors)
- [Airflow Executor Documentation](https://airflow.apache.org/docs/apache-airflow/stable/core-concepts/executor/index.html)
- [Temporal Worker Architecture](https://docs.temporal.io/workers)
