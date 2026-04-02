# Flyte: Architecture Deep Dive

**Date:** 2026-04-02
**Context:** Deep technical analysis of Flyte (flyte.org), the open-source workflow orchestration platform, examined through the lens of what Liminara can learn from it and where the architectures fundamentally diverge. Supersedes the brief Flyte section in [build_vs_buy.md](build_vs_buy.md).

---

## 1. What Flyte Is

Flyte is a **Kubernetes-native workflow orchestration platform** for ML and data pipelines. Originally built at Lyft (~2018), donated to the Linux Foundation (LF AI & Data), now maintained by Union.ai. Apache 2.0 licensed, ~6,900 GitHub stars. Union.ai (the commercial company) raised $38.1M Series A in Feb 2026; revenue grew 3x in 2025.

Flyte 2.0 (2025) moves toward dynamic, crash-proof, resource-aware AI orchestration — dynamic DAGs, not just static ones.

---

## 2. Core Concepts

| Concept | What it is |
|---------|-----------|
| **Task** | A Python function decorated with `@task`. The smallest unit of work. Runs in a container. |
| **Workflow** | A DAG of tasks, defined with `@workflow`. Composes tasks via typed connections. |
| **Launch Plan** | Binds a workflow to specific inputs + scheduling config. Like a "run configuration." |
| **Execution** | A concrete run of a workflow. Immutable once completed. |
| **FlyteIDL** | Protobuf-based Interface Definition Language. Every entity, type, and API contract is formally specified. Language-agnostic. |

### Comparison to Liminara

| Flyte | Liminara | Notes |
|-------|----------|-------|
| Task | Op | Both are typed functions. Flyte's are containerized; Liminara's have determinism classes. |
| Workflow | Plan | Both are DAGs. Flyte defines in Python decorators; Liminara builds programmatically in `plan/1`. |
| Launch Plan | Pack's `plan/1` function | Both bind a DAG to inputs. |
| Execution | Run | Both are immutable execution records. Liminara's is event-sourced; Flyte's is state-based. |
| FlyteIDL | CUE constraint schemas (planned) | CUE's lattice-based validation is a better fit than Protobuf for Liminara's composition-heavy needs. See [cue_language.md](../research/cue_language.md). |

---

## 3. Architecture

### Components

- **FlyteAdmin** — Control plane. Accepts workflow registrations, triggers executions, serves the API. Go + gRPC.
- **FlytePropeller** — Execution engine. A Kubernetes operator (Go) that watches `FlyteWorkflow` CRDs and traverses DAGs, launching pods for each task. One propeller instance per namespace.
- **DataCatalog** — Artifact indexing service. Maps `(task_version, hash(inputs))` → cached outputs. Separate from the execution engine.
- **FlyteConsole** — Web UI (React).
- **Blob Storage** — S3/GCS/Azure Blob for task outputs.
- **PostgreSQL** — Metadata storage for Admin.

### Data Flow

1. User registers a workflow (serialized Protobuf spec → FlyteAdmin → DB)
2. User creates an execution (FlyteAdmin creates a `FlyteWorkflow` CRD in K8s)
3. FlytePropeller watches for CRDs, traverses the DAG, launches pods
4. Each pod runs one task in a versioned container
5. Task outputs stored in blob storage, metadata in DataCatalog
6. Propeller updates CRD status as nodes complete
7. Data flows between tasks via **promises** — lazy references resolved at execution time

### What This Means

FlytePropeller is a **single Go process** coordinating potentially thousands of K8s pods. It doesn't execute user code — it manages state machines. This is architecturally similar to Liminara's `Run.Server` GenServer, except Flyte dispatches to K8s pods while Liminara dispatches to inline/task/port executors.

---

## 4. Type System

Flyte has a **strong, Protobuf-backed type system** defined in FlyteIDL. Python type hints on task inputs/outputs are required. Types are validated at registration time (before execution).

Supported types: primitives, dataframes (via `StructuredDataset` with column-level type checking), `FlyteFile`, `FlyteDirectory`, custom types via `TypeTransformer`. Integration with Pandera and Great Expectations for runtime data validation.

