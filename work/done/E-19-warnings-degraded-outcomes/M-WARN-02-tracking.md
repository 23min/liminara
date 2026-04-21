# M-WARN-02: Observation + UI Surfacing — Tracking

**Started:** 2026-04-17
**Branch:** `epic/E-19-warnings-degraded-outcomes`
**Spec:** `work/epics/E-19-warnings-degraded-outcomes/M-WARN-02-observation-ui-surfacing.md`
**Status:** complete (committed as `d39cb3e`)

## Summary

M-WARN-02 wires the runtime warning contract (locked in M-WARN-01) through
the observation projection, the `/runs/:id` LiveView, the `/runs` index,
and the CLI surfaces in `mix radar.run` and `mix demo_run`. Warnings are
now projected per-node and aggregated at the run level from the
`run_completed`/`run_failed` `warning_summary` payload. Degraded runs are
visually distinct from both plain-success and failed runs.

## Acceptance Criteria

- [x] **AC1: `Liminara.Observation.ViewModel` preserves warnings**
  - Per-node `warnings :: [map()]` populated from `op_completed.payload.warnings`
  - Per-node `degraded :: boolean()` derived as `warnings != []`
  - Run-level `warning_count`, `degraded_nodes`, derived `degraded` populated from `run_completed.payload.warning_summary`
  - Missing/malformed `warning_summary` raises `ArgumentError` (contract violation)
  - Malformed `op_completed.warnings` entries (missing required fields, non-list, non-map entry) raise
  - Missing `warnings` key in `op_completed` raises (see **M-WARN-01 tightening** below — the runtime now emits `"warnings" => []` on every `op_completed`, closing the gap that originally forced the projection to tolerate absent keys)
  - `init/3` seeds all new fields with zero values
  - Evidence: `runtime/apps/liminara_observation/lib/liminara/observation/view_model.ex`, tests in `view_model_test.exs:1014-1560`

- [x] **AC2: `LiminaraWeb.RunsLive.Show` renders degraded status**
  - Run-header degraded badge + warning count shown when `degraded: true`; plain-success runs render the existing success badge with no degraded surface
  - DAG node JSON carries a `degraded: true` flag on warning-bearing nodes; CSS class in root layout distinguishes it from failed
  - Node-inspector **Warnings** section is separate from the existing **Decisions** section
  - Warning entries render `code`, `severity`, `summary`, `cause`, `remediation`, `affected_outputs` with explicit field labels
  - Warnings section is absent when the selected node has no warnings
  - Run-level degraded banner lists the degraded node ids (reachable without switching to the events tab)
  - Evidence: `runtime/apps/liminara_web/lib/liminara_web/live/runs_live/show.ex`, tests in `apps/liminara_web/test/liminara_web/live/runs_live/warnings_test.exs`

- [x] **AC3: `LiminaraWeb.RunsLive.Index` marks degraded runs**
  - Row carries a `status--degraded` badge when `warning_count > 0` and the run is not failed
  - Failed runs take precedence: the degraded badge is suppressed even if warnings are present
  - Plain-success runs show only the existing status badge
  - Evidence: `runtime/apps/liminara_web/lib/liminara_web/live/runs_live/index.ex`, tests in `runs_live_index_test.exs` ("degraded run indicator" describe block)

- [x] **AC4: Mix-task CLI surfaces degraded runs**
  - `Liminara.Run.Cli.degraded_banner/1` returns a single-line banner for degraded-success runs, `nil` for plain-success and for failed runs (failure takes precedence)
  - `mix radar.run` calls the helper after the completion line; output unchanged on plain-success runs
  - `mix demo_run` best-effort awaits 200ms post-start and prints the banner when the run already completed (e.g. a future non-gate demo plan); gate-based demos continue to print the existing "paused at gate" message
  - Exit code unchanged: degraded runs still exit 0
  - Evidence: `runtime/apps/liminara_core/lib/liminara/run/cli.ex`, tests in `apps/liminara_core/test/liminara/run/cli_test.exs`

