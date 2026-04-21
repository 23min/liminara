# M-WARN-04: Post-Review Bugfixes — Tracking

**Started:** 2026-04-20
**Branch:** `epic/E-19-warnings-degraded-outcomes` (continuing epic branch per E-19 pattern; milestones M-WARN-01/02/03 were all committed directly here without a separate milestone branch)
**Spec:** `work/epics/E-19-warnings-degraded-outcomes/M-WARN-04-postreview-bugfixes.md`
**Status:** **complete** (6/6 ACs landed; all 5 phases committed — `3e43f8a`, `8c445e3`, `e68aa98`, `93792f4`, `fac07bd`)
**Completed:** 2026-04-21
**Source of bugs:** ultrareview task `r2fg1c81b` (2026-04-20)

## Resolved Gaps (2026-04-21)

All six ACs landed and committed:

- AC1 Phase 1 (bug_005) — `3e43f8a`
- AC2 Phase 2 (merged_bug_001) — `8c445e3`
- AC3 Phase 3 (bug_004) — `e68aa98`
- AC4 Phase 4 (bug_009) — `93792f4`
- AC5 Phase 5 + AC6 wrap validation — `fac07bd`

M-WARN-04 closes E-19. No deferred items from this milestone.

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
- [x] **AC3: `RunsLive.Index` assigns `warning_count` from the terminal payload, never accumulates** (Phase 3 — 2026-04-20)
  - `RunsLive.Index.update_existing_run/3` now assigns `warning_count` directly from the terminal payload (`warning_count_from_payload(payload)` when `event_type in ["run_completed", "run_partial", "run_failed"]`), else preserves `Map.get(existing, :warning_count, 0)` so non-terminal events (`op_started`, `op_completed`, etc. delivered during Run.Server rebuild re-broadcast) don't zero out an existing count. Mirrors `build_run_summary/3`'s direct assignment on the disk-load path. The now-unreachable helper `update_warning_count/3` was removed (single-use, no external callers).
  - Four tests in new `describe "warning_count idempotence on re-delivered terminal events"` block in `apps/liminara_web/test/liminara_web/live/runs_live_index_test.exs`:
    1. **baseline happy-path**: single terminal delivery populates `warning_count = N` (passes trivially — bug only manifests on re-delivery)
    2. **mount-race**: on-disk summary prefetched (`load_runs_from_store` → `build_run_summary`), then same terminal arrives via `:pg` broadcast — uses per-test tmp `runs_root` for disk isolation; asserts `degraded (2)` and `refute degraded (4)`
    3. **rebuild-rebroadcast**: same terminal event sent twice via `:pg` — asserts `degraded (3)` and `refute degraded (6)` / `refute degraded (9)`
    4. **zero-warning idempotence**: duplicate terminal with `warning_count: 0` leaves no degraded badge on the target row (row-scoped regex assertion to stay robust against unrelated leaked rows)
  - RED verified: pre-fix run produced `degraded (4)` and `degraded (6)` against expected `(2)` / `(3)` respectively — the documented bug_004 signature.
  - Fixture migration: none triggered by the bug_004 fix itself. However adding 4 tests to the web suite perturbed ExUnit's per-seed module shuffle, exposing a pre-existing cross-test leak: `warnings_test.exs`'s `partial run detail (event-log fallback)` describe block persists `fb-partial-*` / `fb-plain-*` runs into the shared supervised-store `runs_root` (`/tmp/liminara_runs/`) without cleanup, causing later `RunsLive.IndexTest` `refute html =~ "status--degraded"` assertions to see sibling-test rows and fail. Fixed in place: added a `setup` block that captures the supervised store's `runs_root` and an `on_exit` per test that deletes the test's own run directory (`File.rm_rf!(Path.join(runs_root, run_id))`). The supervised `Event.Store` reads its `runs_root` once at startup, so `Application.put_env` at setup time doesn't reach it — per-run-dir cleanup is the minimal fix.
