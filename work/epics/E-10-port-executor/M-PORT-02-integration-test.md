---
id: M-PORT-02-integration-test
epic: E-10-port-executor
status: not started
depends_on: M-PORT-01-protocol-executor-runner
---

# M-PORT-02: Integration Test

## Goal

Prove that Python ops work correctly through the full Run.Server execution pipeline — including all four determinism classes, artifact storage, event logging, and cache/replay behaviour. After this milestone, we have confidence that any Pack can include Python ops and they'll behave identically to Elixir ops from the runtime's perspective.

## Context

M-PORT-01 delivered `Executor.Port` and the Python runner. This milestone wires it into Run.Server and verifies the full lifecycle: plan → dispatch → port execution → artifact storage → event logging → cache hit (pure) → replay (recordable) → skip (side_effecting).

Relevant existing code:
- `Liminara.Run.Server` — `runtime/apps/liminara_core/lib/liminara/run/server.ex`
- `Liminara.Executor` — `runtime/apps/liminara_core/lib/liminara/executor.ex`
- `Liminara.Cache` — `runtime/apps/liminara_core/lib/liminara/cache.ex`
- `Liminara.Op` behaviour — `runtime/apps/liminara_core/lib/liminara/op.ex`

## Acceptance Criteria

1. A `:pure` Python op, when executed via Run.Server:
   - First run: spawns Python, executes, stores output artifacts, logs events
   - Second run with same inputs: returns cached result without spawning Python

2. A `:recordable` Python op, when executed via Run.Server:
   - First run: spawns Python, receives outputs + decisions, stores both
   - Replay run: injects stored decisions, does NOT spawn Python, produces same outputs

3. A `:side_effecting` Python op, when executed via Run.Server:
   - First run: spawns Python, executes, stores output artifacts
   - Replay run: skipped entirely (not executed, not cached)

4. A `:pinned_env` Python op behaves like `:pure` (cached on matching inputs + op version)

5. A multi-node plan mixing Elixir and Python ops executes correctly:
   - Elixir op A (pure, inline) → Python op B (recordable, port) → Elixir op C (pure, inline)
   - Data flows correctly via artifact references between nodes
   - All events are logged in correct order

6. Run.Server dispatches to `:port` executor based on the op module's declared executor type

7. A Python op failure (crash or error response) results in:
   - Node marked as `:failed` in Run.Server state
   - Error event logged
   - Downstream nodes not dispatched
   - Run completes with `:partial` or `:failed` status

## Tests

### Determinism class tests

Each test creates a minimal plan with a single Python op, runs it via Run.Server, and verifies behaviour:

- **Pure op — cache hit:** Run once → op executes (Python spawned). Run again with same inputs → cached (no Python spawn). Verify by checking execution events: first run has `op_started`/`op_completed`, second run has cache-hit event only.
- **Pure op — cache miss on version change:** Run once → cached. Change op version → cache miss → Python spawned again.
- **Recordable op — replay:** Run once → decisions recorded. Replay → decisions injected, Python NOT spawned. Verify outputs match.
- **Side_effecting op — skip on replay:** Run once → executes. Replay → node skipped. Verify no `op_started` event for this node in replay.
- **Pinned_env op — cached like pure:** Run once → cached. Run again → cache hit.

### Mixed plan test

- Plan: `elixir_uppercase` (pure, inline) → `python_reverse` (recordable, port) → `elixir_count` (pure, inline)
- First node uppercases a string, passes as artifact to second node
- Second node reverses it (Python), records a trivial decision, passes to third
- Third node counts characters
- Verify: all three nodes complete, artifacts chain correctly, decision is stored
- Replay: Python node uses stored decision, Elixir nodes use cache

### Failure test

- Plan with a Python op that returns an error → node fails → downstream not dispatched → run status is `:failed` or `:partial`
- Plan with a Python op that crashes (exit code 1) → same failure handling

### Event log test

- Run a plan with a Python op. Read the event log. Verify events are complete and ordered: `run_started`, `op_started`, `op_completed` (with duration, outputs), `run_completed`.

## Technical Notes

### Test Python ops

Create minimal test ops in `runtime/python/src/ops/`:
- `test_pure.py` — returns deterministic output from input (e.g., reverse a string). Determinism: `:pure`.
- `test_recordable.py` — returns output + a trivial decision (e.g., "chose X because Y"). Determinism: `:recordable`.
- `test_side_effecting.py` — writes to a temp file (to prove it ran). Determinism: `:side_effecting`.
- `test_fail.py` — raises an exception.
- `test_crash.py` — calls `sys.exit(1)`.

### Test Elixir op modules

Each test Python op needs a corresponding Elixir op module that declares `executor: :port` and points to the Python script. These are test-only modules in the test support directory.

### Run.Server integration

Run.Server currently calls `Executor.run(op_module, inputs, executor: :inline_or_task, ...)`. The change from M-PORT-01 added `:port` to the dispatch. This milestone verifies that dispatch works within the full Run.Server lifecycle (not just Executor in isolation).

## Out of Scope

- Performance benchmarking (spawn overhead measurement)
- Concurrent Python ops (multiple ports simultaneously) — works via Task.Supervisor already, but not explicitly stress-tested here
- Domain-specific ops
- Long-running worker pool

## Dependencies

- M-PORT-01 (Executor.Port + Python runner must exist)
