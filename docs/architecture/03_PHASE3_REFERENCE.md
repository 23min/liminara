# Liminara: Phase 3 Reference Architecture

**Snapshot date:** 2026-03-19
**Status:** Phase 3 complete. OTP Runtime Layer built and tested.
**Test suite:** 8 properties + 229 tests, 0 failures

---

## What exists

The Liminara runtime is a working OTP application that can:

- Execute arbitrary DAGs of operations with concurrent fan-out/fan-in
- Record every nondeterministic choice as a decision record
- Replay any run deterministically by injecting stored decisions
- Cache pure operation results across runs
- Pause execution at gate nodes and resume on external input
- Broadcast every event to subscribers in real-time via `:pg`
- Recover from crashes by rebuilding state from the event log
- Produce tamper-evident, hash-chained event logs in JSONL format
- Store artifacts in a content-addressed filesystem (Git-style sharding)

All of this runs on pure BEAM — zero external dependencies beyond the Erlang runtime and Jason for JSON.

---

## How to run it

From the repository root:

```bash
# Enter the runtime umbrella
cd runtime/apps/liminara_core

# Install dependencies
mix deps.get

# Run the full test suite
mix test

# Run with verbose output
mix test --trace

# Run a specific test file
mix test test/liminara/run/genserver_test.exs

# Run property-based tests only
mix test test/liminara/property_test.exs

# Format check
mix format --check-formatted

# Interactive shell with the application running
iex -S mix
```

### From the IEx shell

```elixir
# The application starts automatically (supervision tree, stores, registry)

# Run the ToyPack (needs a gate resolver)
alias Liminara.{Plan, Run}

# Simple plan without gates
plan = Plan.new()
|> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "hello world"}})
|> Plan.add_node("b", Liminara.TestOps.Reverse, %{"text" => {:ref, "a", "result"}})

{:ok, _pid} = Run.Server.start("my-run-1", plan)
{:ok, result} = Run.Server.await("my-run-1")
# => %Run.Result{status: :success, outputs: %{"a" => ..., "b" => ...}, ...}

# Read an artifact
{:ok, content} = Liminara.Artifact.Store.get(result.outputs["b"]["result"])
# => "DLROW OLLEH"

# Verify event chain
{:ok, count} = Liminara.Event.Store.verify("my-run-1")

# Subscribe to events from a run
Run.subscribe("my-run-2")
{:ok, _pid} = Run.Server.start("my-run-2", plan)
# Your process receives {:run_event, "my-run-2", event} for each event

# Inspect a running server
{:ok, pid} = Run.Server.start("my-run-3", plan)
:sys.get_state(pid)
```

---

## Supervision tree

```
Liminara.Supervisor (one_for_one)
├── Liminara.Artifact.Store          GenServer — owns filesystem blob store
├── Liminara.Event.Store             GenServer — owns JSONL event log directory
├── Liminara.Decision.Store          GenServer — owns decision record directory
├── Liminara.Cache                   GenServer — owns ETS named table
├── :pg (:liminara scope)            OTP process groups for event broadcasting
├── Liminara.Run.Registry            Registry (unique keys: run_id → pid)
└── Liminara.Run.DynamicSupervisor   DynamicSupervisor
    ├── Run.Server ("run-1")         GenServer — owns one run's lifecycle
    │   └── Task.Supervisor          per-run, supervises op Tasks
    │       ├── Task (op "fetch")
    │       ├── Task (op "parse")
    │       └── ...
    ├── Run.Server ("run-2")
    │   └── Task.Supervisor
    └── ...
```

Each run is an isolated subtree. One run's crash doesn't affect others.

---

## Module map

