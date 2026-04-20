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
- [x] **AC2: `:partial`-with-warnings is correctly marked degraded across every consumer** (Phase 2 — 2026-04-20)
  - `Run.Server.finish_run/2` emits `"run_partial"` for `:partial` (case on status: `:success` → `run_completed`, `:partial` → `run_partial`, `:failed` → `run_failed`). `terminal_status/2` simplified to a 1:1 event-type → status map (the old heuristic that derived `:partial` from node_states was removed — event type is the canonical discriminator now). `result_from_event_log/1` and the `handle_continue({:rebuild, ...})` terminal-event guards both accept `"run_partial"`. `Liminara.Run` (synchronous) is untouched — it only halts on first failure, never produces `:partial`.
  - `Liminara.Observation.ViewModel.apply_typed/4` grows a `"run_partial"` clause that projects `run_status: :partial` and `degraded: derive_degraded(:partial, warning_count)`. `extract_warning_summary!/1` error message updated to mention all three terminal types.
  - `Liminara.Observation.Server.publish_state/2` includes `:partial` in the `in [...]` status filter so runs-index broadcasts fire for partial runs.
  - `LiminaraWeb.RunsLive.Show.apply_event_type/4` grows a `"run_partial"` clause (mirrors `run_completed` but writes `run_status: "partial"`). `derive_status/1`, `completed_at/1` guard, and `warning_summary_from_terminal_event/1` all recognise `"run_partial"`. `derive_degraded_from_events/1` already-correct: `n > 0 and not last_event_failed?(events)` returns `true` for a partial-with-warnings since the last event is `"run_partial"`, not `"run_failed"`.
  - `LiminaraWeb.RunsLive.Index.event_type_to_status/1`, `update_status/2`, `derive_degraded/2`, `update_warning_count/3` all grow a `"run_partial"` clause. `build_run_summary/3` on-disk degraded check broadened from `status == "completed"` to `status in ["completed", "partial"]`.
  - CLI (`Run.Result.degraded`) already handled `:partial` correctly via `Result.derive_degraded/2` — no change needed there. `:failed → false` rule preserved.
  - End-to-end `partial_run_integration_test.exs` asserts `:partial` terminal, `degraded: true` on `Run.Result`, ViewModel, runs-index row, run-detail view. Replay parity + `result_from_event_log` recognition covered. Edge cases: partial-with-zero-warnings → not degraded; pure single-node failure → remains `:failed` with `degraded: false` (AC2 rule preserved).
  - `seal` file write preserved for `:partial` runs (untouched in `finish_run/2`).
  - RED verified: reverted the `finish_run` status-to-event-type dispatch to produce 11 failures (4 integration, 6 view_model unit, 2 Index live partial, 2+2 warnings_test run_event/fallback paths).
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

### Phase 2 (merged_bug_001)

- **New file**: `apps/liminara_observation/test/liminara/observation/partial_run_integration_test.exs` — 6 tests, 0 failures (2-node partial + event-type verification + replay-parity + result_from_event_log rebuild + partial-with-zero-warnings + pure single-node failure)
- **Added describes** (extending existing files):
  - `apps/liminara_observation/test/liminara/observation/view_model_test.exs` — 6 new tests in `apply_event/2 - run_partial` (run_status, timestamp, warning_summary extraction, degraded derivation true/false, contract violation)
  - `apps/liminara_web/test/liminara_web/live/runs_live_index_test.exs` — 3 new tests covering Index `run_partial` on the live path (`update_existing_run` with degraded+partial badge), zero-warnings partial, and on-disk mount (`build_run_summary` → partial+degraded)
  - `apps/liminara_web/test/liminara_web/live/runs_live/warnings_test.exs` — 6 new tests covering `RunsLive.Show` on the state_update path (partial with warnings / without), live run_event path (`apply_event_type`), and event-log fallback path (`build_from_events` + `derive_degraded_from_events`) with and without warnings
