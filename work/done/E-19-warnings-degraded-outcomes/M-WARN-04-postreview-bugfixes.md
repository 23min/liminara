---
id: M-WARN-04-postreview-bugfixes
epic: E-19-warnings-degraded-outcomes
status: complete
depends_on: M-WARN-03-radar-adoption
---

# M-WARN-04: Post-Review Bugfixes

## Goal

Close the four bugs the ultrareview surfaced against M-WARN-01 / M-WARN-02 / M-WARN-03, each of which directly invalidates a Success Criterion of E-19 on a reachable code path. After this milestone the epic can wrap honestly: every layer the warning/degraded-outcome contract touches (runtime, observation, LiveView, CLI, Radar briefing) agrees with every other layer on live, replay, crash-recovery, and `:partial` paths.

## Context

Ultrareview (task `r2fg1c81b`, 2026-04-20) produced four findings against commits `d39cb3e` and `629b902`:

1. **bug_005** — `Observation.ViewModel` crashes on live warnings because `Run.Server.warning_payload/1` emits atom-keyed maps while `validate_warning_entry!/1` checks for string keys. Replay passes (JSON round-trip normalises keys) but live broadcast crashes `Observation.Server` on the first `op_completed.warnings`. Any Radar run with `ANTHROPIC_API_KEY` missing takes down the dashboard.
2. **merged_bug_001** — `Run.Server.finish_run` emits the same `"run_failed"` event for both `:failed` and `:partial` terminal statuses with no disambiguator. `Observation.ViewModel`, `RunsLive.Show`, and `RunsLive.Index` all hardcode `derive_degraded(:failed, wc) → false`, so a `:partial`-with-warnings run shows `degraded: true` on `Run.Result` (CLI banner) but `degraded: false` across every web/observation surface.
3. **bug_004** — `RunsLive.Index.update_existing_run/3` accumulates `warning_count` additively even though `update_warning_count/3` returns the full aggregate from the terminal payload. A re-delivered terminal event (mount-time `:pg.join`/`load_runs_from_store` race, or `Run.Server` rebuild re-broadcast) inflates the count to 2N, 3N, etc. Visible as `degraded (2)` / `degraded (6)` in the runs index for a run with exactly 1 / 3 warnings.
4. **bug_009** — `RunsLive.Show.build_nodes/1` in the event-log fallback path reduces `op_completed` to `%{node_id, op_name, status}`, dropping `payload["warnings"]`. When `Observation.Server` cannot start (plan deserialisation fails, op modules not loaded in the web runtime), the run-level banner still fires via `derive_degraded_from_events/1` but per-node DAG pills and the inspector Warnings section silently disappear.

All four are directly material to the E-19 epic success criteria:

- *"the run detail UI shows degraded badges/counts and exposes warning cause/remediation"* — violated by bug_005 (dashboard crash), merged_bug_001 (`:partial` path), bug_009 (fallback path)
- *"run-level summary and CLI output clearly distinguish plain success from success with warnings"* — violated by merged_bug_001 (cross-layer disagreement) and bug_004 (inflated count)
- *"rendered Radar briefing indicates when placeholder or degraded content was used"* — works on happy path; blocked on dashboard via bug_005 when observation server crashes

## Milestone Boundary

M-WARN-04 may implement:

- A string-keyed live warning payload emission from `Run.Server`, so live broadcast and JSON-roundtripped replay present identical shape to consumers
- A disambiguated terminal event for `:partial` runs, so every consumer can correctly derive `degraded` on partial-with-warnings
- An idempotent warning-count assignment in `RunsLive.Index` on terminal events
- A `build_nodes/1` extension in the event-log fallback path that preserves per-node `warnings` and `degraded`
- An end-to-end test that routes a real `%Warning{}` through `Run.Server → :pg → Observation.Server → ViewModel` (closing the coverage hole the review exposed)
- Targeted per-bug tests for the three other findings

M-WARN-04 does not implement:

- Changes to the canonical `Liminara.Warning` struct or its validation (fix is at the payload-emission boundary)
- Changes to `Run.Result` or the run-server `finish_run/2` beyond the minimum needed to disambiguate `:partial`
- Any new warning codes, severities, fields, or event types beyond what the four fixes require
- UI palette, layout, or copy changes beyond the minimum needed to surface the signal
- Radar pack semantic changes (M-WARN-03 is complete; this milestone does not reopen it)
- Retry, backoff, alerting, or policy engine work

## Acceptance Criteria

1. **Live warning payloads cross the runtime → observation boundary without crashing**
   - **Locked: wire-shape fix, not boundary normalisation.** `Run.Server.warning_payload/1` emits string-keyed maps so live `:pg` broadcasts match the JSON-roundtripped replay shape. Boundary normalisation in the ViewModel is explicitly rejected — it would reintroduce the "tolerate shape variance" duct-tape pattern M-WARN-01 / M-WARN-02 eliminated.
   - A new integration test routes a real `%Warning{}` through `Run.Server.emit_event → :pg → Observation.Server → ViewModel.apply_event` and asserts the projection populates per-node `warnings` + `degraded: true` without raising
   - Existing replay tests continue to pass unchanged (replay shape already matches the canonical string-keyed form)

2. **`:partial`-with-warnings is correctly marked degraded across every consumer**
   - **Locked: new `"run_partial"` event type.** `Run.Server.finish_run/2` emits `"run_completed"` for `:success`, `"run_partial"` for `:partial`, `"run_failed"` for `:failed`. One event type per terminal `Run.Result.status`. A payload-field discriminator is explicitly rejected — hiding a terminal distinction inside a nested field is the same silent-distinction-collapse pattern E-19 exists to eliminate.
   - `Liminara.Observation.ViewModel`, `LiminaraWeb.RunsLive.Show`, and `LiminaraWeb.RunsLive.Index` all gain a `"run_partial"` clause that derives `degraded: true` when `warning_count > 0` (same derivation as `run_completed`, different `run_status`). Any consumer that switches on event type grows exactly one clause.
   - CLI (`Run.Result.degraded` via `Liminara.Run.Cli`) and every web surface agree on the same run: all say `degraded: true` or all say `degraded: false`
   - An end-to-end test drives a 2-node plan where one node emits a warning and a downstream node fails; asserts `:partial` terminal, `degraded: true` on `Run.Result`, `degraded: true` on the ViewModel, `degraded: true` on the runs-index row, `degraded: true` on the run-detail view
   - **Important**: `Run.Result.derive_degraded/2` still keeps `:failed → false`; the fix is only for `:partial`
   - The `seal` file write in `finish_run/2` (`if status in [:success, :partial]`) is preserved — `:partial` still seals.

3. **`RunsLive.Index` assigns `warning_count` from the terminal payload, never accumulates**
   - `update_existing_run/3` assigns `warning_count` directly from the terminal payload via the same path `build_run_summary/3` uses on disk load, rather than adding to the existing accumulator
   - Two delivery paths are test-covered: (a) a terminal event arriving while a prefetched summary exists for the same `run_id` (simulating the mount-time `:pg.join`/`load_runs_from_store` race), (b) a duplicate terminal event delivered twice to the same LiveView (simulating `Run.Server` rebuild re-broadcast). Both must leave `warning_count == N`, not `2N` or `3N`.
   - No change to `derive_degraded/2` (which is already `or`-idempotent) or `build_run_summary/3` (which already assigns correctly)

4. **Event-log fallback path preserves per-node degraded state**
   - `RunsLive.Show.build_nodes/1` in the event-log fallback path reads `event["payload"]["warnings"]` on `op_completed` events and populates `:warnings` and `:degraded` on the per-node map, matching the shape `observation_state_to_view_model/1` produces on the primary path
   - A targeted test covers: fallback path (simulate `try_start_obs_server` returning `nil`) with a warning-emitting op; assert DAG JSON contains `degraded: true` for the warning-emitting node and the inspector Warnings section renders