The type system is **language-agnostic at the protocol level** — SDKs exist for Python, Java/Scala, and (limited) JavaScript.

**Lesson for Liminara:** Liminara's op type signatures are implicit (whatever the `execute/1` function accepts). A formal schema for op inputs/outputs would enable plan-time validation and cross-language op execution. **CUE is a stronger fit than Protobuf here** — CUE's lattice-based constraint composition handles what Liminara actually needs: cross-field constraints on op contracts (`confidence: >=0.0 & <=1.0`), multi-source configuration merging (pack defaults + security policy + user overrides), and cross-pack compatibility checking via unification. Protobuf's advantage (code-gen, gRPC) is less relevant since Liminara's bottleneck is op execution, not message serialization. See [cue_language.md](cue_language.md) for full analysis.

---

## 5. Caching (DataCatalog)

Flyte's caching is the most architecturally relevant feature to study.

### Cache Key

```
cache_key = hash(task_name, cache_version, type_signature, hash(input_values))
```

- `cache_version`: user-specified string on the `@task` decorator. Bump it to invalidate.
- `type_signature`: hash of input/output parameter types.
- `hash(input_values)`: deterministic hash of the actual input data.

### Mechanism

1. Before executing a task, Propeller queries DataCatalog: "do we have a cached output for this key?"
2. If yes → skip execution, return cached artifact reference.
3. If no → execute, store output in blob storage, register in DataCatalog.

### Customization

- `HashMethod` annotations on outputs allow custom hashing (e.g., hash only specific columns of a dataframe).
- Cache is shared across executions — any workflow using the same task+version+inputs gets the cached result.
- Local development cache: `diskcache.Cache` at `~/.flyte/local-cache/`.

### Comparison to Liminara

| Aspect | Flyte | Liminara |
|--------|-------|----------|
| Cache key | `hash(task, version, types, inputs)` | `hash(op_name, op_version, sorted_input_hashes)` |
| Storage | Blob storage (S3/GCS) + metadata in DataCatalog | Content-addressed filesystem (SHA-256) |
| Deduplication | By key only — same content stored per-execution | By content — same content stored once |
| Invalidation | Bump `cache_version` | Change op version or input content |
| Determinism-aware? | **No** — assumes all tasks are deterministic | **Yes** — only `pure` and `pinned_env` ops are cached |

**Critical difference:** Flyte's caching **assumes determinism**. If a task produces different output for the same inputs (LLM call, random seed), Flyte either returns a stale cached result or requires the user to bump `cache_version`. There is no concept of "this task is nondeterministic, don't cache it but record what happened."

---

## 6. Reproducibility Model

Flyte achieves reproducibility through:

1. **Versioning** — every workflow/task registration creates a new immutable version
2. **Containerization** — each task runs in a specific Docker image with pinned dependencies (ImageSpec)
3. **Strong typing** — enforced at registration time
4. **Ephemeral compute** — tasks run on fresh, disposable K8s pods

This is **environment-level reproducibility** — "run the same code in the same container with the same inputs." It does NOT provide:

- **Decision-level reproducibility** — "what did the LLM say?" is not recorded
- **Event-level reproducibility** — "reconstruct exactly what happened during this run" is not possible from Flyte's state-based records
- **Tamper-evidence** — no hash-chaining, no cryptographic commitment to execution history

**Assessment:** Flyte's reproducibility is comparable to Nix's — deterministic given a fixed environment. Liminara's extends beyond this to handle irreducible nondeterminism via decision records.

---

## 7. Execution Model and Fault Tolerance

### Retries

Two-tier: **system retries** (infrastructure failures — OOM, spot preemption) and **user retries** (application errors). Configured separately per task. System retries do not count against user retry budget.

### Intratask Checkpointing

Long-running tasks can save/restore internal state via `cp.write()`/`cp.read()`. On retry, the task reads its last checkpoint and resumes. Useful for spot instances.

**Limitation:** Low-level API only — no framework integration with PyTorch/Keras. Does not work in local development.

### Recovery Mode