- [x] **AC5: Tests cover observation projection and LiveView rendering**
  - 31 new tests in `view_model_test.exs` cover warning projection, run-level aggregation, degraded derivation, and contract-violation raises
  - 11 new tests in `runs_live/warnings_test.exs` cover run-header badge, DAG indicator, inspector Warnings section (present/absent/multi-entry/optional-field-tolerance/separation-from-decisions)
  - 3 new tests in `runs_live_index_test.exs` cover per-row degraded indicator presence, plain-success absence, and failed-takes-precedence
  - 7 new tests in `run/cli_test.exs` cover banner content, banner absence on plain-success, and banner absence on failed runs
  - Existing observation and LiveView suites continue to pass (272 observation, 198 web, 77 focused core, 75 radar) after test fixtures were updated to include the now-required `warning_summary` key in `run_completed`/`run_failed` events

## Test Summary (targeted per-app suites, full umbrella not run due to known integration-test hang)

- `mix test apps/liminara_observation/test` → **272 tests, 0 failures** (14.7s)
- `mix test apps/liminara_web/test` → **198 tests, 0 failures** (20.0s)
- `mix test apps/liminara_core/test/liminara/run/cli_test.exs apps/liminara_core/test/liminara/run/warning_aggregation_test.exs apps/liminara_core/test/liminara/execution_contract_structs_test.exs apps/liminara_core/test/liminara/execution_runtime_contract_test.exs` → **77 tests, 0 failures** (1.7s)
- `mix test apps/liminara_radar/test` → **75 tests, 0 failures** (62.9s)

## Validation Pipeline

- `mix format --check-formatted` on M-WARN-02 touched files → **pass** (pre-existing `config/dev.exs` formatting issue is outside scope)
- `mix credo --strict` → **7 refactoring + 1 consistency** issues, all pre-existing (down from baseline of 8 + 1). No net-new issues after post-GREEN refactoring extracted `update_existing_run/3`, `build_run_summary/3`, `find_terminal_warning_summary/1`, `last_event_failed?/1`, and decomposed `extract_warning_summary!/1` into `fetch_summary_map!/1`, `fetch_non_neg_integer!/2`, `fetch_list!/2`.
- `mix dialyzer` → **2 warnings**, both pre-existing (`a2ui_provider.ex:95` callback type mismatch and `show.ex:618` unreachable `_ -> []` pattern — neither touched by M-WARN-02)

## Coverage Notes

- Branch-coverage audit performed on all new/changed paths:
  - `view_model.ex` extract/validate/fetch helpers: each `:error`, non-map, non-integer, non-list, and malformed-entry branch covered by a dedicated `assert_raise` test
  - `show.ex` degraded rendering helpers and DAG JSON: both degraded and non-degraded branches exercised
  - `index.ex` degraded derivation in `update_existing_run` and `build_run_summary`: degraded / plain-success / failed-with-warnings branches each exercised
  - `cli.ex`: failed / plain-success / degraded / partial-zero-warnings paths all covered

## Scope Adherence

- No runtime contract changes (per M-WARN-01 freeze): no new event types, no shape changes to `op_completed.warnings` or `run_completed.warning_summary`, no new fields on `Run.Result`
- No A2UI surface changes (deferred to E-21b / E-21c)
- No Radar pack changes (briefing annotation is M-WARN-03)
- Decisions and Warnings remain separate inspector sections
- Exit codes unchanged: degraded runs still exit 0

## M-WARN-01 tightening (landed under this milestone's branch)

Review of M-WARN-02's initial contract interpretation surfaced a gap in M-WARN-01: `Liminara.Run.Server.handle_replay_skip/2`, `handle_gate_resolved/3`, `handle_cache_hit/3` and `Liminara.Run.handle_replay_skip/2`, `handle_cache_hit/3` all emitted `op_completed` without a `warnings` key. That made the ViewModel's "absent key = no warnings" branch load-bearing — a backward-compat fallback the user explicitly rejected.

