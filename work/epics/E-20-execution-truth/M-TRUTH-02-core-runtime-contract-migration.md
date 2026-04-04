---
id: M-TRUTH-02-core-runtime-contract-migration
epic: E-20-execution-truth
status: draft
depends_on: M-TRUTH-01-execution-spec-outcome-design
---

# M-TRUTH-02: Core Runtime Contract Migration

## Goal

Move runtime execution, replay, and executor boundaries onto the canonical execution-truth contract defined in M-TRUTH-01, while keeping current packs bootable through explicit, removal-tracked compatibility shims that adapt shape only and do not encode known-bad semantics as canonical truth.

## Context

M-TRUTH-01 froze the canonical contract surface in `liminara_core`:

- `Liminara.ExecutionSpec`
- `Liminara.ExecutionContext`
- `Liminara.OpResult`
- `Liminara.Warning`

The runtime still executes through older conventions:

- `Liminara.Op` requires `name/0`, `version/0`, `determinism/0`, and `execute/1`
- `Liminara.Executor` reflectively reads optional `executor/0`, `python_op/0`, and `env_vars/0`
- `Liminara.Executor.Port` still treats Python success as `outputs` plus optional `decisions`
- `Liminara.Run` and `Liminara.Run.Server` still own run identity ad hoc and emit legacy result/event payloads
- current packs, including Radar, still depend on tuple-shaped op results and pack-visible runtime values such as `run_id`

This milestone is runtime-first on purpose. It migrates the core runtime and compatibility layer to the new contract. It does not yet do the pack-semantic cleanup that belongs to M-TRUTH-03.

## Milestone Boundary

M-TRUTH-02 may implement:

- runtime consumption of `execution_spec/0`
- temporary, explicitly bounded derivation of `ExecutionSpec` from legacy callbacks where bootability requires it
- canonical normalization of inline and port executor results into `OpResult`
- runtime-owned `ExecutionContext` creation, persistence, replay threading, and injection
- explicit containment for known semantic mismatches so legacy bootability does not imply false canonical determinism, runtime identity, or degraded-output semantics
- focused runtime tests that freeze the bridge behavior and replay semantics

M-TRUTH-02 does not implement:

- Radar semantic fixes for false purity, runtime-identity misuse, or degraded-output handling in pack code
- full pack-by-pack migration to explicit `execution_spec/0`
- warning UI or operator surfacing from E-19
- sandbox enforcement or capability execution from E-12
- broad platform abstraction work beyond the runtime contract migration

## Acceptance Criteria

1. **Runtime can obtain one canonical execution spec per op**
   - `execution_spec/0` is the preferred runtime surface when an op exports it
   - unmigrated ops can still execute through one central runtime shim that derives `ExecutionSpec` from legacy callbacks
   - derived specs are bounded to shape adaptation of the current contract surface and are documented as temporary exceptions under `docs/architecture/contracts/02_SHIM_POLICY.md`
   - ops with known semantic mismatches may remain behind an explicit legacy bridge for bounded bootability, but the bridge must not invent false canonical determinism, runtime identity, or warning semantics
   - no new standalone top-level callbacks are introduced beyond the canonical spec path

2. **Executor paths normalize into `OpResult`**
   - inline and task execution normalize legacy tuple results into `Liminara.OpResult`
   - port execution accepts the canonical success shape with `outputs`, `decisions`, and `warnings` while still bridging legacy Python JSON responses during transition
   - warning-bearing success reaches the runtime as `OpResult.warnings`, not as ad hoc side flags
   - decision-bearing success continues to emit decision records without conflating decisions and warnings

3. **Execution context is runtime-owned and persisted explicitly**
   - each run creates one canonical `Liminara.ExecutionContext`
   - execution context is threaded into execution only where the spec declares `requires_execution_context: true`
   - run and replay persistence record execution context explicitly, including `replay_of_run_id` when applicable
   - pack-visible runtime identity comes from runtime context injection or runtime-managed output plumbing, not pack-side synthesis

