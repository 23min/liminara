# M-WARN-04: Post-Review Bugfixes — Tracking

**Started:** 2026-04-20
**Branch:** `epic/E-19-warnings-degraded-outcomes` (continuing epic branch per E-19 pattern; milestones M-WARN-01/02/03 were all committed directly here without a separate milestone branch)
**Spec:** `work/epics/E-19-warnings-degraded-outcomes/M-WARN-04-postreview-bugfixes.md`
**Status:** in-progress
**Source of bugs:** ultrareview task `r2fg1c81b` (2026-04-20)

## Summary

Closes four ultrareview findings against commits `d39cb3e` (M-WARN-01 + M-WARN-02) and `629b902` (M-WARN-03) that each invalidate a reachable path through the E-19 warning/degraded-outcome contract. After this milestone, every layer (runtime, observation, LiveView, CLI, Radar briefing) agrees on live, replay, crash-recovery, and `:partial` paths.

## Locked design decisions (approved before implementation)

- **Bug 005**: wire-shape fix. `Run.Server.warning_payload/1` emits string-keyed maps. No boundary normalisation. (Approved 2026-04-20.)
- **Bug merged_001**: new `"run_partial"` terminal event type. Event type is a 1:1 mirror of `Run.Result.status`. No payload-field discriminator. (Approved 2026-04-20.)
- **Fixture migration**: any fixture or test helper that becomes non-compliant with the new spec is updated to match the spec. No backward-compat fallback clauses in production code. (Reinforced by the user 2026-04-20 — consistent with the same rule applied in M-WARN-01 / M-WARN-02 / M-WARN-03.)

## Acceptance Criteria

- [x] **AC1: Live warning payloads cross the runtime → observation boundary without crashing** (Phase 1 — 2026-04-20)
  - `Run.Server.warning_payload/1` emits string-keyed maps; mirror helpers in `Liminara.Run.warning_payload/1` (synchronous runtime) updated identically
  - Integration test `apps/liminara_observation/test/liminara/observation/live_warning_integration_test.exs` routes a real `%Warning{}` through `Run.Server.emit_event → :pg → Observation.Server → ViewModel.apply_event`; per-node `warnings` populated, `degraded: true`, no crash
  - Existing replay tests continue to pass; replay-parity test within the new file asserts live and replay projections produce identical per-node warning shape
  - RED verified by reverting `server.ex` warning_payload to pre-fix atom-keyed form: 5/7 integration-test cases fail with `ArgumentError warning entry missing required field "code"` at `view_model.ex:205` — the documented bug_005 signature
- [ ] **AC2: `:partial`-with-warnings is correctly marked degraded across every consumer**
  - New `"run_partial"` event type emitted by `Run.Server.finish_run/2` and any other terminal emission site
  - `Observation.ViewModel`, `RunsLive.Show` (both `apply_event_type/4` and `derive_degraded_from_events/1`), `RunsLive.Index` (`derive_degraded/2` + `event_type_to_status/1`), `Run.Server.result_from_event_log/1` / `terminal_status/2` / `rebuild_from_events/2` all grow a `run_partial` clause
  - CLI and every web surface agree on the same run
  - End-to-end test: 2-node plan (warning-emitter + downstream failure) asserts `:partial` terminal, `degraded: true` on `Run.Result`, ViewModel, runs-index row, run-detail view
  - `Run.Result.derive_degraded/2` still keeps `:failed → false`; fix is only for `:partial`
  - `seal` file write preserved for `:partial` runs
- [ ] **AC3: `RunsLive.Index` assigns `warning_count` from the terminal payload, never accumulates**
  - `update_existing_run/3` uses direct assignment mirroring `build_run_summary/3`
  - Two delivery paths covered by tests: mount-time race and Run.Server rebuild re-broadcast — both leave `warning_count == N`, not `2N`
- [ ] **AC4: Event-log fallback path preserves per-node degraded state**
  - `RunsLive.Show.build_nodes/1` reads `event["payload"]["warnings"]` on `op_completed`; sets `:warnings` and `:degraded` to match `observation_state_to_view_model/1`'s shape
  - Targeted fallback-path test renders DAG with `degraded: true` on warning-emitting nodes and inspector Warnings section