Fixed in place under this branch (five runtime emission sites + two consumer paths):

- `runtime/apps/liminara_core/lib/liminara/run/server.ex` — `handle_replay_skip`, `handle_gate_resolved`, `handle_cache_hit` now emit `"warnings" => []`
- `runtime/apps/liminara_core/lib/liminara/run.ex` — `handle_replay_skip`, `handle_cache_hit` now emit `"warnings" => []`
- `runtime/apps/liminara_core/lib/liminara/run/server.ex` — `rebuild_from_events` and `warning_aggregation_from_events` now use `Map.fetch!(payload, "warnings")`; silent fallthrough was removed
- `runtime/apps/liminara_observation/lib/liminara/observation/view_model.ex` — `extract_op_completed_warnings/1` raises on missing key

Test fixtures that constructed `op_completed` payloads by hand were updated to include `"warnings" => []`:

- `apps/liminara_observation/test/liminara/observation/view_model_test.exs` (also: "without warnings key" test flipped to assert the raise)
- `apps/liminara_observation/test/liminara/observation/view_model_events_test.exs`
- `apps/liminara_observation/test/liminara/observation/server_events_test.exs`
- `apps/liminara_observation/test/liminara/observation/server_test.exs`
- `apps/liminara_web/test/liminara_web/live/runs_live/timeline_test.exs`

Validation after tightening:

- `mix test apps/liminara_observation/test` → 272 tests, 0 failures
- `mix test apps/liminara_core/test/liminara/run apps/liminara_core/test/liminara/execution_contract_structs_test.exs apps/liminara_core/test/liminara/execution_runtime_contract_test.exs` → 216 tests, 0 failures
- `mix test apps/liminara_core/test/liminara/property_test.exs apps/liminara_core/test/liminara/integration_test.exs apps/liminara_core/test/liminara/golden_fixtures_test.exs apps/liminara_core/test/liminara/toy_pack_test.exs apps/liminara_core/test/liminara/event/store_test.exs` → 8 properties + 38 tests, 0 failures
- `mix test apps/liminara_web/test` → 198 tests, 0 failures
- `mix test apps/liminara_radar/test` → 75 tests, 0 failures

The M-WARN-01 tracking doc (`M-WARN-01-tracking.md`) should be amended to record this tightening before commit.

## UI Judgment Calls (for review before commit)

1. **Degraded badge CSS**: amber/yellow (`#fff8e1` bg, `#b28600` fg, `#ffd54f` border) chosen to sit between green success and red failure. Alternative: orange/warning palette. Reviewer may want to swap the palette — the CSS is localised to `root.html.heex` and trivial to adjust.
2. **Run-header layout**: degraded status is rendered as a second badge alongside the existing status badge (not replacing it). The degraded banner below the meta row restates the warning count + node ids to ensure the information is reachable without scrolling into the inspector.
3. **`mix demo_run` awaits 200ms**: the existing flow is gate-first and never completes before CLI exit. I added a short `Server.await(..., 200)` after the existing 500ms sleep so a future non-gate demo plan will print the banner. For the current gate-based demo plan, the await returns `{:error, :timeout}` and the banner is skipped silently — no change in observable behaviour.
4. **Inspector Warnings section is rendered above Decisions** (not below). This matches the operator reading order: warnings signal *quality of output* and should surface before the nondeterminism audit trail.

## References

- Spec: `work/epics/E-19-warnings-degraded-outcomes/M-WARN-02-observation-ui-surfacing.md`
- Upstream contract: `work/epics/E-19-warnings-degraded-outcomes/M-WARN-01-tracking.md`
- Epic: `work/epics/E-19-warnings-degraded-outcomes/epic.md`
- Downstream: `work/epics/E-19-warnings-degraded-outcomes/M-WARN-03-radar-adoption.md` (not yet started)