```
liminara_core/lib/
├── liminara.ex                    Public API: run/3, replay/4
├── liminara_core.ex               Version helper
└── liminara/
    ├── application.ex             OTP Application, supervision tree
    ├── op.ex                      Op behaviour (4 callbacks)
    ├── pack.ex                    Pack behaviour (4 callbacks)
    ├── plan.ex                    DAG data structure + validation
    ├── run.ex                     Synchronous executor + subscribe/unsubscribe
    ├── run/
    │   └── server.ex              GenServer: async executor, gate, crash recovery
    ├── executor.ex                Dispatches op execution (inline or Task)
    ├── cache.ex                   ETS-based memoization
    ├── hash.ex                    SHA-256 hashing (artifacts, events, decisions)
    ├── canonical.ex               RFC 8785 canonical JSON
    ├── artifact/
    │   └── store.ex               Content-addressed blob storage
    ├── event/
    │   └── store.ex               Append-only hash-chained JSONL event logs
    └── decision/
        └── store.ex               Decision record storage (one JSON per gate/choice)
```

---

## Data flow: a run from start to finish

```
                         ┌─────────────────────────────────────────────┐
                         │              Run.Server (GenServer)          │
                         │                                             │
  Liminara.run(Pack, input)                                            │
        │                │  1. pack.plan(input) → Plan (DAG)           │
        ▼                │  2. emit "run_started"                      │
  DynamicSupervisor      │  3. dispatch_ready loop:                    │
    start_child ────────►│     ┌──────────────────────────────────┐    │
                         │     │ For each ready node:              │    │
                         │     │  • Cache hit? → complete inline   │    │
                         │     │  • Replay inject? → complete      │    │
                         │     │  • Gate? → :waiting               │    │
                         │     │  • Else → Task.Supervisor.async   │    │
                         │     └──────────────────────────────────┘    │
                         │                                             │
                         │  4. Task completes → handle_info            │
                         │     • Store artifacts                       │
                         │     • Record decisions                      │
                         │     • Update cache                          │
                         │     • Emit events + broadcast via :pg       │
                         │     • Dispatch newly ready nodes            │
                         │                                             │
                         │  5. All nodes done → emit "run_completed"   │
                         │     • Write seal                            │
                         │     • Notify awaiting callers               │
                         │     • Stop (normal exit)                    │
                         └─────────────────────────────────────────────┘
```

---

## The five concepts

### Artifact

Immutable, content-addressed blob. Stored on the filesystem in Git-style sharded directories.

```
{store_root}/a1/b2/a1b2c3d4e5f6...    (SHA-256 of content)
```

Hash format: `sha256:{64 lowercase hex chars}`. Writes are idempotent — same content, same hash, one file.

### Op

A typed function with a determinism class. Four callbacks:

| Callback | Returns |
|----------|---------|
| `name()` | `String.t()` |
| `version()` | `String.t()` |
| `determinism()` | `:pure \| :pinned_env \| :recordable \| :side_effecting` |
| `execute(inputs)` | `{:ok, outputs}` or `{:ok, outputs, decisions}` or `{:gate, prompt}` or `{:error, reason}` |

Determinism controls caching and replay behavior:

| Class | Cache? | On replay |
|-------|--------|-----------|
| `:pure` | Yes | Re-execute (or cache hit) |
| `:pinned_env` | Yes (with env hash) | Re-execute (or cache hit) |
| `:recordable` | No | Inject stored decision |
| `:side_effecting` | No | Skip |

### Decision

A recorded nondeterministic choice. Stored as one JSON file per decision:

```
{runs_root}/{run_id}/decisions/{node_id}.json
```

Fields: `node_id`, `op_id`, `op_version`, `decision_type`, `inputs`, `output`, `decision_hash`, `recorded_at`. The `decision_hash` is computed over all other fields, providing tamper evidence.

### Run

An execution = an append-only event log + a plan. The event log IS the run.

```
{runs_root}/{run_id}/events.jsonl     Hash-chained JSONL
{runs_root}/{run_id}/seal.json        Final event hash = run seal
{runs_root}/{run_id}/decisions/       One JSON per recordable op
```

### Pack

A module that provides ops and knows how to plan. Four callbacks:

```elixir
@callback id() :: atom()
@callback version() :: String.t()
@callback ops() :: [module()]
@callback plan(input :: term()) :: Plan.t()
```

---

## Event types and hash chain

Every event is canonical JSON (RFC 8785), one per line in `events.jsonl`. Each event contains `prev_hash` — the SHA-256 of the previous event — creating a tamper-evident chain. The final event's hash is the **run seal**.

