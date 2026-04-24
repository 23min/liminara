---
id: M-EE-03-run-server
epic: E-06-execution-engine
status: complete
---

# M-EE-03: Run.Server + Supervision Tree

## Goal

Implement `Liminara.Run.Server` — the GenServer that drives the scheduler loop for a single run. It takes a plan and executes it by finding ready nodes, dispatching ops, collecting results, recording events, and storing artifacts. Also set up the minimal OTP supervision tree.

## Acceptance criteria

### Module: `Liminara.Run.Server` (GenServer)

- [x] `start_link(opts)` — starts a Run.Server for a given plan, pack_id, pack_version
- [x] Emits `run_started` event on init
- [x] Finds ready nodes and dispatches them via `Liminara.Executor`
- [x] On op completion: stores output artifacts, emits `op_completed` event, dispatches newly ready nodes
- [x] On op failure: emits `op_failed` event, emits `run_failed` event, stops
- [x] When all nodes complete: emits `run_completed` event, writes seal, stops
- [x] Maintains hash chain: each event's `prev_hash` links to the previous event's `event_hash`

### Event recording

- [x] Uses `Liminara.Event.Store.append/5` for all events
- [x] Events emitted: `run_started`, `op_started`, `op_completed`, `op_failed`, `run_completed`, `run_failed`
- [x] `op_started` payload: `node_id`, `op_id`, `op_version`, `determinism`, `input_hashes`
- [x] `op_completed` payload: `node_id`, `output_hashes`, `cache_hit`, `duration_ms`
- [x] `run_completed` payload: `run_id`, `outcome: "success"`, `artifact_hashes`

### Artifact handling

- [x] Op outputs are stored via `Liminara.Artifact.Store.put/2`
- [x] Output artifact hashes are recorded in the `op_completed` event
- [x] Input artifacts are loaded from the store when dispatching (for `:ref` inputs)
- [x] Literal inputs are passed directly (not stored as artifacts)

### Decision recording

- [x] For `:recordable` ops that return decisions, decisions are stored via `Liminara.Decision.Store.put/3`
- [x] `decision_recorded` event is emitted with the decision hash

### Scheduler patterns

- [x] Linear plan (A → B → C): executes sequentially
- [x] Fan-out plan (A → B, A → C): B and C dispatched concurrently after A
- [x] Fan-in plan (A → C, B → C): C dispatched only after both A and B complete

### Supervision tree

- [x] `Liminara.Supervisor` — top-level supervisor
- [x] `Liminara.Run.DynamicSupervisor` — starts Run.Server instances dynamically
- [x] `Liminara.Run.start(plan, opts)` — convenience function to start a run and wait for result

### Run lifecycle API

- [x] `Liminara.Run.start(plan, opts)` → `{:ok, run_id}` — starts a run
- [x] `Liminara.Run.await(run_id, timeout)` → `{:ok, result}` or `{:error, reason}` — waits for completion
- [x] Result includes: `run_id`, `artifact_hashes`, `event_count`

## Tests

### `test/liminara/run/server_test.exs`

**Linear plan:**
- 3-node linear plan (A → B → C) runs to completion
- All events emitted in correct order: run_started, op_started, op_completed × 3, run_completed
- Hash chain is valid (verify the event log)
- Output artifacts are stored and retrievable
- Seal is written and matches final event hash

**Fan-out:**
- Plan: A → B, A → C — both B and C complete
- All expected events emitted

**Fan-in:**
- Plan: A → C, B → C — C only runs after both A and B

**Failure handling:**
- Plan with a failing op: run emits op_failed, run_failed
- Non-failing ops that already completed still have their artifacts stored

**Recordable ops:**
- Recordable op stores a decision record
- `decision_recorded` event is emitted

**Event integrity:**
- Event log has valid hash chain after run completes
- Seal matches final event hash

## TDD sequence

1. **Test agent** reads this spec + M-EE-01 + M-EE-02, writes `run/server_test.exs`. All tests fail (red).
2. Human reviews tests.
3. **Impl agent** reads this spec + tests, implements `Liminara.Run.Server`, supervision tree, and `Liminara.Run` convenience API until all tests pass (green).
4. Human reviews implementation.
5. Validation pipeline.

## Out of scope

- Discovery mode (plan is fixed at run start)
- Gates / human-in-the-loop
- Retry on failure
- Run cancellation
- Concurrent runs (tested with one run at a time)
- Observation / pub-sub

## Spec reference

- `docs/architecture/01_CORE.md` § The scheduler, § How it maps to OTP
- `docs/analysis/11_Data_Model_Spec.md` § Event types
