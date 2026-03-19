---
id: E-06-execution-engine
phase: 2
status: done
---

# E-06: Execution Engine (Plan + Op + Run.Server)

## Goal

Implement the execution side of the runtime: the Plan data structure, the Op behaviour, and the Run.Server that drives the scheduler loop. This is the core of Liminara — "find ready nodes, dispatch, collect, repeat."

## Scope

**In:**

### Plan (`Liminara.Plan`)
- Data structure: a graph of nodes, each naming an op and declaring inputs
- `Plan.new()` → empty plan
- `Plan.node(plan, node_id, op_name, inputs)` → adds a node
- Input types:
  - `literal(value)` — a static value provided at plan construction
  - `ref(node_id)` — the output of another node
- `Plan.ready_nodes(plan, completed_nodes)` → nodes whose inputs are all resolved
- `Plan.all_complete?(plan, completed_nodes)` → boolean
- Validates: no cycles (it's a DAG), no dangling refs, no duplicate node IDs

### Op behaviour (`Liminara.Op`)
- `@callback execute(inputs :: map()) :: {:ok, outputs :: map(), decisions :: list()} | {:error, reason}`
- Ops declare: `name`, `version`, `determinism` (`:pure`, `:pinned_env`, `:recordable`, `:side_effecting`)
- Ops are modules that implement the behaviour — the runtime dispatches to them
- The Op module is the unit of work — it receives input artifacts and produces output artifacts

### Run.Server (`Liminara.Run.Server`)
- GenServer that owns one run's lifecycle
- State: plan, current node statuses, event log reference, decision store reference
- The scheduler loop:
  1. Find ready nodes (all inputs resolved, not yet started)
  2. Dispatch each to an executor (`:inline` or `:task`)
  3. On completion message: record event, store artifacts, check what's ready next
  4. On failure message: record event, apply error policy (fail the run for now)
  5. When all nodes complete: emit `run_completed`, compute seal
- Message-driven: `{:node_completed, node_id, outputs}`, `{:node_failed, node_id, error}`
- Emits events to Event.Store for every state transition
- `:inline` executor: calls `Op.execute/1` directly in the Run.Server process
- `:task` executor: spawns a supervised `Task` that calls `Op.execute/1`

### Supervision tree (minimal)
```
Liminara.Supervisor
├── Liminara.Artifact.Store        (from E-05)
├── Liminara.Event.Store           (from E-05)
├── Liminara.Run.Registry          (Registry for run_id → pid)
└── Liminara.Run.DynamicSupervisor
    └── Liminara.Run.Server (per run)
        └── Task.Supervisor (per run, for :task executor)
```

### Cache (`Liminara.Cache`)
- `cache_key = sha256(op_name, op_version, sorted_input_hashes)`
- Before dispatching a `:pure` or `:pinned_env` op: check cache
- On cache hit: skip execution, emit `op_completed` with `cache_hit: true`
- On cache miss: execute, store result in cache
- `:recordable` and `:side_effecting` ops are never cached
- ETS-based cache (in-memory, lost on restart, rebuilt as runs re-execute)

**Out:**
- Discovery mode (dynamic DAG expansion)
- Gates / human-in-the-loop
- Distributed execution
- Port, NIF, or container executors
- Observation layer / pub/sub
- Oban / scheduling

## Milestones

| ID | Milestone | Status |
|----|-----------|--------|
| M-EE-01-plan | Plan data structure, node/ref/literal, ready_nodes, validation (no cycles, no dangling refs) | done |
| M-EE-02-op | Op behaviour, determinism classes, executor dispatch (inline + task) | done |
| M-EE-03-run-server | Run.Server GenServer, scheduler loop, supervision tree, event recording | done |
| M-EE-04-cache | Cache (ETS), cache key computation, hit/miss logic per determinism class | done |

## Success criteria

- [x] Can define a Plan with 3+ nodes, refs between them, and literals
- [x] Plan rejects cycles and dangling refs
- [x] `ready_nodes` correctly identifies nodes whose inputs are all resolved
- [x] Op behaviour: a module implementing Op can be dispatched and produces outputs
- [x] Run.Server: runs a 3-node linear plan to completion, emitting all events
- [x] Run.Server: runs a fan-out plan (A → B, A → C) with parallel dispatch
- [x] Run.Server: handles op failure (records event, fails run)
- [x] Cache: pure op with same inputs → cache hit, no re-execution
- [x] Cache: recordable op → never cached, always executes
- [x] Event log for a completed run has valid hash chain

## References

- Architecture: `docs/architecture/01_CORE.md` § The plan, § The scheduler, § How it maps to OTP, § Caching
- Data model: `docs/analysis/11_Data_Model_Spec.md` § Event types
