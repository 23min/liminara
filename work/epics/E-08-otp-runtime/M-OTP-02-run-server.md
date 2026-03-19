---
id: M-OTP-02-run-server
epic: E-08-otp-runtime
status: done
---

# M-OTP-02: Run.Server GenServer

## Goal

Implement `Liminara.Run.Server` as a GenServer that owns one run's lifecycle. It replaces the synchronous `Run.execute/3` loop with an asynchronous, message-driven execution engine. Ops are dispatched as supervised Tasks under an `Op.TaskSupervisor`. Multiple ready nodes are dispatched concurrently (fan-out).

## Acceptance criteria

- [ ] `Liminara.Run.Server` is a GenServer started under `Run.DynamicSupervisor`
- [ ] Starting a Run.Server: `DynamicSupervisor.start_child(Run.DynamicSupervisor, {Run.Server, opts})`
- [ ] `opts` include: `run_id`, `pack`, `input`, `store_root`, and optional `replay: run_id`
- [ ] The Run.Server registers itself in `Run.Registry` by `run_id`
- [ ] On init: creates the plan via `pack.plan(input)`, emits `run_started` event, dispatches initial ready nodes
- [ ] Op dispatch: each op runs as a `Task` under a per-run `Task.Supervisor` (named `{:via, Registry, {Run.Registry, {run_id, :task_sup}}}` or similar)
- [ ] The per-run `Task.Supervisor` is started as part of the Run.Server's init (or as a child alongside it)
- [ ] On `{:node_completed, node_id, outputs}`: record event, store artifacts, update node state, dispatch newly ready nodes
- [ ] On `{:node_failed, node_id, error}`: record event, mark node failed, check if run should fail
- [ ] Fan-out: if multiple nodes become ready after a completion, all are dispatched concurrently
- [ ] Fan-in: a node with multiple input refs waits until all are resolved before becoming ready
- [ ] Run completion: when all nodes are complete, emit `run_completed`, compute seal, stop the server (normal exit)
- [ ] Run failure: when a node fails and no more progress is possible, emit `run_failed`, stop the server
- [ ] `:sys.get_state/1` returns the Run.Server's internal state (useful for debugging)
- [ ] Caller can await result: `Run.Server.await(run_id, timeout)` returns `{:ok, result}` or `{:error, reason}`
- [ ] Replay mode: when `replay: run_id` is set, recordable ops inject stored decisions instead of executing
- [ ] Cache integration: pure/pinned_env ops check cache before dispatching a Task

### Public API update
- [ ] `Liminara.run(pack, input, opts)` now starts a Run.Server and awaits its result
- [ ] `Liminara.replay(pack, input, replay_run_id, opts)` starts a Run.Server in replay mode
- [ ] Return type is the same `Run.Result` struct as before

## Tests

### GenServer lifecycle
- Starting a Run.Server registers it in the Registry
- Run.Server is findable via `Registry.lookup(Run.Registry, run_id)`
- Completed run: server exits normally after `run_completed` event
- Failed run: server exits normally after `run_failed` event (not a crash)

### Execution flow
- Single-op plan: op dispatched, completed, run completes
- Linear 3-op plan: ops execute in sequence (each waits for its input)
- Fan-out plan (A → B, A → C): B and C are dispatched concurrently after A completes
- Fan-in plan (A → C, B → C): C dispatched only after both A and B complete
- Diamond plan (A → B, A → C, B → D, C → D): correct execution order, D waits for both B and C

### Event recording
- All events are written to the event store with valid hash chain
- Event types emitted: `run_started`, `node_started`, `node_completed`, `run_completed`
- Failed node emits `node_failed` event
- Run seal is computed on completion

### Artifacts and cache
- Output artifacts are stored in the artifact store
- Pure op results are cached (second run with same inputs → cache hit)
- Recordable ops are not cached

### Replay
- Replay injects stored decisions for recordable ops
- Side-effecting ops are skipped on replay
- Replay produces matching output for pure + recordable ops

### Await API
- `Run.Server.await/2` returns result after run completes
- `Run.Server.await/2` returns error after run fails
- `Run.Server.await/2` times out if run doesn't complete

### Introspection
- `:sys.get_state(pid)` returns state with plan, node statuses, and run_id

## TDD sequence

1. **Test agent** reads this spec, writes tests per the Tests section. All tests must fail (red).
2. Human reviews tests.
3. **Impl agent** reads this spec + tests, writes implementation until all tests pass (green).
4. Human reviews implementation.
5. Refactor if needed. Tests must still pass.

## Design notes

### Message protocol

The Run.Server receives messages from op Tasks:

```elixir
# Task sends on completion:
send(run_server, {:node_completed, node_id, output_hashes, duration_ms})
send(run_server, {:node_completed, node_id, output_hashes, duration_ms, decisions})

# Task sends on failure:
send(run_server, {:node_failed, node_id, reason})
```

The Run.Server's `handle_info` pattern matches these messages and follows the same record → update → dispatch cycle as the synchronous version.

### State struct

```elixir
%{
  run_id: String.t(),
  pack: module(),
  plan: Plan.t(),
  node_states: %{node_id => :pending | :running | :completed | :failed},
  node_outputs: %{node_id => [hash]},
  decisions: %{node_id => Decision.t()},
  replay_decisions: %{node_id => Decision.t()} | nil,
  event_count: non_neg_integer(),
  prev_hash: String.t(),
  awaiting: [pid()],  # processes waiting for the result
  store_root: String.t()
}
```

### Relationship to existing Run module

The existing `Liminara.Run` module with its synchronous `execute/3` can be retained as an internal implementation detail or gradually replaced. The public API (`Liminara.run/3`, `Liminara.replay/4`) should route through the GenServer path.

## Out of scope

- Event broadcasting to external subscribers (M-OTP-03)
- Crash recovery / state rebuild (M-OTP-04)
- Gate handling (M-OTP-05 toy pack)
- Property-based testing (M-OTP-05)

## Spec reference

- `docs/architecture/01_CORE.md` § "The Run.Server"
- `docs/architecture/01_CORE.md` § "The scheduler: ten lines"
