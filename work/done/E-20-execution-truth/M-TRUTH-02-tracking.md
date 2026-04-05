# M-TRUTH-02: Core Runtime Contract Migration — Tracking

**Started:** 2026-04-04
**Branch:** `milestone/M-TRUTH-02`
**Spec:** `work/done/E-20-execution-truth/M-TRUTH-02-core-runtime-contract-migration.md`
**Status:** implementation complete

## Acceptance Criteria

- [x] AC1: Runtime can obtain one canonical execution spec per op
  - `execution_spec/0` is preferred when exported
  - one central runtime shim derives `ExecutionSpec` for unmigrated ops
  - derived specs stay bounded to shape adaptation only
  - known semantic mismatches remain explicit legacy bridges, not false canonical truth
  - no new standalone top-level callbacks are introduced
- [x] AC2: Executor paths normalize into `OpResult`
  - inline and task execution normalize legacy tuple results into `Liminara.OpResult`
  - port execution accepts canonical success with `outputs`, `decisions`, and `warnings`
  - warning-bearing success reaches runtime as `OpResult.warnings`
  - decisions remain distinct from warnings
- [x] AC3: Execution context is runtime-owned and persisted explicitly
  - each run creates one canonical `Liminara.ExecutionContext`
  - execution context is threaded only when `requires_execution_context: true`
  - run and replay persistence record execution context explicitly, including `replay_of_run_id`
  - pack-visible runtime identity comes from runtime injection or runtime-managed output plumbing
- [x] AC4: Run, replay, and event paths operate on the canonical contract
  - `Liminara.Run` and `Liminara.Run.Server` execute via spec/result/context helpers
  - recordable replay reuses stored decisions and stored execution context
  - side-effecting replay still skips execution under the determinism contract
  - emitted event payloads remain sufficient for observation and replay
- [x] AC5: Compatibility shims are explicit, test-covered, and removal-tracked
  - every shim has an owning removal trigger, at minimum M-TRUTH-03 where applicable
  - representative legacy inline, legacy port, and explicit `execution_spec/0` ops are covered
  - the tracking doc enumerates temporary shims without treating legacy surfaces as long-term API

## Baseline

- Branch created from `epic/E-20-execution-truth`: `milestone/M-TRUTH-02`
- Focused baseline validation is green:
  - `mix test apps/liminara_core/test/liminara/op_test.exs`
  - `mix test apps/liminara_core/test/liminara/executor/dispatch_test.exs`
  - `mix test apps/liminara_core/test/liminara/executor/port_test.exs`
  - `mix test apps/liminara_core/test/liminara/execution_contract_structs_test.exs`
- Current runtime still depends on legacy callbacks and tuple results in `Liminara.Op`, `Liminara.Executor`, `Liminara.Executor.Port`, `Liminara.Run`, and `Liminara.Run.Server`

## Implementation Phases

1. Freeze bridge expectations with failing tests for execution spec derivation and executor normalization
2. Add central runtime helpers for spec lookup and `OpResult` normalization across inline, task, and port execution
3. Thread runtime-owned `ExecutionContext` through run, replay, and persistence paths
4. Remove scattered legacy assumptions from run/server flows and verify replay/cache behavior still holds

## Temporary Shims To Track

- Legacy callback to `ExecutionSpec` derivation in runtime core
  - Removal trigger: M-TRUTH-03 pack cleanup plus explicit pack migration off legacy callbacks
- Legacy Python success payload acceptance in port executor
  - Removal trigger: M-TRUTH-03 or the first milestone that migrates remaining Python ops to canonical `OpResult` JSON

## Evidence

