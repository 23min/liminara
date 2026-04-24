# Build vs Buy: Temporal, Dagster, Flyte, and the Custom Path

**Date:** 2026-03-02
**Context:** Supporting research for Liminara core runtime analysis

---

## The Question

Could Liminara's core runtime be built on top of an existing orchestrator instead of custom Elixir/OTP?

## Temporal

### What it gives you for free

| Liminara Need | Temporal Feature | Fit |
|---|---|---|
| Durable execution / crash recovery | Event-sourced workflow replay | Excellent |
| Retries / timeouts / heartbeats | Built-in activity policies | Excellent |
| Dynamic DAG expansion | Child workflows, loops, ContinueAsNew | Good |
| Human-in-the-loop gates | Signals + queries | Good |
| Scheduling | Temporal Schedules (cron-like) | Good |
| Multi-tenancy | Namespaces | Good |
| Cancellation propagation | Cancellation scopes | Good |

### What you'd still build

- Content-addressed artifact store (entire system)
- Decision record capture and injection
- Three replay modes (exact, verify, selective refresh)
- Plan DAG visualization and inspection
- Budget enforcement (tokens, compute, wall-clock)
- Domain pack registration and schemas
- The observation UI
- Run diffing

**Assessment:** You'd use ~30-40% of what Temporal provides and build 60-70% of Liminara's surface area on top.

### The Elixir SDK problem

There is **no official Temporal Elixir SDK.** The practical path would be:
- Write workflow code in Go or TypeScript (a supported SDK)
- Write activity workers in Elixir (via gRPC)
- Result: a polyglot architecture that splits the most interesting code across two languages

### Operational burden

Temporal Server requires Cassandra or PostgreSQL + Elasticsearch. Heavy for a solo-dev, local-first project.

### Verdict

Temporal solves the hardest infrastructure problem (durable execution) but not the hardest domain problems (artifact provenance, decision records, replay modes). The ecosystem mismatch with Elixir makes it impractical without abandoning the BEAM for orchestration.

---

## Dagster

### Why it's the closest philosophical match

Dagster's core abstraction is the "Software-Defined Asset" — a declarative description of a data artifact and how to produce it. This maps directly to Liminara's "artifact-first" model.

| Liminara Need | Dagster Feature | Fit |
|---|---|---|
| Artifact-first model | Software-Defined Assets | Best match |
| DAG execution | Asset dependency graphs | Good |
| Selective re-materialization | Re-materialize specific assets | Conceptually close to selective refresh |
| Lineage | Asset lineage tracking | Partial (no content hashing) |
| Dynamic expansion | Dynamic partitions, @graph | Partial |
| Human-in-the-loop | Manual materialization, sensors | Limited |
| Content addressing | Not built-in | Gap |
| Decision records | Not built-in | Gap |
| Replay modes | Not built-in | Gap |

### The tradeoff

Dagster is Python-only. You'd lose the BEAM advantages (supervision, fault tolerance, lightweight processes for many concurrent runs). But you'd gain an ecosystem, a community, a battle-tested UI, and years of hardening.

### Verdict

If the goal is shipping products (Radar, house compiler), Dagster is worth serious consideration. If the goal is building a platform as the intellectual project, the philosophical alignment is useful as a reference but not a reason to adopt.

---

## Flyte

### Strongest fit for caching

Flyte's input-hash caching (`(task_version, hash(inputs)) -> cached_output`) is exactly Liminara's memoization model. Flyte also has:
- Typed data passing between tasks
- Containerized execution
- Dynamic workflow expansion (@dynamic)
- Projects + domains for multi-tenancy

### The tradeoff

Deeply Kubernetes-native (requires a K8s cluster). Python-centric. No decision records, no replay modes, no HITL pause/approve.

### Verdict

Best reference implementation for cache semantics. Study Flyte's caching before implementing Liminara's.

---

## Prefect

Closer to "modern Airflow" than to Liminara. Has `suspend_flow_run` for HITL, which is a useful pattern to study, but lacks artifacts, provenance, and replay.

---

## What to steal from each

| System | Pattern to adopt |
|---|---|
| Temporal | Event sourcing for run state; activity heartbeats; signal-based HITL |
| Dagster | Asset-first thinking; selective re-materialization |
| Flyte | Input-hash caching; typed data passing between ops |
| Prefect | `suspend_flow_run` with input collection as HITL pattern |
| Bazel | CAS + action cache separation (content store vs recipe-to-result mapping) |
| AiiDA | Provenance graph model; full lineage DAG |

---

## Bottom line

The unique value of Liminara (artifact provenance, decision records, replay modes, pack-defined IR pipelines) is entirely above what any existing orchestrator provides. The durability layer — the part Temporal excels at — is the most commoditized part and is well-served by Elixir/OTP supervision + Postgres event sourcing.

**Recommendation:** Build custom, but aggressively steal patterns. Consider Oban (Elixir job library) for the scheduler layer instead of rolling your own GenServer state machine.