4. **Run, replay, and event paths operate on the canonical contract**
   - `Liminara.Run` and `Liminara.Run.Server` execute against spec/result/context helpers rather than legacy callback and tuple assumptions scattered across the code path
   - replay of recordable ops continues to use stored decisions and now reuses stored execution context
   - replay of side-effecting ops continues to skip execution according to the determinism contract after the migration
   - event payloads emitted by the runtime remain sufficient for observation and replay after result/context normalization

5. **Compatibility shims are explicit, test-covered, and removal-tracked**
   - every runtime shim introduced in this milestone names an owning removal trigger, at minimum M-TRUTH-03 where the remaining Radar pack cleanup depends on it
   - representative legacy inline ops, representative legacy port ops, and at least one explicit `execution_spec/0` op are covered by focused tests
   - the milestone tracking doc can enumerate the temporary shims without treating the legacy callback surface as first-class long-term API

## Tests

Write tests first for the runtime migration surface.

- `ExecutionSpec` bridge tests for a legacy inline op, a legacy port op, and an op exporting explicit `execution_spec/0`
- `Executor` normalization tests for:
  - `{:ok, outputs}`
  - `{:ok, outputs, decisions}`
  - canonical `OpResult` returns
  - canonical warning-bearing success
- `Executor.Port` protocol tests for both:
  - legacy Python success payloads
  - canonical Python success payloads including warnings
- `Run` / `Run.Server` tests for execution-context creation, persistence, replay reuse, and recordable decision replay
- regression tests proving cache hit, replay skip, and replay inject behavior still work after the contract migration

Use the repository TDD conventions:

- happy path
- edge cases
- error cases
- round-trip and replay cases where applicable
- format-compliance assertions for stored runtime context and event payloads where practical

## TDD Sequence

1. Write focused runtime tests for spec derivation, result normalization, and execution-context persistence. All new tests must fail first.
2. Implement the minimum runtime bridge needed to make the new tests pass.
3. Refactor only after the canonical contract is exercised through both inline and port execution paths.
4. Re-run focused runtime tests, then the relevant broader runtime suite for replay and execution coverage.

## Technical Notes

- Expected core touch points:
  - `runtime/apps/liminara_core/lib/liminara/op.ex`
  - `runtime/apps/liminara_core/lib/liminara/executor.ex`
  - `runtime/apps/liminara_core/lib/liminara/executor/port.ex`
  - `runtime/apps/liminara_core/lib/liminara/run.ex`
  - `runtime/apps/liminara_core/lib/liminara/run/server.ex`
  - `runtime/apps/liminara_core/lib/liminara/event/store.ex`
- The spec bridge should live in runtime/core, not be reimplemented per pack.
- Known semantic mismatches in Radar are not to be hidden behind permanent shims in this milestone. Where a bridge is unavoidable for bootability, it must carry a named removal trigger and remain explicitly legacy rather than being translated into false canonical values.
- The migration should leave E-19 and E-12 consuming the same contract surface rather than inventing local runtime adapters.

## Out of Scope

- Reclassifying Radar ops whose determinism semantics are still wrong in production terms
- Refactoring Radar pack modules to stop depending on legacy runtime-shaped inputs
- Warning presentation in LiveView or A2UI
- Capability enforcement, audit hooks, Landlock, or executor sandbox policy
- Dynamic DAG, scheduler, or storage generalization work outside the execution-truth contract

## Dependencies

- M-TRUTH-01 is complete and merged
- `docs/architecture/08_EXECUTION_TRUTH_PLAN.md`
- `docs/architecture/contracts/00_TRUTH_MODEL.md`
- `docs/architecture/contracts/02_SHIM_POLICY.md`
- Decision D-2026-04-02-015
- Decision D-2026-04-04-022

## Spec Reference

- `docs/architecture/08_EXECUTION_TRUTH_PLAN.md`
- `work/epics/E-20-execution-truth/epic.md`

## Related ADRs

- D-2026-04-02-015: unified execution spec replaces callback sprawl
- D-2026-04-04-022: architecture truth is split into live, decided-next, and historical sources