- [ ] **AC5: Cross-layer consistency tests**
  - New test module exercises all four fixed paths in one place (live broadcast, `:partial`-with-warnings, terminal replay, event-log fallback)
- [ ] **AC6: Validation pipeline stays at baseline**
  - Per-app suites green (liminara_radar, liminara_observation, liminara_web, liminara_core)
  - `uvx ruff check .` / `uvx ruff format --check .` pass
  - `mix format --check-formatted`, `mix credo --strict`, `mix dialyzer` unchanged from M-WARN-03 baseline

## Implementation Phases

| Phase | Bug | Description | Tests |
|-------|-----|-------------|-------|
| 1 | bug_005 | Wire-shape fix: string-keyed warning payload emission | Integration test through `:pg` broadcast; existing replay tests still green |
| 2 | merged_bug_001 | New `run_partial` event type, six consumer updates | End-to-end 2-node partial-with-warnings test; per-consumer projection tests |
| 3 | bug_004 | Direct-assign `warning_count` in `RunsLive.Index.update_existing_run/3` | Mount-race + rebuild-rebroadcast idempotence tests |
| 4 | bug_009 | Read warnings in event-log fallback `build_nodes/1` | Forced-fallback test asserting per-node pill + inspector |
| 5 | cross-layer | Consolidated test module | All four paths in one file |

## Test Summary

### Phase 1 (bug_005)

- **New file**: `apps/liminara_observation/test/liminara/observation/live_warning_integration_test.exs` — 7 tests, 0 failures
- **Per-app suite runs** (post-fix, foreground, per-app):
  - `liminara_observation`: 279 tests / 0 failures
  - `liminara_core/test/liminara/run`: 161 tests / 0 failures
  - `liminara_core` execution contracts (structs + runtime): 55 tests / 0 failures
- **Fixture migration**: none required. Audit for atom-keyed `warning_payload`-shaped test fixtures found zero. Both `warning_map/1` helpers (in `view_model_test.exs` and `warnings_test.exs`) are already string-keyed; per-event literal `"warnings" => [...]` sites in tests are either empty lists or deliberately malformed inputs that exercise contract enforcement.

## Coverage notes

### Phase 1: `warning_payload/1` family (bug_005)

`Run.Server` and `Run` now expose private helpers `warning_payload/1` (two heads: struct / plain map), `stringify_warning_map/1`, and `stringify_warning_value/1` (two heads: atom-convert / fallthrough).

| Branch | Covered by |
|--------|------------|
| `warning_payload(%_{} = warning)` (struct head) | `%Warning{}` single / multi / optional-fields tests |
| `warning_payload(warning) when is_map(warning)` (plain-map head) | `WithWarningMap` test op: raw `%{"code" => …}` result |
| `stringify_warning_map/1` | every test (single sink) |
| `stringify_warning_value/1` atom-convert head | severity atoms `:low`, `:medium`, `:degraded` → `"low"`, `"medium"`, `"degraded"` |
| `stringify_warning_value/1` fallthrough — `nil` | optional-fields test asserts `cause`/`remediation` = `nil` |
| `stringify_warning_value/1` fallthrough — binary | every test (code + summary) |
| `stringify_warning_value/1` fallthrough — list | optional-fields test asserts `affected_outputs == []` |
| `stringify_warning_value/1` `not is_boolean(v)` guard skip | **Defensive, unreachable via current contract.** No `%Warning{}` field is a boolean, and no op under test emits a warning map with a boolean value. The guard exists so a future op returning an arbitrary boolean-carrying map doesn't lose that value to `Atom.to_string(true) == "true"`. |

## Validation Pipeline

*To be filled at wrap time.*

## Notes

*To be filled as decisions and pitfalls surface during TDD.*

## References

- Spec: `work/epics/E-19-warnings-degraded-outcomes/M-WARN-04-postreview-bugfixes.md`
- Ultrareview: task `r2fg1c81b`, findings `bug_005`, `merged_bug_001`, `bug_004`, `bug_009`
- Epic: `work/epics/E-19-warnings-degraded-outcomes/epic.md`
- Upstream milestones: `M-WARN-01-tracking.md`, `M-WARN-02-tracking.md`, `M-WARN-03-tracking.md`
