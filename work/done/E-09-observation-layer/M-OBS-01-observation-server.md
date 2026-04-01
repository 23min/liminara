---
id: M-OBS-01-observation-server
epic: E-09-observation-layer
status: done
---

# M-OBS-01: Observation Server

## Goal

Build the renderer-agnostic observation foundation. The Observation.Server is a GenServer that subscribes to a run's `:pg` event stream and maintains a "view model" — a structured projection of the run's current state optimized for UI consumption. Any renderer (LiveView, A2UI, CLI) subscribes to the Observation.Server for updates, not directly to the run.

This is the contract that all observation UIs depend on.

## Acceptance criteria

- [x] `Observation.Server` GenServer starts for a given run_id, subscribes to its `:pg` events
- [x] Maintains a view model containing: DAG structure (nodes + edges), node states (pending/running/completed/failed/waiting), node timing (start/end/duration), artifact references per node, decision references per node, run status, run timing
- [x] View model updates on every event received from `:pg`
- [x] Provides `get_state/1` API returning the full view model snapshot
- [x] Provides `get_node/2` API returning detailed info for a single node
- [x] Publishes updates via Phoenix.PubSub on a topic per run (for LiveView consumption)
- [x] Multiple Observation.Servers can observe the same run concurrently
- [x] Observation.Server crash does not affect the Run.Server
- [x] Observation.Server can attach to an already-running run (catches up from event log, then receives live events)
- [x] Observation.Server can observe an already-completed run (loads from event log)

## Tests

### Unit tests — view model projection
- Event sequence → view model state: verify that each event type correctly updates the view model
- `run_started` → initializes DAG structure, sets all nodes to `:pending`
- `op_started` → marks node as `:running`, records start time
- `op_completed` → marks node as `:completed`, records end time + duration, stores output artifact refs
- `op_failed` → marks node as `:failed`, records error info
- `gate_requested` → marks node as `:waiting`, stores prompt
- `gate_resolved` → marks node as `:completed`, stores response
- `decision_recorded` → stores decision reference on node
- `run_completed` → marks run as completed, records final timing

### Integration tests — `:pg` subscription
- Start a Run.Server with a plan, start an Observation.Server for the same run. Verify Observation.Server receives all events and view model matches expected final state.
- Start Observation.Server AFTER run has already started (mid-run join). Verify it catches up from event log and then receives subsequent live events.
- Start Observation.Server for a completed run. Verify it loads the full state from events.

### PubSub tests
- Subscribe a test process to the Observation.Server's PubSub topic. Verify it receives view model updates as events arrive.

### Isolation tests
- Kill Observation.Server while Run.Server is active. Verify Run.Server is unaffected.
- Start two Observation.Servers for the same run. Verify both receive events and maintain consistent state.

## TDD sequence

1. **Test agent** reads this spec, writes tests per the Tests section. All tests must fail (red).
2. Human reviews tests.
3. **Impl agent** reads this spec + tests, writes implementation until all tests pass (green).
4. Human reviews implementation.
5. Refactor if needed. Tests must still pass.

## Out of scope

- Any rendering or UI (that's M-OBS-02+)
- Phoenix app scaffolding
- A2UI integration
- Observation.Server supervision tree (use simple start_link for now; supervise in M-OBS-02)
- Historical run comparison or diffing

## Spec reference

- `docs/architecture/01_CORE.md §Observation: the Excel quality`
- `docs/architecture/03_PHASE3_REFERENCE.md §Event broadcasting`

## Related ADRs

- none yet
