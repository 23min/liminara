---
id: M-WARN-02-observation-ui-surfacing
epic: E-19-warnings-degraded-outcomes
status: complete
depends_on: M-WARN-01-runtime-warning-contract
---

# M-WARN-02: Observation + UI Surfacing

## Goal

Make warnings and degraded-success visible to operators through the observation projection, the runs LiveView UI, and the CLI run-output surfaces. After this milestone, a run with warning-bearing nodes can no longer look like a plain success in any operator-facing surface: the DAG carries a degraded badge, the node inspector exposes each warning's cause / severity / remediation / affected outputs, the run header shows an aggregated warning count, and the mix-task CLI summaries (`mix radar.run`, `mix demo_run`) print degraded information.

## Context

M-WARN-01 locked the runtime contract: `op_completed` events carry a `"warnings"` list, `run_completed` carries a `"warning_summary"`, and `Liminara.Run.Result` exposes `warning_count`, `degraded_nodes`, and a derived `degraded` boolean. The runtime side of warning surfacing is complete and frozen.

The observation and web layers do not yet consume any of that:

- `Liminara.Observation.ViewModel` projects `op_completed` into per-node `status`, `duration_ms`, `output_hashes`, and `cache_hit`. It drops the `warnings` list entirely.
- Per-node view state has a `decisions` collection but no `warnings` collection.
- Run-level view state exposes `run_status :: :pending | :running | :completed | :failed` with no `degraded` flag and no `warning_summary`.
- `Liminara.Observation.ViewModel.apply_typed("run_completed", ...)` ignores the new `warning_summary` payload.
- `LiminaraWeb.RunsLive.Show` and `LiminaraWeb.RunsLive.Index` have no rendering path for warnings, no degraded badges, and no inspector section for warning cause/severity/remediation.
- `Mix.Tasks.Radar.Run` and `Mix.Tasks.DemoRun` print run status and node counts but say nothing about degraded outcomes.

The consequence is that a Radar run with a placeholder summary (M-TRUTH-03 already emits a canonical warning for this case) still looks like a plain green success in the dashboard and in CLI output. M-WARN-02 fixes that without touching the runtime contract.

## Milestone Boundary

M-WARN-02 may implement:

- `Liminara.Observation.ViewModel` projection of `op_completed.warnings` into a per-node `warnings` list preserved alongside `decisions`
- Projection of `run_completed.warning_summary` into run-level `warning_count`, `degraded_nodes`, and derived `degraded` fields on the view model
- `LiminaraWeb.RunsLive.Show` rendering: run-header degraded badge + warning count, DAG node-level degraded indicator, node-inspector warning section (code, severity, summary, cause, remediation, affected outputs) separate from the decisions section
- `LiminaraWeb.RunsLive.Index` degraded indicator per run row
- CLI output additions in `Mix.Tasks.Radar.Run` and `Mix.Tasks.DemoRun`: degraded banner with warning count + comma-separated degraded node ids, and a non-zero exit only if the run itself failed (degraded is not a failure)
- Test coverage on the observation projection, LiveView rendering, and mix-task output

M-WARN-02 does not implement:

- Changes to the runtime contract locked in M-WARN-01 (no reshape of `warnings` or `warning_summary`, no new event types, no additional payload fields on `op_completed` or `run_completed`)
- Radar pack-level briefing annotation when placeholder summaries are rendered (owned by M-WARN-03)
- Any A2UI surface changes or new A2UI message types; A2UI rendering of warnings is deferred to the pack contribution contract work in E-21b / E-21c where SurfaceRenderer and the A2UI MultiProvider are owned
- Retry / backoff / alerting / CLI exit-code semantics beyond surfacing degraded status as text (degraded runs still exit 0; only failed runs exit non-zero)

## Acceptance Criteria