Given a failed execution, Flyte can **copy all successful node outputs and re-run only failed nodes**. This is not replay (no decision injection) — it's "resume from cached results."

**Lesson for Liminara:** Recovery mode is a pragmatic feature worth adopting. Liminara's event log enables this naturally (read the log, skip completed nodes, dispatch only incomplete ones), but the explicit "create a recovery execution from a failed one" UX pattern is good design.

### Human-in-the-Loop

Added in v1.6 via Signals: `wait_for_input()` pauses a workflow until an external value arrives; `approve()` gates execution on human approval. The workflow pod stays alive (sleeping) during the wait.

**Comparison:** Liminara's gate ops return `{:gate, prompt}` and the Run.Server suspends — event log persists state, no sleeping pod needed. More efficient for long waits.

---

## 8. Plugin / Executor Model

Flyte's extensibility centers on **plugins** — every task type is backed by a plugin:

### Native Plugins (in FlytePropeller, Go)

- **Container** — default, runs a Docker container in a K8s pod
- **K8sPod** — full pod spec control (sidecars, volumes, etc.)
- **Sql** — SQL query execution

### Backend Plugins (loaded into Propeller)

- Spark (via Spark-on-K8s operator)
- Ray (via KubeRay)
- Kubeflow (PyTorch, TensorFlow distributed training)
- SageMaker, Athena, Hive, BigQuery

### Flyte Agents (newer, async)

Long-running agent processes that handle lightweight/async tasks without spawning a pod. Solves the "pod-per-task overhead for trivial operations" problem.

### The Plugin Interface

```go
BuildResource()    // Create the execution spec
GetTaskPhase()     // Poll for status
BuildIdentityResource()  // Template
```

**Lesson for Liminara:** Flyte's tiered plugin model is well-designed. The distinction between heavyweight plugins (pod per task) and lightweight agents (shared process) is exactly the spectrum Liminara needs: `:inline`/`:task` (lightweight, in-BEAM) vs `:port` (medium, local process) vs future `:container`/`:k8s_pod` (heavyweight, isolated).

---

## 9. Cost Model

| Deployment | Cost |
|------------|------|
| **Self-hosted** | ~$150-300/mo minimum (K8s cluster + blob storage + PostgreSQL). Scales with cluster size. |
| **Union.ai Team** | $950/mo (converts to usage credits) + pay-per-use: CPU $0.042/vCPU-hr, GPU $0.15-2.85/hr depending on model |
| **Union.ai Enterprise** | Custom pricing, volume discounts |
| **Operational overhead** | High for self-hosted — 5 services (Admin, Propeller, Console, DataCatalog, blob store), Helm charts, database migrations, auth setup |

For comparison, Liminara runs on a single `mix phx.server` with zero infrastructure dependencies.

---

## 10. Who Uses Flyte

| Company | Use case | Scale |
|---------|----------|-------|
| **Lyft** | ML pipelines (origin) | Production at scale |
| **Spotify** | ML workflows — cut quarterly forecast time in half | Millions of workflows |
| **LinkedIn** | Distributed GNN training | Large-scale |
| **Warner Bros. Discovery** | ML workflow delivery | Production |
| **Wayve** | Autonomous driving ML | GPU-heavy |
| **Freenome** | Cancer detection blood tests | Regulated domain |
| **MethaneSAT** | Methane monitoring from satellite data | Scientific/regulatory |
| **Cradle** | Protein design | Biotech |
| **Pachama** | Carbon credit measurement | Environmental |