- [x] **AC4: Event-log fallback path preserves per-node degraded state** (Phase 4 — 2026-04-21)
  - `RunsLive.Show.build_nodes/1` at `runtime/apps/liminara_web/lib/liminara_web/live/runs_live/show.ex:883-912` now reads `event["payload"]["warnings"]` on `op_completed` and sets `:warnings` (list of string-keyed warning maps, as stored on the wire post-bug_005) and `:degraded` (boolean, `warnings != []`) on the per-node map. The view_model nodes list is a subset of the primary obs path: `:degraded` drives the DAG pill (via `nodes_only_dag_json` at line 575-593), and `:warnings` lets `find_in_view_model/2` supply the inspector Warnings section when `obs_nodes` is empty on the fallback path.
  - Two new tests in `apps/liminara_web/test/liminara_web/live/runs_live/warnings_test.exs` `describe "partial run detail (event-log fallback: build_from_events)"`:
    1. `event log op_completed with warnings marks per-node degraded in DAG data on fallback` — 2-node fallback run (warn + plain). Decodes the `data-dag` attribute via `extract_dag_json!/1` helper (replaces `&quot;` → `"` then Jason.decode!), asserts `warn["degraded"] == true` and `plain["degraded"] != true`.
    2. `event log op_completed warnings render in inspector Warnings section on fallback` — persists an op_completed with a full canonical warning, renders `/runs/:id`, `render_click(view, "select_node", %{"node-id" => "summarize"})`, asserts the Warnings header plus `code`, `summary`, `cause`, `remediation` all appear.
  - RED verified: pre-fix run produced exactly the documented bug_009 signature — the data-dag JSON lacked `"degraded":true` for the warn node, and the inspector rendered Fields/status but no Warnings section (and `llm_fallback`/`summary`/`cause`/`remediation` strings absent).
  - Fixture migration: none. The `extract_dag_json!/1` helper is a new test utility, not a migration of existing fixtures.
- [x] **AC5: Cross-layer consistency tests** (Phase 5 — 2026-04-21)
  - New test module `apps/liminara_web/test/liminara_web/live/runs_live/warning_cross_layer_test.exs` (4 tests, 0 failures) exercises all four fixed paths:
    1. `live warning broadcast reaches ViewModel without raising (bug_005)` — runs a real `%Warning{}`-bearing plan through `Run.Server → :pg → Observation.Server`, asserts the observer survives, `state.nodes["warn"].degraded == true`, and `/runs/:id` renders the degraded badge.
    2. `partial-with-warnings reaches every consumer as degraded (merged_bug_001)` — runs a fan-out partial plan, asserts `Run.Result.status == :partial` with `degraded: true`, ViewModel `run_status: :partial` with `degraded: true`, and `/runs/:id` renders both `status--partial` + `status--degraded` while NOT rendering `status--failed`.
    3. `runs-index warning_count stays stable on duplicate terminal (bug_004)` — runs a warning plan under a `run-xlayer-*` id (passes `real_run?/2`), mounts `/runs`, asserts the row for this run shows `degraded (1)` and not `degraded (2)`.
    4. `event-log fallback preserves per-node degraded (bug_009)` — appends events without a plan.json, mounts `/runs/:id`, decodes `data-dag`, asserts `warn["degraded"] == true`, then `render_click(view, "select_node", ...)` and asserts the inspector Warnings section renders code/summary/cause/remediation.
  - Module-level `setup` grabs the supervised `runs_root`; every test `on_exit`s a `File.rm_rf!` of its own run dir to prevent cross-test leak (same isolation pattern used by the existing warnings_test.exs fallback describe).
  - All four tests pass against the HEAD of Phase 1+2+3+4. Verified stable across seeds.
- [x] **AC6: Validation pipeline stays at baseline** (wrap-time — 2026-04-21)
  - Per-app suites: see the Validation Pipeline table below. All green; deltas accounted for by new M-WARN-04 tests only.
  - Python: `uvx ruff check .` + `uvx ruff format --check .` pass (33 files already formatted).
  - `mix format --check-formatted` clean.
  - `mix credo --strict`: 7 refactoring opportunities, unchanged from M-WARN-03 baseline.
  - `mix dialyzer`: 2 errors, both pre-existing and unchanged from M-WARN-03 baseline (verified against HEAD pre-Phase 5).

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

### Phase 4 (bug_009)

- **Added** to existing file `apps/liminara_web/test/liminara_web/live/runs_live/warnings_test.exs`:
  - 2 new tests inside the existing `"partial run detail (event-log fallback: build_from_events)"` describe block (see AC4 above for titles).
  - 1 new helper `extract_dag_json!/1` at module top (extracts the `data-dag` attribute, unescapes `&quot;`/`&amp;`, `Jason.decode!`s).