1. **`Liminara.Observation.ViewModel` preserves warnings**
   - Per-node view state gains a `warnings :: [map()]` field (default `[]`) populated from `op_completed.payload.warnings`; each entry preserves `code`, `severity`, `summary`, `cause`, `remediation`, and `affected_outputs`
   - Per-node view state gains `degraded :: boolean()` (true iff `warnings != []`)
   - Run-level view state gains `warning_count :: non_neg_integer()`, `degraded_nodes :: [String.t()]`, and derived `degraded :: boolean()` (true iff `run_status` is not `:failed` and `warning_count > 0`)
   - Run-level aggregation is populated directly from the `run_completed.payload.warning_summary` map; the payload is required and malformed/missing values are a contract violation, not a fallback case (M-WARN-01 guarantees the key is present on every run)
   - Decisions and warnings remain separate per-node collections; warnings are not folded into decisions and vice versa
   - `Liminara.Observation.ViewModel.init/3` initializes the new fields with zero values so code reading the projection never needs to guard for `nil`

2. **`LiminaraWeb.RunsLive.Show` renders degraded status**
   - The run header block shows a visible degraded badge and the `warning_count` when `degraded: true`; plain-success runs show the existing success badge with no warning surface
   - The DAG node rendering gains a per-node degraded indicator when the node has at least one warning; the indicator is visually distinct from the error/failed indicator
   - The node inspector panel gains a "Warnings" section, separate from and rendered alongside the existing "Decisions" section; each warning entry shows `code`, `severity`, `summary`, `cause`, `remediation`, and `affected_outputs`
   - The inspector warnings section is only rendered when the selected node has at least one warning; selecting a non-warning node does not show an empty warnings block
   - The run-level warning count links to or scrolls to the list of degraded node ids (scroll behavior is implementation-free; the list must be reachable without switching to the events tab)

3. **`LiminaraWeb.RunsLive.Index` marks degraded runs**
   - Each run row carries a degraded indicator when `warning_count > 0` and the run is not failed; the indicator is visually distinct from success and failure
   - The runs list does not need a separate degraded-only filter in this milestone (degraded filtering is deferred)

4. **Mix-task CLI surfaces degraded runs**
   - `mix radar.run` and `mix demo_run` print a `degraded` banner (single line, non-ambiguous wording) when the completed run has `warning_count > 0`, followed by `warning_count` and a comma-separated list of degraded node ids
   - When `warning_count == 0`, no degraded banner is printed and the CLI output is unchanged from the current behavior
   - Process exit code is unchanged: degraded runs still exit 0; failed runs continue to exit non-zero exactly as today

5. **Tests cover observation projection and LiveView rendering**
   - `apps/liminara_observation/test/liminara/observation/view_model_test.exs` gains tests for warning projection, run-level aggregation, degraded-derivation semantics, and fallback aggregation when `warning_summary` is absent from the source event
   - `apps/liminara_web/test/liminara_web/live/runs_live/show_test.exs` gains tests for run-header degraded badge, DAG degraded indicator, inspector warnings section (rendered when warnings exist, absent when they do not), and separation between warnings and decisions
   - `apps/liminara_web/test/liminara_web/live/runs_live/index_test.exs` gains a test for per-row degraded indicator presence
   - Mix-task output tests cover the degraded banner content and its absence on plain-success runs
   - Existing observation and LiveView suites continue to pass without relaxed assertions

## Tests

Use the repository TDD conventions. Required categories:

- **Happy path**
  - ViewModel: `op_completed` with one warning populates node `warnings`, sets node `degraded: true`; `run_completed.warning_summary` populates run-level fields
  - LiveView: degraded run renders degraded badge + warning count + node indicator + inspector warnings section
  - CLI: degraded run prints the banner with warning count and degraded node ids

- **Edge cases**
  - Zero-warning run: ViewModel stays in baseline shape, LiveView renders the existing success view, CLI prints no degraded banner
  - Node with multiple warnings: node `warnings` is a list of length N, inspector renders N entries, run-level count reflects N (not 1)
  - Multiple nodes with warnings: `degraded_nodes` lists every node once; run-level warning count sums node warnings; LiveView shows indicators on every affected node

- **Error cases**
  - `run_completed` event missing `warning_summary` or carrying a malformed one: projection raises — this is a runtime-contract violation that M-WARN-01 guarantees against, not a user-facing condition to paper over
  - `op_completed.warnings` missing the required warning fields: projection raises for the same reason
  - Mix task invoked on a failed run does not print the degraded banner; the failure banner takes precedence

- **Projection / rebuild parity**
  - ViewModel rebuilt from an event log yields the same `degraded`, `warning_count`, and `degraded_nodes` values a live projection would produce; tests cover both code paths

