---
id: M-WARN-03-radar-adoption
epic: E-19-warnings-degraded-outcomes
status: complete
depends_on: M-WARN-02-observation-ui-surfacing
---

# M-WARN-03: Radar Adoption

## Goal

Make Radar the first pack that fully honours the E-19 warning/degraded-outcome contract end to end: degraded summaries are not only surfaced in the runtime event stream and the dashboard (already true after M-WARN-01 / M-WARN-02) but also **visible in the rendered briefing itself**. After this milestone, a Radar run produced against a missing `ANTHROPIC_API_KEY` or a broken Anthropic endpoint cannot be mistaken for a fully-LLM-produced briefing by anyone reading the output — the HTML carries an explicit banner plus per-cluster placeholder annotations, and pack-level tests prove the round-trip.

## Context

M-TRUTH-03 already migrated the three known Radar silent-fallback paths onto canonical `OpResult.warnings`:

- `runtime/python/src/ops/radar_summarize.py` — placeholder-summary path (no API key / no SDK) and LLM-error path emit `radar_summarize_placeholder` / `radar_summarize_llm_error` warnings with `severity: degraded`
- `radar_dedup.py` — safe-default dedup mode emits a warning
- Fetch-error embedding emits a warning on partial ingestion

M-WARN-01 froze the runtime contract and guaranteed `warnings` is present on every `op_completed`. M-WARN-02 projected warnings into `Liminara.Observation.ViewModel`, the LiveView run inspector, the runs list, and the `mix radar.run` / `mix demo_run` CLI output. Warning visibility in the **observation layer** is therefore complete.

What is not yet true:

- The **briefing artifact itself** (`ComposeBriefing` output) contains no flag indicating that any of its cluster summaries were produced by a fallback path. The summary string may read like an LLM summary but is actually a title-list placeholder.
- The **rendered HTML briefing** (`RenderHtml` output) shows no visible degraded banner and no per-cluster "this is a placeholder" marker. A reader opening the briefing cannot distinguish LLM-authored from placeholder content.
- There is no end-to-end pack test that covers the degraded-but-successful path as a first-class scenario (existing pack tests assume the happy path or hard failure).

M-WARN-03 closes those three gaps. It is the smallest milestone in E-19 because the runtime-level work is already done.

## Milestone Boundary

M-WARN-03 may implement:

- Per-summary `degraded` metadata inside the `summaries` artifact produced by `radar_summarize` (Python)
- Per-cluster degraded flags carried through `ComposeBriefing` into the `briefing` artifact
- Run-level `degraded` + `degradation_note` fields in the briefing root map
- Rendered-HTML degraded banner in `RenderHtml` at the top of the briefing, plus a per-cluster degraded pill / note when the cluster carried placeholder content
- A dedicated Radar pack test that exercises the degraded-summary path end to end: run Radar with Anthropic access disabled, assert warnings land, the briefing artifact carries the degraded flag, the rendered HTML contains the banner and per-cluster marker, and replay reproduces the annotation
- Optional: similar surfacing for `radar_dedup` safe-default and fetch-error partial-ingestion, if the same mechanism extends cleanly

M-WARN-03 does not implement:

- Runtime contract changes (locked by M-WARN-01 and verified by M-WARN-02)
- Observation projection or LiveView rendering changes (owned by M-WARN-02)
- New warning codes, severities, or shapes beyond what M-TRUTH-03 already emits
- Retry / remediation / alerting
- Any work in non-Radar packs (VSME is Phase 6; admin-pack is E-22)
- A2UI surface annotation — deferred to E-21b / E-21c
- CUE codification of the Radar-level degraded annotation schema (that is the adjacent ADR-OPSPEC-01 / ADR-CONTENT-01 concern in E-21a)

## Acceptance Criteria

1. **`radar_summarize` marks per-cluster degraded summaries inside the artifact**
   - The `summaries` output is a JSON list where each entry is now a map with `cluster_id`, `summary`, `key_takeaways`, **and**:
     - `degraded :: boolean` (true on placeholder / LLM-error paths)
     - `degradation_code :: string | nil` (e.g. `"radar_summarize_placeholder"`, `"radar_summarize_llm_error"`; `nil` on success)
     - `degradation_note :: string | nil` (short human-readable note reusing the warning `summary` text)
   - Non-degraded summaries emit `degraded: false, degradation_code: nil, degradation_note: nil` (explicit, not absent — same "no duct tape" principle as M-WARN-01)
   - The existing `radar_summarize_placeholder` / `radar_summarize_llm_error` warnings continue to emit on the event stream unchanged; this milestone is additive at the artifact level
   - Python tests in `runtime/python/src/ops/` cover happy, placeholder, and LLM-error paths for the new fields