5. **Cross-layer consistency tests are added**
   - A new test module exercises all four fixed paths in a single place — live warning broadcast, `:partial`-with-warnings, terminal-event replay, event-log fallback — so future regressions surface immediately
   - Test names read as specifications (`"live warning broadcast reaches ViewModel without raising"`, etc.)

6. **Validation pipeline stays at baseline**
   - Full per-app test suites green (see Testing rules below for scope)
   - `uvx ruff check .` / `uvx ruff format --check .` pass
   - `mix format --check-formatted`, `mix credo --strict`, `mix dialyzer` unchanged from the M-WARN-03 baseline

## Tests

Use the repository TDD conventions. Required categories:

- **Happy path**
  - Bug 005: `%Warning{code: "c", severity: :low, summary: "s"}` routed through `Run.Server → :pg → Observation.Server → ViewModel` produces `state.nodes[id].warnings` with length 1 and `degraded: true`, no exception raised
  - Bug merged_001: 2-node plan with one warning + one failing node yields `:partial` terminal, all four consumers report `degraded: true`
  - Bug 004: single terminal delivery populates `warning_count = N`
  - Bug 009: fallback path renders per-node pills for warning-emitting nodes

- **Edge cases**
  - Bug 005: warning payload with `nil` `cause`/`remediation` and empty `affected_outputs` still validates
  - Bug merged_001: `:partial` with zero warnings (all completed nodes clean) reports `degraded: false`
  - Bug 004: two duplicate terminal deliveries both leave `warning_count = N` (idempotent)
  - Bug 009: fallback path without any warnings leaves `degraded: false` everywhere

- **Error cases**
  - Bug 005: atom-keyed warning with missing required field still raises (contract enforcement is preserved, not weakened)
  - Bug merged_001: `:failed` (not `:partial`) with warnings still reports `degraded: false` on every consumer (the rule in `Run.Result.derive_degraded` stands)

- **Replay / recovery**
  - Bug 005: replay of a warning-bearing run continues to work exactly as today (no behaviour change on the replay path)
  - Bug merged_001: replay of a `:partial`-with-warnings run reproduces `degraded: true`

## TDD Sequence

1. **Bug 005 first (blocks everything else on live path)**: write a failing integration test that routes a real `%Warning{}` through `Run.Server → :pg → Observation.Server → ViewModel`; implement string-keyed emission (or boundary normalisation) to make it pass.
2. **Bug merged_001**: write failing tests for `:partial` terminal projection in ViewModel, Show, Index; implement event-type or payload disambiguation; update all three consumers.
3. **Bug 004**: write failing tests for re-delivered terminal events against `RunsLive.Index`; switch to direct assignment.
4. **Bug 009**: write a failing test for the event-log fallback path; extend `build_nodes/1`.
5. **Cross-layer consistency test module**: one test file that exercises all four fixes in combination.
6. **Validation**: per-app suites (liminara_radar, liminara_observation, liminara_web, liminara_core run+contracts), ruff, format, credo, dialyzer.

## Technical Notes

- Expected touch points:
  - `runtime/apps/liminara_core/lib/liminara/run/server.ex` — `warning_payload/1` (bug 005), `finish_run/2` event-type dispatch (merged_001), `rebuild_from_events/2` and `result_from_event_log/1` / `terminal_status/2` (new `"run_partial"` terminal)
  - `runtime/apps/liminara_core/lib/liminara/run.ex` — same dispatch pattern in the synchronous runtime if it owns its own terminal emission
  - `runtime/apps/liminara_observation/lib/liminara/observation/view_model.ex` — new `apply_typed(_, "run_partial", _, _)` clause (merged_001)
  - `runtime/apps/liminara_web/lib/liminara_web/live/runs_live/show.ex` — new `apply_event_type(_, "run_partial", _, _)` clause, update `derive_degraded_from_events/1` so the terminal event is recognised as `:partial` (merged_001); extend `build_nodes/1` to read `payload["warnings"]` (bug 009)
  - `runtime/apps/liminara_web/lib/liminara_web/live/runs_live/index.ex` — new `derive_degraded/2` pattern for `"run_partial"`, new `event_type_to_status/1` mapping, and switch `update_existing_run/3` to direct assignment (bug 004)
  - New or extended test files under `apps/liminara_observation/test/liminara/observation/` and `apps/liminara_web/test/liminara_web/live/runs_live/`