- **Format compliance**
  - Warning fields rendered in the inspector use the exact casing from the stored payload; severity is rendered as a human-readable label matching the atom taxonomy (`info`, `low`, `medium`, `high`, `degraded`)

## TDD Sequence

1. ViewModel first: write failing tests for warning projection, degraded derivation, fallback aggregation; extend `ViewModel` and its test helpers.
2. LiveView run header + DAG indicator: failing tests for the rendered badge/indicator; extend `RunsLive.Show` templates and assigns.
3. LiveView inspector warnings section: failing tests for the separate warnings block; extend the inspector component.
4. LiveView runs index degraded column: failing test; extend `RunsLive.Index`.
5. Mix-task CLI degraded banner: failing tests for both `mix radar.run` and `mix demo_run`; extend the task printers.
6. Run the focused observation, web, and radar suites; then run the umbrella `mix test` before asking for commit approval.

## Technical Notes

- Expected touch points:
  - `runtime/apps/liminara_observation/lib/liminara/observation/view_model.ex`
  - `runtime/apps/liminara_web/lib/liminara_web/live/runs_live/show.ex` (and any HEEX templates / components it renders)
  - `runtime/apps/liminara_web/lib/liminara_web/live/runs_live/index.ex`
  - `runtime/apps/liminara_web/lib/mix/tasks/demo_run.ex`
  - `runtime/apps/liminara_radar/lib/mix/tasks/radar.run.ex`
  - Corresponding `test/` files under each app
- Keep the projection additive. Do not remove or rename existing fields on `Liminara.Observation.ViewModel` — downstream consumers include live DAG rendering and A2UI providers that assume the current shape.
- The inspector warnings section should render each warning as a card or list entry with explicit field labels (Code, Severity, Summary, Cause, Remediation, Affected outputs). Resist the urge to collapse severity into a color badge only — cause and remediation are success criteria from the epic spec and must be visible without additional interaction.
- Decisions and warnings share a node inspector panel but must remain clearly distinct sections with their own headers. Do not merge them into a single "provenance" list.
- No backward-compatibility fallback for missing/malformed `warning_summary` or `op_completed.warnings`. M-WARN-01 guarantees the shape on every run; the projection trusts that contract and raises on violation rather than silently coping with legacy payloads.
- CLI output style should match the existing `mix radar.run` / `mix demo_run` output. Do not introduce a color or formatting dependency that isn't already used by the task.

## Out of Scope

- Runtime contract changes (locked by M-WARN-01)
- Radar briefing HTML/Markdown annotation when placeholder content is present (owned by M-WARN-03)
- A2UI warning rendering (owned by E-21b / E-21c)
- CLI exit-code changes for degraded runs — degraded is not a failure
- Observation filter UI for "only degraded runs" — deferred
- Warning surfacing in the timeline viewer events tab beyond the existing event list (events already render payload JSON; that's sufficient for this milestone)
- Per-warning acknowledgement, suppression, or dismissal UI

## Dependencies

- M-WARN-01 is complete: `Liminara.Warning`, `Warning.enforce_contract/2`, `Run.Result.warning_count/degraded_nodes/degraded`, `op_completed.warnings`, `run_completed.warning_summary` are all in place and test-covered
- Contracts: `docs/architecture/contracts/00_TRUTH_MODEL.md`, `docs/architecture/contracts/01_CONTRACT_MATRIX.md`
- Decision D-2026-04-02-015 (unified execution spec)

## Spec Reference

- `work/epics/E-19-warnings-degraded-outcomes/epic.md`
- `work/epics/E-19-warnings-degraded-outcomes/M-WARN-01-runtime-warning-contract.md`
- `work/epics/E-19-warnings-degraded-outcomes/M-WARN-01-tracking.md`

## Downstream Consumers

- **M-WARN-03** (Radar adoption) consumes the ViewModel and LiveView surface to verify the Radar placeholder-summary path is visibly degraded in the dashboard; no shape changes to the M-WARN-02 outputs are expected.
- **E-21a ADR-OPSPEC-01** codifies the wire-level warning contract. The ViewModel shape this milestone locks is the authoritative mapping from event payload to observation state; ADR-OPSPEC-01 should cite this milestone as the reference implementation for how consumers project warnings.