| Event | Payload | When |
|-------|---------|------|
| `run_started` | run_id, pack_id, pack_version, plan_hash | Run begins |
| `op_started` | node_id, op_id, op_version, determinism, input_hashes | Before dispatch |
| `op_completed` | node_id, output_hashes, cache_hit, duration_ms | Op finishes |
| `op_failed` | node_id, error_type, error_message, duration_ms | Op crashes |
| `decision_recorded` | node_id, decision_hash, decision_type | Nondeterministic choice |
| `gate_requested` | node_id, prompt | Op returns `{:gate, prompt}` |
| `gate_resolved` | node_id, response | External resolution |
| `run_completed` | run_id, outcome, artifact_hashes | All nodes done |
| `run_failed` | run_id, error_type, error_message, failed_nodes | Run cannot progress |

---

## Run lifecycle and node states

```
                    ┌──── cache hit ──── :completed
                    │
:pending ──── dispatch ──── Task ──── success ──── :completed
                    │                     │
                    │                     └── with decisions ──── :completed
                    │                                              + decision_recorded
                    │
                    ├──── Task ──── failure/crash ──── :failed
                    │
                    └──── gate ──── :waiting ──── resolve_gate ──── :completed
```

Run statuses:

| Status | Meaning |
|--------|---------|
| `:success` | All nodes completed |
| `:partial` | Some completed, some failed, none blocked |
| `:failed` | Failures blocked pending nodes |

---

## Two execution paths

The runtime supports two execution modes:

### Supervised (GenServer path)

Used when the OTP application is running. No directory arguments needed — stores use their configured roots.

```elixir
# Via public API
{:ok, result} = Liminara.run(MyPack, input)

# Via Run.Server directly
{:ok, _pid} = Run.Server.start("run-1", plan)
{:ok, result} = Run.Server.await("run-1")
```

Features: concurrent dispatch, event broadcasting, crash recovery, gate support.

### Direct (synchronous path)

Stateless functions with explicit directory arguments. Used in tests or standalone scripts. No OTP application needed.

```elixir
{:ok, result} = Liminara.run(MyPack, input,
  store_root: "/tmp/artifacts",
  runs_root: "/tmp/runs"
)
```

Features: synchronous execution, no broadcasting, no gates.

---

## Crash recovery

### Op crash

An op that raises, exits, or hangs is caught by the Run.Server via `Task.Supervisor.async_nolink`. The Task crashes, Run.Server receives `{:DOWN, ref, ...}`, marks the node as `:failed`, and continues dispatching other ready nodes. The run completes with `:partial` or `:failed` depending on whether the failure blocked other nodes.

### Run.Server crash

When a Run.Server is killed externally, a new server started with the same `run_id` detects existing events in the event log. It rebuilds state:

- Nodes with `op_completed` events → `:completed` (artifacts already in store)
- Nodes with `op_started` but no terminal event → reset to `:pending`
- Nodes with `op_failed` → `:failed`
- `prev_hash` set to the last event's hash (chain continues correctly)
- Already-completed runs detected and reported without re-execution

---

## Event broadcasting

Every event the Run.Server records is broadcast to `:pg` subscribers:

```elixir
# Subscribe
Liminara.Run.subscribe("run-1")

# Receive events
receive do
  {:run_event, "run-1", %{event_type: "op_completed", payload: payload}} ->
    IO.inspect(payload)
end

# Unsubscribe
Liminara.Run.unsubscribe("run-1")
```

Properties:
- Fire-and-forget (non-blocking for the server)
- Subscriber crashes don't affect the server
- Events arrive in the same order they're recorded
- Dead subscribers are automatically removed by `:pg`

This is the mechanism the observation layer (Phase 4) will consume.

---

## Gate mechanism

Ops can return `{:gate, prompt}` to pause execution and wait for external input:

```elixir
def execute(%{"data" => data}) do
  {:gate, %{"prompt" => "Approve this?", "preview" => data}}
end
```

The Run.Server:
1. Emits `gate_requested` event (broadcast to subscribers)
2. Sets node state to `:waiting`
3. Waits for `resolve_gate/3` call

