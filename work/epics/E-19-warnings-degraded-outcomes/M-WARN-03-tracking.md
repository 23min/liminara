# M-WARN-03: Radar Adoption — Tracking

**Started:** 2026-04-17
**Branch:** `epic/E-19-warnings-degraded-outcomes`
**Spec:** `work/epics/E-19-warnings-degraded-outcomes/M-WARN-03-radar-adoption.md`
**Status:** implementation complete, awaiting commit approval

## Summary

M-WARN-03 makes Radar the first pack that fully honours the E-19
warning/degraded-outcome contract at the artifact layer as well as the
runtime layer. `radar_summarize` now annotates each summary with explicit
`degraded` / `degradation_code` / `degradation_note` fields;
`ComposeBriefing` propagates them into the briefing artifact with a root
`degraded` flag and a sorted `degraded_cluster_ids` list; `RenderHtml`
surfaces this in the rendered HTML via a top-of-briefing banner and a
per-cluster pill with stable CSS classes. An end-to-end pack test and a
replay-parity extension verify the round-trip.

## Acceptance Criteria

- [x] **AC1: `radar_summarize` marks per-cluster degraded summaries inside the artifact**
  - Placeholder and LLM-error paths populate `degraded: true` + concrete `degradation_code` +
    non-nil `degradation_note`. Success path emits explicit `false` / `nil` / `nil`.
  - Evidence: `runtime/python/src/ops/radar_summarize.py` (8 tests, all categories covered)
- [x] **AC2: `ComposeBriefing` propagates degraded annotations into the briefing artifact**
  - Every summary field (`summary`, `key_takeaways`, `degraded`, `degradation_code`, `degradation_note`)
    is fetched via `Map.fetch!` — no silent defaults. This matches the M-WARN-01 / M-WARN-02
    "no duct tape" principle applied to the whole summaries-artifact contract, not just the new fields.
  - Root `degraded` is `degraded_cluster_ids != []`; `degraded_cluster_ids` is sorted.
  - Evidence: `apps/liminara_radar/lib/liminara/radar/ops/compose_briefing.ex` + 20 tests
- [x] **AC3: `RenderHtml` shows a visible degraded banner + per-cluster pill**
  - Banner uses `<section class="briefing--degraded">`, pill uses `<span class="cluster--degraded">`.
  - Banner cites deduplicated `degradation_note` text and lists degraded cluster ids.
  - Non-degraded briefings render zero degraded elements (the CSS rule is present regardless,
    but no `class="…"` attribute references those classes in the body).
  - Evidence: `apps/liminara_radar/lib/liminara/radar/ops/render_html.ex` + 18 tests
- [x] **AC4: End-to-end pack test covers the degraded-but-successful path**
  - New file `apps/liminara_radar/test/liminara/radar/degradation_pipeline_test.exs` drives
    `RadarReplayTestPack` with `ANTHROPIC_API_KEY` removed and asserts: `status == :success`,
    `Run.Result.degraded == true`, `warning_count >= 1`, `"summarize" in degraded_nodes`,
    `briefing.degraded == true`, `degraded_cluster_ids` non-empty, HTML contains banner +
    pill + placeholder note text.
- [x] **AC5: Contract tests remain green**
  - liminara_radar 93/0, liminara_observation 272/0, liminara_web 198/0,
    liminara_core (run + contracts) 216/0, Python 79/0.

## TDD Sequence Progress

- [x] Task 15 (RED) — Python: failing tests for per-summary degraded fields
- [x] Task 16 (GREEN) — Python: add per-summary degraded fields (full Python suite 79/0 green)
- [x] Task 17 — Elixir: `ComposeBriefing` propagates per-cluster + root degraded flags (compose_briefing_test 18/0, pipeline_test 2/0)
- [x] Task 18 — Elixir: `RenderHtml` renders banner + per-cluster pill (render_html_test 18/0)
- [x] Task 19 — Elixir: end-to-end degradation pipeline test (`degradation_pipeline_test.exs`, 1/0)
- [x] Task 20 — Elixir: replay parity for degraded runs (replay_test 4/0)
- [x] Task 21 — Per-app validation suites (all green, details in Test Summary)

## Test Summary (targeted per-app suites, full umbrella not run due to known integration-test hang)

- `uv run --extra test pytest` (runtime/python) → **79 tests, 0 failures** (10.3s)
- `mix test apps/liminara_radar/test` → **97 tests, 0 failures** (47.2s; baseline was 75, added 22 across M-WARN-03 + pre-commit refinements)
- `mix test apps/liminara_observation/test` → **272 tests, 0 failures** (14.7s)
- `mix test apps/liminara_web/test` → **198 tests, 0 failures** (20.3s)
- `mix test apps/liminara_core/test/liminara/run apps/liminara_core/test/liminara/execution_contract_structs_test.exs apps/liminara_core/test/liminara/execution_runtime_contract_test.exs` → **216 tests, 0 failures** (19.0s)

## Validation Pipeline

- `mix format` on touched Elixir files → **pass** (all touched files reformatted)
- `mix credo --strict` → **7 refactoring + 1 consistency** issues, **all pre-existing** (same set as M-WARN-02 baseline; none of the M-WARN-03 touched files introduce any new credo findings)
- `mix dialyzer` → **2 warnings**, both pre-existing (`a2ui_provider.ex:95` callback type mismatch, `show.ex:618` unreachable pattern — unchanged from M-WARN-02)

## Coverage Notes

Branch-coverage audit performed on all new/changed source files:

- `runtime/python/src/ops/radar_summarize.py`
  - `if not clusters` → `test_empty_clusters`
  - `if not api_key or anthropic is None` — both disjuncts: `test_no_api_key_returns_placeholder` (no-key) + `test_missing_sdk_returns_placeholder_warning` (SDK None)
  - Per-cluster `try/except` — both sides covered by `test_haiku_called_per_cluster`/`test_summary_structure` (success) and `test_llm_error_returns_fallback` / `test_mixed_llm_success_and_error_per_summary_flags` (error)
  - `if not llm_failed` decision-append branch — success vs error branches exercised in the mixed test
  - `if warnings` result merge — no-warnings branch (happy) + warnings branch (error)
  - `"radar_summarize_llm_error" if llm_failed else None` ternary — both sides
  - `_placeholder_summaries` `if not api_key` vs else — both sides via the two placeholder tests

- `runtime/apps/liminara_radar/lib/liminara/radar/ops/compose_briefing.ex`
  - `Map.fetch!(summary_map, …)` — raise branch: `missing summary for a listed cluster raises`; happy: all other tests
  - Five `Map.fetch!(summary_data, …)` calls (`summary`, `key_takeaways`, `degraded`, `degradation_code`, `degradation_note`) — raise branches: five dedicated `malformed summaries (missing <field>) raises` tests; happy: all others
  - `degraded_cluster_ids != []` — true (degraded tests), false (happy-path test)

- `runtime/apps/liminara_radar/lib/liminara/radar/ops/render_html.ex`
  - `render_degraded_banner`: `if briefing["degraded"] == true` — true branch covered by mixed/all-degraded/banner-dedup/pill-note/N-of-M-counts tests; false branch covered by non-degraded + empty-non-degraded tests
  - `render_cluster_pill`: `if cluster["degraded"] == true` — true branch covered by mixed/all-degraded/pill-note/N-of-M-counts/nil-note-fallback tests; false branch covered by non-degraded tests (c0 in mixed case)
  - `render_cluster_pill`'s `case cluster["degradation_note"] do nil -> "Degraded"; note -> esc(note)` — both branches covered (nil-note-fallback test + pill-note test).

## Scope Adherence

- No runtime contract changes (per M-WARN-01 freeze). No touching `Liminara.Warning`, `Warning.enforce_contract/2`, `Run.Result` struct, `op_completed.warnings` shape, or `run_completed.warning_summary`.
- No observation projection or LiveView rendering changes (owned by M-WARN-02).
- No A2UI surface changes (deferred to E-21b / E-21c).
- No new warning codes, severities, or shapes.
- `ComposeBriefing` does NOT read from the event stream; degraded signal flows via artifact content only.
- `radar_dedup` safe-default path and fetch-error partial-ingestion paths were **not** extended in this milestone (see Deferrals).

## Deferrals

- **`radar_dedup` safe-default surfacing and fetch-error partial-ingestion surfacing** in the rendered HTML were not added. The spec's "optional" scope said to extend the same per-summary mechanism only if it generalises trivially (< ~1h). It does not:
  - `radar_dedup` operates on items before clustering; its degraded signal would need a new "item-level degraded flag" that propagates through `Cluster` / `Rank` into `ComposeBriefing`. That is a separate schema decision for the briefing contract (surface degraded items as a section? tag clusters containing degraded items?) and crosses into E-21a ADR-CONTENT-01 territory.
  - Fetch-error partial-ingestion is a source-level concern; the briefing already has a `source_health` section that shows errors. Extending that to a top-level banner would require deciding how per-source errors compose with per-cluster placeholder summaries in the same banner — another UX + schema decision.
  - Both extensions would cost more than an hour and the spec explicitly says to defer in that case.
  - The runtime-level warnings from both paths continue to surface via the observation layer (M-WARN-02) — this deferral only affects the rendered HTML surface.

## UI Judgment Calls (for review before commit)

1. **Banner palette**: reuses the amber/yellow palette chosen for M-WARN-02's degraded status badge (`#fff8e1` bg, `#ffd54f` border, `#6b5300` text). Consistent with the M-WARN-02 choice.
2. **Banner layout**: degraded banner renders below the header, above the clusters. Bulleted list of deduplicated `degradation_note` text followed by a "Degraded clusters: c0, c1" line so operators can quickly locate the affected clusters.
3. **Pill placement**: inline in the cluster `<h2>` heading, to the right of the cluster label. Stable class `cluster--degraded` on `<span>`.
4. **Banner text**: the primary title is a count-prefixed sentence — `⚠ N of M cluster summaries are degraded.` (per the spec's cited form, "3 of 7 cluster summaries are placeholders because the Anthropic API key is unavailable"). The bulleted list of deduplicated `degradation_note` text carries the *why*; the "Degraded clusters: c0, c1" line locates the affected clusters.
5. **CSS class naming**: `briefing--degraded` and `cluster--degraded` follow the BEM-like convention used by `status--degraded` in M-WARN-02. A shared stylesheet could unify them later.
6. **Existing pipeline_test.exs fixture migration**: the static `@summaries` literal in `pipeline_test.exs` was updated to include the new fields (non-degraded happy-path explicit values). Consistent with M-WARN-01's fixture migration principle.

## References

- Spec: `work/epics/E-19-warnings-degraded-outcomes/M-WARN-03-radar-adoption.md`
- Upstream: `work/epics/E-19-warnings-degraded-outcomes/M-WARN-02-tracking.md`
- Epic: `work/epics/E-19-warnings-degraded-outcomes/epic.md`