- **Bug 005 fix shape: wire-shape emission, not boundary normalisation.** `Run.Server.warning_payload/1` returns a string-keyed map so live `:pg` broadcasts and JSON-roundtripped replay present identical shape. Any test fixture or test helper that constructs warning payloads as atom-keyed maps must be updated to emit string-keyed maps. No normalisation layer.
- **Bug merged_001 fix shape: new `"run_partial"` terminal event type.** Event type is a 1:1 mirror of `Run.Result.status`. Every consumer that switches on event type grows a `run_partial` clause alongside its `run_completed` and `run_failed` clauses. No payload-field discriminator.
- **For bug 004, mirror `build_run_summary/3` exactly.** Don't invent a new helper. Direct assignment from the terminal payload.
- **For bug 009, match `observation_state_to_view_model/1`'s per-node shape** (`degraded: Map.get(node, :degraded, false)`, `warnings: …`). Same contract on both paths.
- No runtime contract changes beyond the `run_partial` event-type addition and the `warning_payload/1` key-shape fix. `Liminara.Warning` struct and validation are unchanged.

## Fixture migration rule (explicit)

The user has ruled twice in this epic that **backward compatibility with legacy fixtures or persisted data is not a concern at this stage**. Any fixture that becomes non-compliant with the spec after this milestone must be updated to match the new spec, not tolerated by the production code.

Concrete expectations:

- Test helpers that build `warning_payload`-shaped maps with **atom keys** must be updated to emit **string keys** after bug 005 lands. No defensive accept-both path in production code.
- Test fixtures that emit `"run_failed"` as the terminal event for a partial run must be updated to emit `"run_partial"` after bug merged_001 lands. Production consumers switch strictly on event type; a legacy `"run_failed"` fixture that meant `:partial` is now a broken fixture.
- Any on-disk event logs under `runs/` that assume old shape are treated as disposable. If a test depends on a checked-in fixture run, that fixture must be regenerated under the new shape.
- Consumers must **not** carry fallback clauses like `Map.get(payload, "warnings", %{})` or `"run_failed" when payload["outcome"] == "partial"` just to keep a legacy fixture working. If a fixture breaks, fix the fixture.

## Out of Scope

- Changes to `Liminara.Warning` struct or its `new/1` validation
- Changes to the severity taxonomy, warning contract shape, or `warning_summary` payload shape
- A2UI surfacing (E-21b / E-21c)
- Briefing HTML changes (M-WARN-03 complete)
- UI palette / layout / copy
- New Radar pack ops or Radar semantic adjustments
- CUE codification (E-21a ADR-OPSPEC-01)
- Retries, backoff, alerting, policy engines

## Dependencies

- M-WARN-01, M-WARN-02, M-WARN-03 complete (committed as `d39cb3e` + `629b902`)
- Ultrareview findings `bug_005`, `merged_bug_001`, `bug_004`, `bug_009` (task `r2fg1c81b`, 2026-04-20)

## Spec Reference

- `work/epics/E-19-warnings-degraded-outcomes/epic.md`
- `work/epics/E-19-warnings-degraded-outcomes/M-WARN-01-runtime-warning-contract.md`
- `work/epics/E-19-warnings-degraded-outcomes/M-WARN-02-observation-ui-surfacing.md`
- `work/epics/E-19-warnings-degraded-outcomes/M-WARN-03-radar-adoption.md`

## Downstream Consumers

- **E-21a ADR-OPSPEC-01** (warning contract → CUE): if bug merged_001 is fixed by adding a `run_partial` event type, ADR-OPSPEC-01 should codify the new event type alongside `run_completed` / `run_failed`. The payload-field alternative would not require an event taxonomy change.
- **E-21a ADR-CONTENT-01**: unaffected.
- No other downstream milestones depend on these fixes.