```elixir
Run.Server.resolve_gate("run-1", "gate_node", %{"approved" => true})
```

On resolution: records decision, completes the node, dispatches newly ready nodes.

On replay: the stored gate decision is injected automatically — no waiting.

---

## Cache semantics

Cache key = `SHA-256(op_name, op_version, sorted input hashes)`

Only `:pure` and `:pinned_env` ops are cached. The cache is an ETS named table (`Liminara.Cache`) shared across all runs. This means:

- Second run with same plan → pure ops cache-hit instantly
- Change one input → downstream cache misses, upstream cache hits
- Replay with stored decisions → recordable ops inject, pure ops may cache-hit

---

## Filesystem layout

```
{store_root}/                          Artifact blob store
├── a1/b2/a1b2c3d4...                 Content-addressed blobs
├── fe/dc/fedc9876...                  (Git-style 2-level sharding)
└── ...

{runs_root}/                           Run data
├── {run_id}/
│   ├── events.jsonl                   Hash-chained event log
│   ├── seal.json                      Run seal (final hash + metadata)
│   └── decisions/
│       ├── {node_id}.json             One decision per recordable op
│       └── ...
└── ...
```

---

## Dependencies

### Runtime

| Dependency | Version | Purpose |
|-----------|---------|---------|
| Elixir | ~> 1.18 | Language |
| OTP | 27+ | BEAM runtime |
| Jason | ~> 1.4 | JSON encoding/decoding |

That's it. Three dependencies. Everything else is OTP built-ins: ETS, `:pg`, Registry, GenServer, Task.Supervisor, DynamicSupervisor, `:crypto`.

### Test-only

| Dependency | Version | Purpose |
|-----------|---------|---------|
| StreamData | ~> 1.0 | Property-based testing |

### Dev-only (umbrella level)

| Dependency | Purpose |
|-----------|---------|
| ExDoc | Documentation |
| Credo | Linting |
| Dialyxir | Type analysis |

---

## Test suite structure

22 test files, organized by module:

| Category | Files | Tests |
|----------|-------|-------|
| Core data model | hash, canonical, op, plan, pack | ~40 |
| Storage | artifact store, event store, decision store, cache | ~40 |
| Synchronous execution | run/server, run/replay, run/cached_run | ~30 |
| Integration | integration, golden_fixtures | ~10 |
| OTP application | application, supervised_stores | ~21 |
| GenServer execution | run/genserver | ~25 |
| Broadcasting | run/broadcast | ~15 |
| Crash recovery | run/crash_recovery | ~12 |
| Property-based | property (StreamData) | 8 properties × 100 cases |
| ToyPack | toy_pack | ~6 |

Property tests verify invariants over randomized DAG shapes:
- **Termination**: every plan completes within 5 seconds
- **Event integrity**: valid hash chain for every run
- **Completeness**: every node gets a terminal event
- **Determinism**: same pure plan → identical outputs
- **Isolation**: concurrent runs don't interfere
- **Crash resilience**: random failures → valid termination

---

## What this enables (Phase 4+)

The runtime is ready for:

1. **Observation Layer (Phase 4)**: The `:pg` event stream is the contract. An observation UI (ex_a2ui or LiveView) subscribes to runs and renders the DAG in real-time. No runtime changes needed — just a consumer of the existing broadcast.

2. **Real packs (Phase 5+)**: The Pack behaviour, gate mechanism, binary artifact support, and all four determinism classes are proven. A pack author implements 4 callbacks and gets scheduling, caching, replay, crash recovery, and event broadcasting for free.

3. **Scheduled execution (Phase 6)**: The Run.Server is started via DynamicSupervisor — Oban just becomes another way to trigger `Run.Server.start/3`.

4. **Compliance reporting**: The hash-chained event log and decision records already provide EU AI Act Article 12 tamper-evidence as an architectural consequence.

---

*This document is a point-in-time snapshot after Phase 3. For the evolving architecture, see [01_CORE.md](01_CORE.md). For the build plan, see [02_PLAN.md](02_PLAN.md).*