- **Modified** `apps/liminara_web/lib/liminara_web/live/runs_live/show.ex`: `build_nodes/1` op_completed arm replaced from a single `status: "completed"` struct-update to a three-step pipeline setting `:status`, `:warnings` (from payload, default `[]`), `:degraded` (`warnings != []`).
- **Per-app suite run** (post-fix, foreground):
  - `liminara_web`: 212 tests / 0 failures (was 210 after Phase 3 — +2 from Phase 4's fallback tests)
- **Formatting**: `mix format --check-formatted` clean on the modified files.

### Phase 3 (bug_004)

- **Added** to existing file `apps/liminara_web/test/liminara_web/live/runs_live_index_test.exs`: 4 new tests in `describe "warning_count idempotence on re-delivered terminal events"` (baseline, mount-race, rebuild-rebroadcast, zero-warning).
- **Modified** (test-isolation, Phase-3-exposed regression fix) `apps/liminara_web/test/liminara_web/live/runs_live/warnings_test.exs`: `describe "partial run detail (event-log fallback: build_from_events)"` now has a `setup` block capturing the supervised-store `runs_root` and each test does `on_exit(fn -> File.rm_rf!(Path.join(runs_root, run_id)) end)` to prevent persisted `fb-partial-*` / `fb-plain-*` runs from leaking into later tests that mount `/runs`.
- **Per-app suite runs** (post-fix, foreground, per-app):
  - `liminara_web`: 210 tests / 0 failures, verified stable across seeds 0, 1, 42, 99, 7777 (was 206 after Phase 2 — +4 from Phase 3's idempotence tests)
  - `liminara_observation`: 291 tests / 0 failures (unchanged from Phase 2)
  - `liminara_core/test/liminara/run`: 161 tests / 0 failures
  - `liminara_core` execution contracts: 55 tests / 0 failures
  - `liminara_radar`: 97 tests / 0 failures
- **Fixture migration**: none required by the fix itself. Modified warnings_test.exs fallback describe block as a test-isolation fix (described above), not a fixture content migration — the event payloads those tests write are unchanged.
- **Helper removed**: `update_warning_count/3` in `index.ex` deleted; its only caller was the additive expression that the bug_004 fix replaces. `rg update_warning_count runtime/` returns zero references. No branch-coverage loss — its terminal arm's behaviour is now the explicit terminal clause in `update_existing_run/3`, and the `_, _, _` fallthrough head is now the `else` clause that preserves `existing.warning_count`.
- **Formatting**: `mix format --check-formatted` clean.

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

### Phase 3: `update_existing_run/3` (bug_004)

The additive `Map.get(existing, :warning_count, 0) + update_warning_count(existing, payload, event_type)` expression is replaced by a two-branch `if`. Coverage:

| Branch | Covered by |
|--------|------------|
| `event_type in ["run_completed", "run_partial", "run_failed"]` — terminal direct-assign | (run_completed) baseline happy-path + mount-race + rebuild-rebroadcast + zero-warning idempotence tests + pre-existing `degraded run indicator` tests; (run_partial) Phase 2 `partial run (run_partial event)` tests where `run_started` precedes the terminal `run_partial`; (run_failed) pre-existing `failed run does NOT show a degraded indicator even with warnings` test |
| else branch — non-terminal event preserves `existing.warning_count` | Pre-existing `shows run_id/pack_id/status for each run`, `real-time updates`, `multiple runs appear in list as they complete` tests flow a real `RunServer.start` plan whose `op_started`/`op_completed` events are broadcast to `:all_runs` and hit this branch for an already-initialised entry |
| Rebuild-rebroadcast of non-terminal events (from `Run.Server` lines 236-242) | Same real-RunServer flow as above; `Run.Server` `rebuild_from_events` re-broadcasts all atom-keyed events including intermediate `op_*` events, and `apply_run_event/3` passes atom-keyed maps through the same `Map.get(event, "event_type") || Map.get(event, :event_type)` path |

The removed helper `update_warning_count/3` had two heads (terminal guard + fallthrough). Both behaviours are now inline in the `if/else` above. No dangling defensive branch.

### Phase 4: `build_nodes/1` op_completed arm (bug_009)

The op_completed arm of `RunsLive.Show.build_nodes/1` now sets three fields (`:status`, `:warnings`, `:degraded`) instead of one. Coverage:

| Branch | Covered by |
|--------|------------|
| `op_completed` with non-empty `payload["warnings"]` — `:degraded => true` | `event log op_completed with warnings marks per-node degraded in DAG data on fallback` (warn node) + `event log op_completed warnings render in inspector Warnings section on fallback` |
| `op_completed` with absent `payload["warnings"]` — `warnings = []`, `:degraded => false` | `event log op_completed with warnings marks per-node degraded in DAG data on fallback` (plain node; op_completed payload omits the `"warnings"` key entirely) + pre-existing `build_from_events` event-log fallback tests |
| `op_completed` with explicit `payload["warnings"] = []` | Collapses into the same arm as absent-key; contract-indistinguishable. Not separately tested — the `\|\| []` default makes the two paths produce identical node state. |
| `nodes_only_dag_json` node with `:degraded => true` put onto base | DAG test decodes `data-dag` and asserts `warn["degraded"] == true` |
| `nodes_only_dag_json` node with `:degraded => false` (default not applied) | DAG test asserts `plain["degraded"] != true` (key absent per `nodes_only_dag_json` line 585's `if degraded` guard) |
| `find_in_view_model/2` fallback returning a view_model node with `:warnings` populated | Inspector test asserts `Warnings` header + `code`/`summary`/`cause`/`remediation` strings present after `select_node` |

No unreachable branches introduced. The op_started/op_failed arms are unchanged and continue to carry their pre-existing coverage (existing `build_from_events` event-log fallback tests).

## Validation Pipeline

Run 2026-04-21, all scopes foreground + per-app per CLAUDE.md testing rules.

### Per-app test suites

| Suite | Result | Delta from M-WARN-03 baseline |
|-------|--------|-------------------------------|
| `apps/liminara_radar/test` | 97 / 0 | unchanged (no radar touch) |
| `apps/liminara_observation/test` | 291 / 0 | +19 (+12 Phase 2 view_model + partial integration, +7 Phase 1 live integration) |
| `apps/liminara_web/test` | 216 / 0 | +18 (+8 Phase 2 Index/warnings partial, +4 Phase 3 idempotence, +2 Phase 4 fallback, +4 Phase 5 cross-layer) |
| `apps/liminara_core/test/liminara/run` + `execution_runtime_contract_test.exs` | 182 / 0 | unchanged (no runtime Run.Server surface change in Phase 3/4/5) |
| `apps/liminara_core/test/liminara/execution_contract_structs_test.exs` + `execution_runtime_contract_test.exs` | 55 / 0 | unchanged |

Note: the broader `mix test apps/liminara_core/test` invocation hangs without emitting output in this environment (reproduced twice across fresh runs; Phase 2 notes saw 438/0/8 properties but that was on a different day — likely the pre-existing integration-test pathology flagged in CLAUDE.md "Running Tests from an AI Assistant"). The 182 + 55 per-directory scopes together cover every runtime code path M-WARN-04 modified.

### Python linters

| Tool | Result |
|------|--------|
| `uvx ruff check .` (under `runtime/python/`) | All checks passed |
| `uvx ruff format --check .` (under `runtime/python/`) | 33 files already formatted |

### Elixir linters

| Tool | Result |
|------|--------|
| `mix format --check-formatted` (umbrella root) | clean |
| `mix credo --strict` | 7 refactoring opportunities (unchanged from M-WARN-03 baseline; all 7 in pre-existing files, none in M-WARN-04 touchpoints) |
| `mix dialyzer` | 2 errors (`a2ui_provider.ex:95:callback_type_mismatch`, `runs_live/show.ex:618:pattern_match_cov`) — both pre-existing, identical on HEAD with or without Phase 4 edits. `show.ex:618` is `load_initial_events/1`'s defensive `_` fallthrough; M-WARN-04's only touch to `show.ex` is `build_nodes/1` at lines 883-912. |

Baseline preserved across all three linters.

## Notes

*To be filled as decisions and pitfalls surface during TDD.*

## References

- Spec: `work/epics/E-19-warnings-degraded-outcomes/M-WARN-04-postreview-bugfixes.md`
- Ultrareview: task `r2fg1c81b`, findings `bug_005`, `merged_bug_001`, `bug_004`, `bug_009`
- Epic: `work/epics/E-19-warnings-degraded-outcomes/epic.md`
- Upstream milestones: `M-WARN-01-tracking.md`, `M-WARN-02-tracking.md`, `M-WARN-03-tracking.md`