2. **`ComposeBriefing` propagates degraded annotations into the briefing artifact**
   - Each cluster in `briefing["clusters"]` gains `degraded: boolean`, `degradation_code: string | nil`, `degradation_note: string | nil` populated from the summary map
   - The briefing root gains `degraded: boolean` (true iff any cluster is degraded) and `degraded_cluster_ids: [string]` (sorted list of cluster ids with `degraded: true`)
   - `ComposeBriefing`'s determinism class and replay policy are unchanged; the added fields are deterministic with respect to inputs
   - Elixir tests in `apps/liminara_radar/test/liminara/radar/ops/compose_briefing_test.exs` cover: all-success clusters, one degraded cluster, all degraded clusters

3. **`RenderHtml` shows a visible degraded banner + per-cluster pill**
   - When `briefing.degraded == true`, the rendered HTML contains a prominent top-of-document banner that states (1) the briefing contains placeholder or fallback content, (2) the human-readable degradation notes (deduplicated), and (3) a stable CSS class (e.g. `briefing--degraded`) so downstream styling hooks exist
   - Each degraded cluster in the rendered HTML carries a visible inline pill or badge near the cluster heading (e.g. `⚠ Placeholder summary`), labelled by `degradation_note`, with a stable CSS class (e.g. `cluster--degraded`)
   - Non-degraded briefings render with zero degraded surface (no empty banner, no empty pills)
   - Elixir tests in `apps/liminara_radar/test/liminara/radar/ops/render_html_test.exs` cover: non-degraded (no banner/pill), mixed (banner + pill on affected clusters only), all-degraded (banner + pill on every cluster)

4. **End-to-end pack test covers the degraded-but-successful path**
   - A new test under `apps/liminara_radar/test/liminara/radar/pipeline_test.exs` (or a dedicated `degradation_pipeline_test.exs`) drives Radar with Anthropic access deliberately disabled
   - The test asserts:
     - the run reaches terminal `:success` (degraded is not failure)
     - `Run.Result.warning_count >= 1` and the `summarize` node is in `Run.Result.degraded_nodes`
     - the `briefing` artifact has `degraded: true` and `degraded_cluster_ids != []`
     - the rendered HTML contains the banner and the per-cluster pill
   - A replay test confirms the degraded annotation survives replay (warnings re-emitted via `Decision.Store.get_warnings/2`, briefing and HTML regenerated from the same inputs with the same degraded fields)

5. **Contract tests remain green**
   - Existing Radar pack tests continue to pass without relaxed assertions
   - Existing ViewModel / LiveView / CLI tests (from M-WARN-02) continue to project the degraded run correctly — no projection-layer regression
   - `Liminara.Run.Result.degraded` is true for the degraded run, false for the happy-path run

## Tests

Use the repository TDD conventions. Required categories:

- **Happy path**
  - Radar run with Anthropic access available: no warnings, no degraded flags in artifact, no banner in HTML
  - Radar run with Anthropic disabled: warnings on summarize node, `briefing.degraded == true`, HTML banner present

- **Edge cases**
  - Mixed clusters: some LLM-generated, some placeholder (e.g. LLM errors on a subset) — per-cluster flags match, banner lists the degraded clusters only
  - All clusters degraded — every cluster carries a pill, banner summarises once
  - Zero clusters — briefing still renders; `briefing.degraded == false`; no banner

- **Error cases**
  - Malformed summaries artifact (missing the new degraded fields) — `ComposeBriefing` raises (no backward-compat fallback; consistent with M-WARN-01 / M-WARN-02)

- **Round-trip / replay**
  - Replay of a degraded run reproduces identical `summaries`, `briefing`, and rendered HTML artifacts; warnings re-emit via `Decision.Store.get_warnings/2`
  - `Run.Result` on replay has `degraded: true` with the same `warning_count` and `degraded_nodes`

- **Format compliance**
  - Briefing JSON has stable key ordering for the new fields
  - HTML banner and pill use stable CSS class names so downstream styling can be applied

## TDD Sequence