- **Per-app suite runs** (post-fix, foreground, per-app):
  - `liminara_observation`: 291 tests / 0 failures (was 279 after Phase 1 — +12 total from Phase 2's integration + view_model additions)
  - `liminara_web`: 206 tests / 0 failures (was 198 pre-M-WARN-04 — +8 total from Phase 2's Index + warnings_test additions)
  - `liminara_core/test/liminara/run`: 161 tests / 0 failures
  - `liminara_core` full suite: 438 tests / 0 failures / 8 properties
  - `liminara_radar`: 97 tests / 0 failures
- **Fixture migration**:
  - `apps/liminara_observation/test/liminara/observation/integration_test.exs:163` — the "failing run: failed node marked :failed, run_status :failed" test was renamed and updated. Previously a linear `ok -> fail` plan was expected to project `run_status: :failed` (because the runtime emitted `"run_failed"` and the `terminal_status/2` heuristic then re-derived status from node_states at the Result boundary). With the new 1:1 event-type → status mapping, that plan correctly emits `"run_partial"` (stuck + failed + completed + no pending), so `run_status` is `:partial`. Test updated to assert `:partial` and verifies both the failed node and the completed node.
  - No other fixtures required migration. All test helpers that construct terminal events by hand (e.g. `run_completed_event/2`, `run_failed` in view_model_test) were checked — none previously emitted `"run_failed"` for a `:partial` run. The one `run_partial_event/2` helper added in view_model_test is new, not a migration.
- **Formatting**: `mix format` applied after the fix; `mix format --check-formatted` clean.
- **Credo**: `mix credo --strict` produces the same 7 pre-existing refactoring opportunities (unchanged from M-WARN-03 baseline).

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

### Phase 2: `run_partial` event-type consumers (merged_bug_001)

14 new or changed reachable branches in six consumers. Every branch has at least one test.

| Branch | Covered by |
|--------|------------|
| `Run.Server.finish_run/2` case `:success → "run_completed"` | existing `simple_plan()` tests across run, integration, partial_run_integration's "pure failed" setup |
| `Run.Server.finish_run/2` case `:partial → "run_partial"` | `partial_run_integration_test.exs` end-to-end |
| `Run.Server.finish_run/2` case `:failed → "run_failed"` | `partial_run_integration_test.exs` `:failed` rule preserved + existing failure tests |
| `Run.Server.terminal_status("run_completed")` | existing success tests |
| `Run.Server.terminal_status("run_partial")` | `partial_run_integration_test.exs` replay + rebuild tests |
| `Run.Server.terminal_status("run_failed")` | existing failure tests |
| `ViewModel.apply_typed(_, "run_partial", _, _)` | `view_model_test.exs` `run_partial` describe (6 cases) + partial_run_integration live path |
| `Observation.Server.publish_state/2` `:partial` in filter | partial_run_integration + Observation integration (all partial-run tests verify the ViewModel state is broadcast/readable) |
| `RunsLive.Show.apply_event_type(_, "run_partial", _, _)` | `warnings_test.exs` "run_event path: apply_event_type" |
| `RunsLive.Show.derive_status("run_partial")` | `warnings_test.exs` "event-log fallback" |
| `RunsLive.Show.completed_at/1` guard with `"run_partial"` | `warnings_test.exs` "event-log fallback" (page renders completed_at for partial terminal) |
| `RunsLive.Show.warning_summary_from_terminal_event` type filter with `"run_partial"` | `warnings_test.exs` "event-log fallback" (degraded derivation relies on the summary being found) |
| `RunsLive.Index.event_type_to_status("run_partial")` | `runs_live_index_test.exs` on-disk mount test (partial) + live partial test |
| `RunsLive.Index.update_status(_, "run_partial")` | `runs_live_index_test.exs` live partial test (run_started → run_partial path) |
| `RunsLive.Index.derive_degraded("run_partial", _)` | `runs_live_index_test.exs` live partial with/without warnings |
| `RunsLive.Index.update_warning_count(_, _, "run_partial")` | `runs_live_index_test.exs` live partial (warning_count populated from payload) |
| `RunsLive.Index.build_run_summary/3` degraded filter `in ["completed", "partial"]` | `runs_live_index_test.exs` on-disk mount test |

No genuinely unreachable branches introduced in Phase 2. The `Observation.Server.publish_state/2` `:partial` in the broadcast filter is exercised by every partial-run test that observes ViewModel state via `get_state` (the same broadcast pathway that drives `runs:index` subscribers is used to refresh the live state the tests poll).

## Validation Pipeline

*To be filled at wrap time.*

## Notes

*To be filled as decisions and pitfalls surface during TDD.*

## References

- Spec: `work/epics/E-19-warnings-degraded-outcomes/M-WARN-04-postreview-bugfixes.md`
- Ultrareview: task `r2fg1c81b`, findings `bug_005`, `merged_bug_001`, `bug_004`, `bug_009`
- Epic: `work/epics/E-19-warnings-degraded-outcomes/epic.md`
- Upstream milestones: `M-WARN-01-tracking.md`, `M-WARN-02-tracking.md`, `M-WARN-03-tracking.md`