The user base skews heavily toward **ML platform teams at mid-to-large companies**. For pure data engineering / ETL, teams still typically use Airflow (Lyft's own blog confirms this).

---

## 11. Could Decision Recording Be Tacked Onto Flyte?

**Partially, with fundamental limitations.**

### What you could build

- A **Flyte Agent** that wraps LLM calls, logs request/response to a side-store. Doable.
- Use **Signals** for human approvals, record the approval in the side-store. Doable.
- A **custom TypeTransformer** that adds SHA-256 content hashing to artifacts. Doable but parallel to DataCatalog, not integrated.

### What you'd lose

1. **Granularity** — Flyte records at task boundaries. Multiple decisions within a single task are invisible. You'd need to split every decision into its own task → DAG explosion, 5-30s pod overhead per decision.
2. **Decision semantics** — No concept of determinism classes. The cache doesn't know "this task is nondeterministic, don't cache it." You'd encode this in task metadata and naming conventions.
3. **Event sourcing** — Flyte's execution model is state-based (node status transitions in PostgreSQL). No append-only log, no hash-chaining, no tamper-evidence, no time-travel.
4. **Content addressing** — Artifacts in blob storage with UUID paths. No deduplication by content, no cryptographic provenance.
5. **K8s coupling** — Every op is a container. A trivial hash operation gets a pod (5-30s overhead). Absurd for lightweight ops.

### Verdict

You could build a Flyte plugin that logs LLM responses and human approvals, but you'd be fighting the abstraction at every turn. The impedance mismatch is fundamental — Flyte's unit of work is a containerized task on K8s; Liminara's is a lightweight op with recorded nondeterminism. It would be simpler to build decision recording natively than to bend Flyte's architecture to support it.

---

## 12. What Liminara Should Steal From Flyte

| Pattern | Why | Priority |
|---------|-----|----------|
| **Formal op contracts via CUE** | CUE constraint schemas for ops, plans, decisions. Lattice-based validation enables cross-pack compatibility checking and multi-source config composition — advantages Protobuf can't provide. See [cue_language.md](cue_language.md). | Medium-term |
| **ImageSpec / container isolation** | Per-task dependency pinning. Liminara's Python port executor has ad-hoc dependency management. | When `:container` executor is built |
| **Recovery mode UX** | "Create a recovery run from a failed one" as an explicit API, not just "the event log enables this." | Near-term |
| **DataCatalog separation** | Separating artifact indexing from execution is clean. Liminara's cache is tightly coupled to the runtime. | Medium-term |
| **Tiered execution** | Agents (lightweight) vs pods (heavyweight) for different task types. Liminara already has this (`:inline` vs `:port`) but should formalize the spectrum. | Near-term |
| **Dynamic workflows** | Flyte 2.0's dynamic DAG capabilities — tasks calling other tasks, branching at runtime. Relevant for discovery mode. | On roadmap |

---

*See also:*
- *[build_vs_buy.md](build_vs_buy.md) — original brief comparison (Temporal, Dagster, Flyte, Prefect)*
- *[graph_execution_patterns.md](graph_execution_patterns.md) — taxonomy of DAG execution systems*
- *[agent_frameworks_landscape.md](agent_frameworks_landscape.md) — LangGraph and Cloudflare Agents comparison*
- *[../analysis/04_HashiCorp_Parallels.md](../analysis/04_HashiCorp_Parallels.md) — Terraform architectural parallels*

Sources:
- [Flyte Official Documentation](https://docs.flyte.org/)
- [Flyte GitHub Repository](https://github.com/flyteorg/flyte)
- [FlyteIDL Repository](https://github.com/flyteorg/flyteidl)
- [FlytePropeller Architecture](https://docs.flyte.org/en/latest/user_guide/concepts/component_architecture/flytepropeller_architecture.html)
- [Flyte Caching Documentation](https://docs-legacy.flyte.org/en/v1.11.0/user_guide/development_lifecycle/caching.html)
- [Union.ai Pricing](https://www.union.ai/pricing)
- [Union.ai Series A Announcement](https://finance.yahoo.com/news/union-ai-completes-38-1-140000054.html)
- [Lyft Engineering: Flyte vs Airflow](https://eng.lyft.com/orchestrating-data-pipelines-at-lyft-comparing-flyte-and-airflow-72c40d143aad)
- [Introducing Flyte 2.0](https://www.union.ai/blog-post/introducing-flyte-2-0-dynamic-crash-proof-resource-aware-ai-orchestration)
- [Achieving Reproducible Workflows with Flyte](https://www.union.ai/blog-post/achieving-reproducible-workflows-with-flyte)
