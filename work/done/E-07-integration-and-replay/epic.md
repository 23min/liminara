---
id: E-07-integration-and-replay
phase: 2
status: complete
---

# E-07: Integration and Replay

## Goal

Wire everything together into a working runtime. Run a trivial multi-op plan end-to-end: discovery mode (first run, decisions recorded) and replay mode (second run, decisions injected). Verify interoperability with the Python SDK's file format.

This is the "done when" proof for Phase 2: "Can define a trivial plan (3 ops), execute it, produce artifacts, record events, and replay from the event log."

## Scope

**In:**

### Replay (`Liminara.Replay`)
- Load decisions from a previous run's decision store
- On replay: when a `recordable` op is dispatched, inject the stored decision instead of executing
- `Run.Server` accepts a `replay: run_id` option that switches recordable ops to injection mode
- Pure ops re-execute (and should produce identical output due to same inputs)
- Side-effecting ops: skip on replay (log a warning)

### Integration test: end-to-end run
- Define 3 test ops:
  - `TestOps.LoadData` (`:pure`) — returns a hardcoded string artifact
  - `TestOps.Transform` (`:recordable`) — simulates nondeterminism (returns input + random suffix), records decision
  - `TestOps.Save` (`:side_effecting`) — writes output to a file
- Plan: `load → transform → save`
- First run (discovery):
  - All ops execute
  - Events recorded in JSONL with valid hash chain
  - Decision recorded for Transform op
  - Artifacts stored in artifact store
  - Run seal computed
- Second run (replay):
  - LoadData re-executes (pure, same output)
  - Transform injects stored decision (same output as first run)
  - Save is skipped (side-effecting, replay mode)
  - Event log records the replay run separately
  - Output matches first run (for load + transform)

### Integration test: cache behavior
- Run the same plan twice (not replay — two fresh runs with same inputs)
- Pure ops should cache-hit on the second run
- Recordable ops should re-execute (and may produce different decisions)
- Verify cache hit/miss via event log (`cache_hit: true/false` in op_completed payload)

### Interop with Python SDK
- Read golden fixtures (from E-04) with the Elixir storage layer
- Verify: event log parses, hash chain validates, artifacts are retrievable, decision records parse
- Write a run from Elixir, verify the output matches the spec (same format the Python SDK would produce)

### Pack behaviour (`Liminara.Pack`)
- `@callback id() :: atom()`
- `@callback version() :: String.t()`
- `@callback ops() :: [module()]`
- `@callback plan(input :: term()) :: Plan.t()`
- `@callback init() :: :ok` (optional)
- A simple `TestPack` that implements the behaviour with the 3 test ops above

### Public API (`Liminara`)
- `Liminara.run(pack_module, input)` → starts a run, returns `{:ok, run_result}` or `{:error, reason}`
- `Liminara.replay(pack_module, input, replay_run_id)` → replays with stored decisions
- These are the top-level entry points for using the runtime

**Out:**
- Discovery mode (dynamic DAG expansion)
- Gates / human-in-the-loop
- Observation layer
- Real domain packs (Report Compiler is Phase 3)
- Error recovery beyond "fail the run"

## Milestones

| ID | Milestone | Status |
|----|-----------|--------|
| M-IR-01-replay | Replay module: load decisions, inject on dispatch, skip side-effecting | done |
| M-IR-02-pack | Pack behaviour, TestPack with 3 ops, public API (Liminara.run, Liminara.replay) | done |
| M-IR-03-end-to-end | End-to-end integration tests: discovery run, replay run, cache behavior, interop with golden fixtures | done |

## Success criteria

- [x] First run of TestPack: all ops execute, events recorded, hash chain valid, seal computed
- [x] Replay of that run: Transform op injects stored decision, output matches first run
- [x] Cache test: second fresh run with same inputs → pure ops cache-hit
- [x] Golden fixtures from E-04 are readable by Elixir storage layer
- [x] Elixir-written event log is valid canonical JSON matching the spec
- [x] Pack behaviour: TestPack implements all callbacks, `Liminara.run(TestPack, input)` works
- [x] `Liminara.replay(TestPack, input, run_id)` works

## References

- Architecture: `docs/architecture/01_CORE.md` § Replay, § Five concepts (Pack), § The elegance test
- Data model: `docs/analysis/11_Data_Model_Spec.md`
- Golden fixtures: `test_fixtures/` (from E-04)
- Depends on: E-04 (scaffolding + fixtures), E-05 (storage), E-06 (execution)
