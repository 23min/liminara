---
id: M-OTP-04-crash-recovery
epic: E-08-otp-runtime
status: draft
---

# M-OTP-04: Crash Recovery and Run Isolation

## Goal

Verify and harden the OTP layer's crash handling. An op crash should not crash the Run.Server. A Run.Server crash should be recoverable from the event log. Multiple concurrent runs must be fully isolated. This milestone is about proving the "let it crash" philosophy works correctly for Liminara.

## Acceptance criteria

### Op crash handling
- [ ] An op that raises an exception: the Task crashes, Run.Server receives the failure, marks the node as failed
- [ ] An op that times out: the Task is killed, Run.Server marks the node as failed (use `Task.Supervisor.async_nolink` with timeout or monitor-based detection)
- [ ] After an op failure: Run.Server checks for other ready nodes and continues if possible
- [ ] A run where all paths through the DAG hit a failure emits `run_failed`
- [ ] A run where a non-critical branch fails but other branches succeed: the run completes with partial results (failed nodes recorded)

### Run.Server crash recovery
- [ ] When a Run.Server crashes (e.g., killed externally), the DynamicSupervisor restarts it
- [ ] On restart, the Run.Server rebuilds its state by replaying the event log from the Event.Store
- [ ] After rebuild: nodes that were completed stay completed (outputs already in artifact store)
- [ ] After rebuild: nodes that were in-progress are reset to pending and re-dispatched
- [ ] After rebuild: the event log continues with correct hash chain (prev_hash links to last recorded event)
- [ ] A Run.Server that was already completed does not re-execute (detects `run_completed` in event log)

### Concurrent run isolation
- [ ] Two runs started simultaneously execute independently
- [ ] One run crashing does not affect the other
- [ ] Each run has its own event log, artifact outputs, and decision records
- [ ] Run.Registry correctly tracks both runs
- [ ] ETS cache is shared but keyed by op+inputs (no run-level collision)

### Process inspection
- [ ] `:sys.get_state/1` works on any Run.Server
- [ ] `:sys.trace/2` enables message tracing for debugging (manual verification, not automated test)
- [ ] `Process.info(pid)` shows expected links/monitors (to TaskSupervisor, to supervised Tasks)

## Tests

### Op crash handling
- Op that raises `RuntimeError` → node marked failed, run continues with other branches
- Op that exits with `:kill` → node marked failed
- Op that runs forever (simulated) → timeout mechanism kicks in, node marked failed
- Linear plan where middle op fails → downstream nodes never execute, run fails
- Fan-out plan where one branch fails → other branch completes, run completes with partial results

### State rebuild from event log
- Run a plan to completion, crash the server (simulated), restart → server detects completion, reports result
- Run a plan, complete 2 of 3 ops, crash the server, restart → server rebuilds state, dispatches remaining op, completes
- Verify rebuilt state: correct node_states, correct prev_hash for next event
- Verify no duplicate events: restarted server doesn't re-emit events that are already in the log
- Verify artifacts: already-stored artifacts are not re-stored

### Concurrent runs
- Start two runs with different plans simultaneously → both complete correctly
- Start two runs, crash one → the other is unaffected
- Start two runs with same plan and inputs → each produces its own event log
- Registry contains both run IDs during execution, removes them on completion

### Inspection
- `:sys.get_state/1` returns the current state of a running Run.Server
- State includes: run_id, node_states, event_count

## TDD sequence

1. **Test agent** reads this spec, writes tests per the Tests section. All tests must fail (red).
2. Human reviews tests.
3. **Impl agent** reads this spec + tests, writes implementation until all tests pass (green).
4. Human reviews implementation.
5. Refactor if needed. Tests must still pass.

## Design notes

### Op crash detection

Use `Task.Supervisor.async_nolink/2` so the Task is not linked to the Run.Server. The Run.Server monitors the Task. When the Task crashes:

```elixir
# Run.Server receives:
{:DOWN, ref, :process, pid, reason}
```

Map `ref` back to `node_id` and handle as `{:node_failed, node_id, reason}`.

### State rebuild

On init, before dispatching any nodes, check if the event log already has events for this run_id:

```elixir
def init(opts) do
  run_id = opts[:run_id]
  case Event.Store.read(run_id) do
    {:ok, events} when events != [] ->
      state = rebuild_state_from_events(events)
      maybe_continue_or_report(state)
    _ ->
      state = fresh_run(opts)
      dispatch_ready(state)
  end
end
```

### Partial success

A run can complete with some nodes failed. The `Run.Result` should include:
- `status: :completed | :partial | :failed`
- `failed_nodes: [node_id]`
- `outputs: %{node_id => hashes}` (only for completed nodes)

This is a design decision — an alternative is "any failure = run failure." The partial approach is more useful for real workloads (a fan-out where one branch is optional).

## Out of scope

- Retry policies (retry N times before marking failed) — add later as configuration
- Graceful shutdown with in-progress op draining
- Multi-node (distributed Erlang) recovery

## Spec reference

- `docs/architecture/01_CORE.md` § "What Elixir is genuinely good at here"
- `docs/architecture/01_CORE.md` § "How it maps to OTP" — supervision tree and Run.Server