1. Python tests + implementation: fail-first tests for the new per-summary fields in `radar_summarize` placeholder and LLM-error paths; add the fields.
2. Elixir tests + implementation: fail-first tests for `ComposeBriefing` cluster-level + root-level degraded fields; add the propagation.
3. Elixir tests + implementation: fail-first tests for `RenderHtml` banner + per-cluster pill; add the rendering.
4. End-to-end pack test: fail-first `degradation_pipeline_test.exs` exercising the full Radar pipeline with Anthropic disabled; no new runtime code expected — this test just proves the integration.
5. Replay test extension: add a degraded-run replay assertion to the existing Radar replay suite.
6. Validation: `mix test apps/liminara_radar/test`, `mix test apps/liminara_core/test/liminara/run`, `mix test apps/liminara_observation/test`, `mix test apps/liminara_web/test`. Per-app per the new testing rules — no full umbrella.

## Technical Notes

- Expected touch points:
  - `runtime/python/src/ops/radar_summarize.py` (add per-summary degraded fields)
  - Python tests for `radar_summarize`
  - `runtime/apps/liminara_radar/lib/liminara/radar/ops/compose_briefing.ex` (propagate degraded into briefing)
  - `runtime/apps/liminara_radar/lib/liminara/radar/ops/render_html.ex` (banner + pill rendering)
  - `runtime/apps/liminara_radar/test/liminara/radar/ops/compose_briefing_test.exs` (extend)
  - `runtime/apps/liminara_radar/test/liminara/radar/ops/render_html_test.exs` (extend)
  - `runtime/apps/liminara_radar/test/liminara/radar/pipeline_test.exs` or a new `degradation_pipeline_test.exs` (end-to-end)
  - `runtime/apps/liminara_radar/test/liminara/radar/replay_test.exs` (extend with degraded-run replay)
- Keep the `summaries` artifact JSON additive — existing consumers (dashboard, any analysis scripts) should continue to read the current fields without modification.
- Do NOT read warnings from the event stream inside `ComposeBriefing`. Warnings are runtime-layer concerns; artifact-level degraded annotations are artifact-layer data, and the briefing must be deterministic from its inputs. Pass the degraded signal as artifact content only.
- CSS class names (`briefing--degraded`, `cluster--degraded`) should match the convention used by the M-WARN-02 LiveView classes (`status--degraded`) so any shared stylesheet can be unified later.
- The banner text should cite **why** the briefing is degraded (e.g. "3 of 7 cluster summaries are placeholders because the Anthropic API key is unavailable"), not just "degraded". Cause-focused operator language is the same principle applied in the inspector Warnings section.
- No new warning codes, severities, or shapes are added here. The milestone consumes what M-TRUTH-03 / M-WARN-01 locked.

## Out of Scope

- Runtime contract changes (M-WARN-01)
- Observation / LiveView / CLI surfacing (M-WARN-02)
- A2UI surfacing of degraded briefings (E-21b / E-21c)
- CUE schema codification of the briefing degraded annotation (E-21a ADR-CONTENT-01)
- Non-Radar packs
- Retries, backoff, alerting, policy engines
- Surfacing `radar_dedup` safe-default or fetch-error degraded artifacts in the rendered HTML — deferred unless the `summarize` path mechanism extends trivially to those ops. If extending costs more than an hour of work, defer to a follow-on milestone.

## Dependencies

- M-WARN-01 is complete (runtime contract frozen; `warnings` always present on `op_completed`)
- M-WARN-02 is complete (observation projection + LiveView + CLI surfacing)
- M-TRUTH-03 is complete (Radar fallback paths already emit canonical warnings)
- Radar pack behaviour and current test structure under `apps/liminara_radar/test/`

## Spec Reference

- `work/epics/E-19-warnings-degraded-outcomes/epic.md`
- `work/epics/E-19-warnings-degraded-outcomes/M-WARN-01-runtime-warning-contract.md`
- `work/epics/E-19-warnings-degraded-outcomes/M-WARN-02-observation-ui-surfacing.md`
- `work/done/E-20-execution-truth/M-TRUTH-03-radar-semantic-cleanup.md`

## Downstream Consumers

- **E-21a ADR-OPSPEC-01** (warning contract → CUE): M-WARN-03 does not change the warning contract shape. ADR-OPSPEC-01 can land with the contract as frozen by M-WARN-01.
- **E-21a ADR-CONTENT-01** (artifact content-type namespace rules): the Radar briefing's new degraded fields are a concrete example for how artifact schemas should carry degraded annotation. ADR-CONTENT-01 should cite this milestone as a reference implementation.
- **E-21d Radar extraction**: when Radar moves to an external pack, the briefing schema introduced here goes with it. No re-design expected.