- `Liminara.Op.execution_spec/1` now resolves one canonical execution spec per op and prefers explicit `execution_spec/0` after ensuring the module is loaded.
- `Liminara.Executor` and `Liminara.Executor.Port` now normalize legacy tuple and Python success shapes into `Liminara.OpResult`, including canonical warning-bearing success.
- `Liminara.Run` and `Liminara.Run.Server` now execute against canonical spec/result helpers, persist `execution_context.json`, emit runtime context in `run_started`, and carry warnings on `op_completed` payloads.
- Warning-bearing inline/task results now tolerate both `Liminara.Warning` structs and plain warning maps when the runtime serializes `op_completed` payloads.
- Execution context injection is now strictly spec-gated: runtime paths only pass context when `requires_execution_context: true`, rather than reflectively treating `execute/2` as a second contract surface.
- Cache lookups and cacheability now follow canonical `execution_spec` identity plus canonical `cache_policy`, so migrated explicit-spec ops can both opt into and opt out of caching without diverging from runtime execution behavior.
- Replay branching now follows canonical `replay_policy` with class fallback only when the policy is absent, so explicit-spec ops can override class-derived replay behavior consistently in both `Run` and `Run.Server`.
- Task and port executor paths now default to canonical `execution.timeout_ms` when present, so explicit execution specs control runtime timeout behavior without requiring ad hoc caller overrides.
- `Run.execute` now owns a private task supervisor for canonical `executor: :task` ops, and `Run.Server` threads its supervisor through nested executor dispatch so runtime-level task execution matches direct executor behavior.
- Synchronous `Run.execute` now handles gate results explicitly by emitting `gate_requested` and failing with a `gate_requires_run_server` runtime error instead of crashing on an unmatched gate tuple.
- Replay now reuses the stored execution context from the source run while stamping `replay_of_run_id`, so context-aware ops see the original runtime identity fields during replay rather than fresh replacements.
- The Python warning bridge now ignores unknown warning keys instead of crashing on schema expansion, and end-to-end tests now cover Python execution-context transport during both discovery and replay.
- Replays now fail explicitly with `missing_replay_execution_context` when a context-aware source run is missing `execution_context.json`, instead of silently fabricating replacement runtime identity.
- `Run.Server` now defers terminal completion until a ready-node dispatch batch finishes, so multi-root replay failures emit one terminal `run_failed` event instead of closing the run mid-dispatch and duplicating terminal events.
- Replay source-context enforcement is now replay-policy aware, so `replay_recorded` and `skip` nodes do not fail merely because the source `execution_context.json` is unavailable when no live re-execution will occur.
- `replay_recorded` context-aware nodes now fail closed when both the source execution context and the stored replay data are unavailable, instead of silently falling back to live execution with synthesized replay context.
- Warning payloads are now persisted alongside replay metadata so recordable discovery and replay emit the same `op_completed.warnings` surface in both `Run` and `Run.Server`.
- Replay runs that fail for missing source context no longer persist a synthesized `execution_context.json`, preventing crash recovery from locking in fabricated runtime identity.
- Missing-source-context suppression is now scoped to plans that actually require execution context, so pure replays still persist and publish replay-owned runtime context while context-aware replays continue to fail explicitly.
- Invalid `execution_context.json` files now surface explicit replay failure instead of crashing the store or run process, including non-object JSON payloads and malformed optional fields, while schema drift with extra keys remains tolerated.
- Crash recovery now falls back to the canonical `run_started.payload.execution_context` when the current run's `execution_context.json` is missing or unreadable, so resumed context-aware nodes keep the original runtime identity.
- Execution-context-aware ops are now treated as uncached until the runtime can incorporate execution context into the cache key, preventing unrelated runs from reusing context-sensitive artifacts during replay and crash recovery.
- `pinned_env` caching is now safety-disabled until environment hashing exists, so the canonical cache contract no longer claims environment-sensitive reuse the runtime cannot yet prove.
- Decision persistence now records canonical spec identity for explicit-spec ops, keeping stored decision provenance aligned with canonical `op_started` events.
- `Run.Server` crash recovery now reloads the persisted execution context before resuming pending work, so resumed nodes see the same runtime-owned metadata already recorded for the run.
- `op_completed` events now include keyed output hashes, and `Run.Server.await/2` rebuilds outputs from those keyed hashes when falling back to the event log after the server exits.
- `Run.Server.await/2` now falls back to the event log when a normally exiting registered process wins the race against result delivery, instead of surfacing `:server_exited` for completed runs.
- Event-log fallback now preserves `:partial` versus `:failed` by deriving terminal status from the rebuilt node-state picture instead of collapsing every `run_failed` terminal event into plain failure.
- Replay for gate-backed recordable nodes now persists gate output hashes, so replay injects stored outputs instead of falling back into a live gate wait.
- `Run.Server.await/2` now reconstructs outputs from event logs when the server has already exited, preserving successful result access for concurrent runs.
- Execution-context deserialization now ignores unknown persisted keys so the runtime can tolerate bounded schema drift in `execution_context.json`.

## Validation

- Focused executor + contract tests are green, including the new regressions for canonical task and port timeout propagation plus the pinned-env cache safety guard.
- Focused run/replay/context tests are green, including the new regressions for recovery-context reuse, keyed output reconstruction, partial-status preservation, spec-gated context injection, execution-context schema drift tolerance, invalid-context replay failure for malformed, non-object, and malformed-optional-field JSON, inline warning-map propagation, canonical decision-record identity, explicit replay-policy override, runtime-level task execution, synchronous gate handling, replay-context reuse, explicit missing-context replay failure, single-terminal-event handling for multi-root replay failures, warning-preserving replay, replay-recorded context-aware fallback, replay-recorded fail-closed behavior when stored replay data is absent, and Python execution-context transport.
- Focused replay-context regressions are green for both direct and GenServer runtimes when the source `execution_context.json` is missing but the replay plan does not require execution context.
- Focused cache and await regressions are green, including canonical-spec cacheability and normal-exit await fallback.
- Broader focused runtime slice is green: `mix test apps/liminara_core/test/liminara/execution_runtime_contract_test.exs apps/liminara_core/test/liminara/run/execution_context_test.exs apps/liminara_core/test/liminara/run/replay_test.exs apps/liminara_core/test/liminara/run/crash_recovery_test.exs apps/liminara_core/test/liminara/run/genserver_test.exs`.
- Full `liminara_core` validation is green on the updated branch: `mix test apps/liminara_core/test` → `8 properties, 383 tests, 0 failures, 1 excluded`.
- Previously flaky full-suite ordering remains green on the branch prior to this fix: `mix test apps/liminara_core/test --seed 1` → `8 properties, 382 tests, 0 failures, 1 excluded`.
- Elixir formatting check passes for all touched Elixir files.
- Python syntax validation passes for `runtime/python/src/liminara_op_runner.py`, `runtime/python/src/ops/test_warning.py`, and `runtime/python/src/ops/test_context.py`.
- Ruff lint and format checks pass for `runtime/python/src/liminara_op_runner.py`, `runtime/python/src/ops/test_warning.py`, and `runtime/python/src/ops/test_context.py`.

## Notes

- This milestone is runtime-first. Radar semantic cleanup remains deferred to M-TRUTH-03.
- Compatibility shims are allowed only as bounded shape adapters under `docs/architecture/contracts/02_SHIM_POLICY.md`.
- Full umbrella validation is still expected to encounter unrelated worktree failures outside this milestone slice; focused runtime validation is the working loop until the contract migration is complete.