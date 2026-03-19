---
id: E-08-otp-runtime
phase: 3
status: done
---

# E-08: OTP Runtime Layer

## Goal

Promote the synchronous walking skeleton into a proper OTP application. The current runtime (`Run.execute/3`) is a synchronous loop with no supervision, no process isolation, and no event broadcasting. This epic builds the foundation that the observation layer (Phase 4) and all real packs depend on: a supervised GenServer-based run engine with concurrent op dispatch, crash recovery, and `:pg`-based event broadcasting.

This is infrastructure, not features. Every design choice in `01_CORE.md` § "How it maps to OTP" gets implemented and stress-tested here.

## Scope

**In:**

### OTP Application and Supervision Tree
- `Liminara.Application` — top-level application with supervision tree
- `Liminara.Run.Registry` — maps run IDs to Run.Server PIDs (via `Registry`)
- `Liminara.Run.DynamicSupervisor` — supervises active Run.Server processes
- Startup: ETS tables created, stores initialized, supervision tree started

### Run.Server GenServer
- `Liminara.Run.Server` — GenServer owning one run's lifecycle
- Async message-based execution: `node_completed`, `node_failed`, `gate_resolved`
- Dispatches ready ops via `Op.TaskSupervisor` (supervised Tasks)
- Fan-out: multiple ready nodes dispatched concurrently
- State derived from events (same as the synchronous version, but as GenServer state)
- Proper shutdown: completes or fails gracefully on termination

### Event Broadcasting
- `:pg` process group per run (`:liminara` group scope)
- Every event the Run.Server records is broadcast to subscribers
- Subscription API: `Liminara.Run.subscribe(run_id)` / `unsubscribe`
- Late-join subscribers receive no backfill (they can read the event log for history)

### Crash Recovery and Supervision
- Op crash → Run.Server handles the failure (marks node failed, continues or fails run)
- Run.Server crash → DynamicSupervisor restarts it; server rebuilds state from event log
- Multiple concurrent runs don't interfere with each other
- Process isolation: one run's crash doesn't affect other runs

### Property-Based Testing
- `StreamData` generators for random DAG shapes (varying width, depth, branching)
- Invariant verification: scheduler always terminates, all events recorded, hash chain valid
- Crash injection: random op failures don't corrupt state
- Concurrent run isolation: multiple simultaneous runs produce independent, valid results

### Toy Pack Integration
- Minimal pack exercising all four determinism classes + gate + binary artifact
- Validates the full async path: plan → GenServer dispatch → Task execution → event broadcast → result
- Cache behavior through the new async runtime
- Replay through the new async runtime

**Out:**
- Observation UI (Phase 4)
- Real domain packs (Radar, House Compiler)
- Discovery mode (dynamic DAG expansion)
- Oban / Postgres
- Error policies beyond "fail the node, continue the run" and "fail the run"
- Hot code loading

## Milestones

| ID | Milestone | Status |
|----|-----------|--------|
| M-OTP-01-supervision | Application module, supervision tree, Run.Registry, DynamicSupervisor, ETS table lifecycle | done |
| M-OTP-02-run-server | Run.Server GenServer: async dispatch, fan-out, op completion/failure handling, state management | done |
| M-OTP-03-broadcast | `:pg` event broadcasting, subscriber API, multi-subscriber delivery | done |
| M-OTP-04-crash-recovery | Op crash handling, Run.Server restart + state rebuild from event log, concurrent run isolation | done |
| M-OTP-05-stress-testing | StreamData property-based tests, random DAG shapes, crash injection, concurrency invariants | done |

## Success criteria

- [x] `Application.start` brings up the full supervision tree; Observer shows the expected process hierarchy
- [x] A 3-op plan runs end-to-end through the GenServer path with concurrent fan-out
- [x] A subscriber receives all events from a run in real-time via `:pg`
- [x] Killing an op Task doesn't crash the Run.Server; the node is marked failed
- [x] Killing a Run.Server and restarting it rebuilds state from the event log and continues (or reports final status)
- [x] 100+ randomized DAG shapes all terminate correctly with valid event logs
- [x] Two concurrent runs with interleaved op completions produce independent, valid results
- [x] Replay works through the async GenServer path (decisions injected, output matches)
- [x] `:sys.get_state/1` on a Run.Server returns inspectable state
- [x] All existing tests continue to pass (the synchronous path may be retained or adapted)

## References

- Architecture: `docs/architecture/01_CORE.md` § "How it maps to OTP", § "The scheduler: ten lines", § "Observation"
- Supervision tree diagram: `01_CORE.md` § "Supervision tree"
- Depends on: E-04 (scaffolding), E-05 (storage), E-06 (execution), E-07 (integration/replay)
- ADRs: none yet
