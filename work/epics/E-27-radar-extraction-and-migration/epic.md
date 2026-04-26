---
id: E-27
parent: E-21
phase: 5c
status: planning
depends_on:
  - E-25
  - E-26
---

# E-21d: Radar Extraction + Migration

## Goal

Move Radar entirely out of the Liminara repo into an external `radar-pack` submodule repo, using the contract (E-21a), runtime (E-21b), and DX (E-21c) that the prior sub-epics shipped. When E-21d is done:

- The Liminara repo contains **zero Radar-specific code**: no `liminara_radar/` app, no `radar_*.py` ops, no `radar_live/` LiveView pages, no Radar routes, no Radar fixtures.
- The `radar-pack` submodule repo is a valid, manifest-driven Liminara pack using `liminara_pack_sdk` (Elixir) for plan ergonomics, `liminara-pack-sdk` (Python) for Python ops, and YAML surface declarations rendered via `liminara_widgets` widgets.
- Radar's end-to-end test, replay test, and briefing UI all pass against the extracted pack, exercised through `liminara-test-harness`.
- Pack authoring documentation is finalized with Radar as the canonical "mixed-language advanced pack" reference.
- Admin-pack (E-22) can start against a hardened contract.

## Context

Radar has been Liminara's in-tree test case throughout Phases 4 and 5. It grew inside the monorepo because there was no pack-contribution contract yet. Now that E-21a/b/c have produced one, Radar is both the primary proof that the contract works and the proof that packs can genuinely live outside Liminara.

The extraction is **the acceptance test for the entire E-21 initiative**. If moving Radar out is painful — if the contract has gaps, if the runtime lacks a necessary shape, if the SDK is missing an ergonomic, if a widget is wrong — this is where the failure surfaces. Going back to E-21a/b/c to fix it is cheap compared to going back from E-22 (admin-pack) to fix it.

## Scope

### In scope

- **Create the `radar-pack` submodule repo** (github.com/23min/radar-pack or similar). Initialize with the conventional layout from ADR-LAYOUT-01: `pack.yaml` at root, `lib/radar_pack/`, `python/src/radar_pack/ops/`, `surfaces/`, `test/`, `tests/`, `fixtures/`.
- **Move Radar Elixir code**: `runtime/apps/liminara_radar/` → `radar-pack` submodule's `lib/radar_pack/`. Update internal module references; adopt `liminara_pack_sdk` (Elixir) where it reduces boilerplate; keep behavior unchanged.
- **Move Radar Python ops**: `runtime/python/src/ops/radar_*.py` → `radar-pack/python/src/radar_pack/ops/`. Register via manifest; no protocol changes.
- **Move Radar LiveView pages and routes**: `runtime/apps/liminara_web/lib/liminara_web/live/radar_live/` → `radar-pack` as declarative surfaces rendered via `liminara_widgets`. Radar's UI is refactored to express every view through `SurfaceRenderer` + widget compositions. **No pack-shipped LiveView modules, and no pack-registered custom routes** — that escape hatch is explicitly deferred (see parent epic "Explicitly deferred" table). If a Radar view genuinely cannot be expressed with the current widget catalog, the fix is to amend E-21c (add the missing widget) rather than open a LiveView escape hatch.
- **Move Radar's scheduler**: Radar's GenServer scheduler is replaced by a `:cron` trigger declaration in `pack.yaml`, served by `TriggerManager` from E-21b.
- **Move Radar fixtures and test data** that are pack-specific to the submodule. Keep only truly Liminara-runtime fixtures in-tree.
- **Bump the submodule pointer in Liminara** to a pinned commit of `radar-pack` once extraction milestones merge there.
- **Add `radar-pack` to Liminara's default deployment config** so the development/test Liminara instance loads it.
- **Run Radar's full test suite against the extracted form** — unit, integration, replay, and UI tests all pass.
- **Finalize `docs/guides/pack-authoring.md`** with Radar cited as the advanced mixed-language reference alongside `examples/file_watch_demo` as the simple pure-Python reference.
- **Write the E-22 readiness signoff** (`docs/analysis/admin-pack-readiness.md`) — a short curated list of the load-bearing capabilities admin-pack's author (you) will need on day 1 of E-22, each marked as shipped / deferred-with-trigger / shipped-differently-than-expected. **This is a readiness signoff, not a requirements-completeness audit** — admin-pack's architecture docs are ~3,000 lines of prose that were not authored as a structured requirements list, and extracting one at E-21d wrap-time is work that doesn't pay back (the real validation is building admin-pack in E-22, not reviewing paper). The checkpoint's purpose is to unblock E-22 with an auditable artifact: the admin-pack author can start E-22 and reference "what I thought I needed" vs "what shipped."
- **Write the schema-evolution doc** (`docs/governance/schema-evolution-policy.md`) explaining the CUE-backed backward-compat discipline for future pack-schema changes.
- **Roadmap and CLAUDE.md "Current Work" housekeeping** reflecting completion of Phase 5c pack-contract work.

### Out of scope

- Any further runtime-plumbing work (done in E-21b).
- Any further SDK or widget work (done in E-21c). If extraction reveals missing capabilities, reviewer decides whether to open a late-breaking E-21c addendum or defer to follow-up.
- Admin-pack itself (E-22).
- Rewriting Radar's Python op internals. Only their location and packaging change; the op logic stays as-is.
- Provider op library extraction (`liminara-ops-pdf`, etc.) — deferred; Radar vendors what it needs.

## Constraints

Shared E-21 constraints apply. Sub-epic-specific:

- **Radar must work at every merge point.** Staged extraction: submodule dogfood (M-PACK-D-01a, no code moves), atomic flip of Elixir + Python + scheduler + deploy config (M-PACK-D-01b), then surfaces + routes (M-PACK-D-02). At each merge point, Radar's end-to-end + replay + briefing UI all pass. If any of these fail, the milestone is not done.
- **No compatibility shims.** Extraction is a one-way move. There is no in-tree fallback for Radar after M-PACK-D-02. The shim policy (`docs/governance/shim-policy.md`) applies: any temporary compatibility layer has a named removal trigger. Two named shims exist within E-21d's window: (1) the E-21b-generated `pack.yaml` shim, removed in M-PACK-D-01b (record: E-21b Compatibility shims section); (2) the Radar-specific filters in `liminara_web` that survive M-PACK-D-01b as the D-01b → D-02 bridge, removed in M-PACK-D-02 (record: M-PACK-D-02 spec must carry its own `## Compatibility shims` section naming this bridge when authored).
- **Submodule-first discipline.** Changes land in the `radar-pack` repo first (with its own PR + review). The submodule pointer bump in Liminara is a separate PR that references the `radar-pack` commit hash.
- **No behavior changes.** Radar works exactly as it does today from a user perspective. No new features, no tweaks to clustering thresholds, no UI changes. Pure extraction.
- **Contract gaps found during extraction go back to E-21a.** If extraction reveals a schema that cannot represent Radar's real needs, the correct action is to amend an E-21a ADR (+ CUE schema + fixtures) and update downstream code. Do not hack around the gap in E-21d.

## Success criteria

Success criteria are grouped by owning milestone to make the three-milestone split explicit. M-PACK-D-01 is split into **M-PACK-D-01a (dogfood — submodule exists, manifest validates, in-tree Radar unchanged)** and **M-PACK-D-01b (the flip — Elixir + Python + scheduler + deploy config + shim deletion, all atomically)** — see "Milestones" table below.

**M-PACK-D-01a — Submodule dogfood (retires repo-creation risk with a green signal):**
- [ ] `radar-pack` submodule repo exists at the chosen GitHub location (e.g. `github.com/23min/radar-pack`), initialized with conventional layout per ADR-LAYOUT-01: `pack.yaml` at root, `lib/radar_pack/` skeleton, `python/src/radar_pack/ops/` skeleton, `surfaces/` skeleton, `test/`, `tests/`, `fixtures/`.
- [ ] `radar-pack`'s canonical authored `pack.yaml` passes `cue vet` against the ADR-MANIFEST-01 schema.
- [ ] `radar-pack`'s surface declarations pass `cue vet` against the ADR-SURFACE-01 schema.
- [ ] Liminara's `PackLoader` can load the submodule's `pack.yaml` in a **validation-only test** — manifest round-trips through CUE validation and schema-version compat check (per E-21b acceptance criterion), `PackRegistry.get/1` returns it with the declared shape. **The submodule is not yet referenced from production deploy config.** Purpose: prove the submodule's layout, manifest, and cross-repo wiring work end-to-end before any code migration.
- [ ] In-tree Radar continues to run through its current path unchanged. Shim `pack.yaml` (from M-PACK-B-01b) still lives in-tree. No deploy-config changes. No code moves. D-01a is "the submodule exists and Liminara can see it," not "Radar runs from it."
- [ ] Repo access / branch protection / submodule pointer wiring is documented in M-PACK-D-01a's tracking doc so D-01b doesn't need to debug logistics.
- [ ] **Radar-references pre-audit** lands as `work/epics/E-21-pack-contribution-contract/radar-references.md` before M-PACK-D-01a is considered done. The audit enumerates every in-tree Radar reference with file:line anchors and classifies each into one of four buckets:
  - **Moves with Radar** — belongs in `radar-pack` (e.g. `runtime/apps/liminara_radar/`, `runtime/python/src/ops/radar_*.py`, `runtime/data/radar/lancedb/` — with an explicit migration story for the data directory: does LanceDB data move with the pack, stay in-tree as operator-managed state, or get re-populated from scratch in the extracted pack?).
  - **Stays in-tree as pack-config entry** — the Radar entry in `config :liminara, :packs` after flip; the `config :liminara_radar, lancedb_path: …` blocks in `config/{dev,test,prod}.exs` (if they remain as deploy-time config).
  - **D-01b → D-02 bridge (planned temporary)** — Radar-specific filters and layout in `liminara_web` that survive the flip and get removed in D-02 (e.g. Radar filter in `runs_live/index.ex`, `/radar/…` nav link in `app.html.heex`, the three `/radar/…` routes in `router.ex`, Radar routes visible in layouts). Each item in this bucket becomes a **D-02 removal checklist entry** (see M-PACK-D-02 bridge-removal criterion).
  - **Surprise — needs decision** — any reference that doesn't fit the three above (e.g. incidental references in `liminara_core/lib/liminara/pack.ex` / `op.ex` / `run/cli.ex` that may be docstring / example / load-bearing; load-bearing surprises require a docket entry and a decision before D-01b starts).
  
  Audit baseline (produced during 2026-04-23 ultrareview; to be re-run and formalized at M-PACK-D-01a time): 10 Elixir files in `liminara_core` / `liminara_observation` / `liminara_web` reference Radar; 3 config blocks (`dev.exs`, `test.exs`, `prod.exs`); 3 LiveView routes in `router.ex`; 1 umbrella dep in `liminara_web/mix.exs`; 9 Python ops; the full `liminara_radar/` app; the `data/radar/lancedb/` data directory. Expect the formal audit to find ~1–3 additional references from the "surprise" bucket. If a load-bearing surprise is found (e.g. Radar-specific load-order assumption in `liminara_core`), D-01b is paused until the surprise is classified and either migrated into M-PACK-D-01b's scope or named a D-02 bridge.

**M-PACK-D-01b — The flip (atomic cutover: Radar runs from the submodule):**
- [ ] Elixir code moved: `runtime/apps/liminara_radar/` → `radar-pack/lib/radar_pack/`. Internal module references renamed. `liminara_pack_sdk` (Elixir) adopted where it reduces boilerplate. Behaviour unchanged.
- [ ] Python ops moved: `runtime/python/src/ops/radar_*.py` → `radar-pack/python/src/radar_pack/ops/`. `pyproject.toml` in `radar-pack` declares the ops; manifest registers them. Wire protocol unchanged.
- [ ] Radar's GenServer scheduler (`Liminara.Radar.Scheduler`) deleted. Scheduling moves to a `:cron` trigger declaration in `radar-pack/pack.yaml`, served by `TriggerManager` from M-PACK-B-03.
- [ ] Radar fixtures and test data that are pack-specific move to the submodule. Only truly Liminara-runtime fixtures stay in-tree.
- [ ] Shim `pack.yaml` deleted from in-tree per its M-PACK-B-01b Compatibility-shims record (removal trigger satisfied). Submodule's authored `pack.yaml` becomes the only one.
- [ ] Liminara's dev/test deployment config loads `radar-pack` by submodule path; production-like configs load it by git ref. No more in-tree Radar app.
- [ ] In-tree `runtime/apps/liminara_radar/` directory and `runtime/python/src/ops/radar_*.py` files are **deleted**, not kept as references.
- [ ] Radar's end-to-end pipeline test (fetch → extract → dedup → cluster → rank → render → briefing) passes against the extracted pack via `liminara-test-harness`.
- [ ] Radar's replay test (discovery → replay → identical artifacts) passes against the extracted pack.
- [ ] Radar's briefing UI works in the browser when a Liminara instance has `radar-pack` in its deployment config. UI stays in-tree temporarily (remaining Radar-specific filters in `liminara_web` are the D-01b → D-02 bridge; explicitly documented).
- [ ] Radar's cron scheduling works via `TriggerManager`'s `:cron` trigger (no bespoke scheduler in the pack or runtime).
- [ ] UI parity for scheduler observability: the Radar briefing UI still displays next-scheduled-run, last-run, and a manual fire-now control, sourced from `TriggerManager`'s observation API (per E-21b + ADR-TRIGGER-01). Losing these UI affordances is a behavior change and blocks wrap.

**M-PACK-D-02 — UI extraction + wrap-up (unchanged from prior plan):**
- [ ] Liminara's repo contains zero Radar-specific code (final cleanup pass after UI extraction):
  - [ ] no `runtime/apps/liminara_radar/` app directory (already gone after D-01b)
  - [ ] no `radar_*.py` files under `runtime/python/src/ops/` (already gone after D-01b)
  - [ ] no `radar_live/` directory under `liminara_web/live/`
  - [ ] no Radar-specific route in `liminara_web`'s router
  - [ ] no Radar-specific test fixtures in-tree beyond generic shared ones
  - [ ] no Radar-specific filters in `liminara_web` (the D-01b → D-02 bridge is removed here). **Removal checklist source**: every entry in the pre-audit's "D-01b → D-02 bridge" bucket (see `work/epics/E-21-pack-contribution-contract/radar-references.md`, authored in M-PACK-D-01a) must be removed; M-PACK-D-02 reviewer verifies each bridge-bucket entry has been addressed before wrap. If the audit identified surprise-bucket entries that were provisionally classified as bridge items, those are also removed here.
  - [ ] no Radar mentions in `liminara_core` / `liminara_observation` / `liminara_web` code (except as a deployment-config entry in dev/test)
- [ ] Widget-catalog gap-analysis table is M-PACK-D-02's first acceptance criterion (per Finding 9 / 2026-04-23 review): Radar render element → widget composition → any gap. Review blocks on absence.
- [ ] `radar_live/` LiveView pages refactored into declarative surface YAMLs rendered by `liminara_widgets` widgets via `SurfaceRenderer`. Concrete mapping per Technical direction (2).
- [ ] Pack authoring guide finalized at `docs/guides/pack-authoring.md`, walks zero-to-running in under one page, cites both `file_watch_demo` and `radar-pack`.
- [ ] **E-22 readiness signoff** at `docs/analysis/admin-pack-readiness.md`: a short curated list (~10–20 items) of the load-bearing capabilities admin-pack's author will need for E-22 day 1, each marked **shipped** (with specific E-21 milestone + validation reference, e.g. "multi-workflow plan dispatch — M-PACK-B-03, validated by admin-pack-shape proxy"), **deferred** (with named removal trigger, e.g. "`pdf_viewer` widget — demand-driven; E-22 M-<first admin-pack milestone> or earlier named consumer"), or **shipped-differently** (if the shipped capability diverges from what admin-pack's architecture docs assumed — e.g. "FS-scope is advisory-declaration-only in MVP, not runtime-syscall-hard-enforced; admin-pack deployments must not rely on runtime conformance until E-12"). **Explicitly not required: exhaustive requirements extraction** against the ~3,000 lines of admin-pack architecture prose. The author curates the list from prior knowledge of admin-pack; the checkpoint reflects "what I think I need" paired with "what shipped." Admin-pack's author (you, as admin-pack owner) signs off on the checkpoint before wrap — this is the strongest signal that E-22 can start; requirements-completeness auditing is explicitly deferred to E-22 development, where real gaps will surface as building pressure rather than paper review.
- [ ] Schema-evolution doc at `docs/governance/schema-evolution-policy.md` explains the CUE-backed backward-compat discipline.
- [ ] Roadmap updated: Phase 5c pack-contract work marked complete; admin-pack (E-22) listed as ready to start.
- [ ] `CLAUDE.md` "Current Work" section updated to reflect the post-E-21 state.
- [ ] `docs/architecture/indexes/contract-matrix.md` — Radar-dedup row removed. Rationale: once Radar is extracted, dedup is a pack-owned contract in an external repo, not a runtime-owned surface. The matrix tracks what the runtime owns. Same pattern will apply to future extracted packs (admin-pack, VSME, House Compiler). Rule reference: `.ai-repo/rules/liminara.md` → Contract matrix discipline.

## Milestones

| ID | Title | Summary |
|---|---|---|
| **M-PACK-D-01a** | Submodule dogfood + Radar-references pre-audit | Create `radar-pack` submodule repo with conventional layout per ADR-LAYOUT-01. Author the canonical `pack.yaml` (manifest + surface YAMLs). `PackLoader` validates the submodule's manifest through a validation-only test. **Ship `work/epics/E-21-pack-contribution-contract/radar-references.md`** enumerating every in-tree Radar reference and classifying each (moves-with-Radar / stays-as-pack-config / D-01b → D-02 bridge / surprise-needs-decision); includes data-directory migration story. **In-tree Radar runs unchanged; shim `pack.yaml` still in-tree; no deploy-config changes; no code moves.** Purpose: retire repo-creation risk + retire surprise-discovery risk with a green signal before any migration. Comparable in size to M-PACK-B-01a. |
| **M-PACK-D-01b** | The flip — Radar extracts atomically | Move `liminara_radar/` Elixir app → `radar-pack/lib/radar_pack/`. Move `radar_*.py` Python ops → `radar-pack/python/src/radar_pack/ops/`. Replace Radar's GenServer scheduler with a `:cron` trigger declaration (consumes B-03). Delete shim `pack.yaml` (satisfies its removal trigger). Flip deploy config to submodule path. Delete in-tree `runtime/apps/liminara_radar/` and `runtime/python/src/ops/radar_*.py`. Radar e2e + replay + briefing UI pass via `liminara-test-harness`. UI stays in-tree temporarily (Radar-specific filters in `liminara_web` are the D-01b → D-02 bridge). |
| **M-PACK-D-02** | Radar surfaces + routes extraction + docs wrap-up | Refactor `radar_live/` LiveView pages into declarative surface YAMLs rendered by `liminara_widgets` widgets via `SurfaceRenderer`. **M-PACK-D-02's spec must include a widget-catalog gap-analysis table as its first acceptance criterion** (Radar render element → widget composition → any gap); review blocks on absence. No pack-shipped LiveView modules; no pack-registered routes. If a gap is identified, amend E-21c to add the missing widget rather than open a LiveView escape hatch. Remove remaining Radar-specific filters in `liminara_web` (the D-01b bridge). Bump submodule pointer. Finalize pack authoring guide. Write **E-22 readiness signoff** (short curated list, admin-pack-author signoff — explicitly not a requirements-completeness audit). Write schema-evolution doc. Roadmap + CLAUDE.md housekeeping. Liminara repo is free of Radar code. |

## Technical direction

1. **Staged extraction, validated at each stage.** Three milestones, each with a distinct green signal: **M-PACK-D-01a** creates the submodule, authors its canonical `pack.yaml`, and proves `PackLoader` can load it in validation-only mode — retiring repo-creation risk (admin access, branch protection, cross-repo wiring) before any code migration. **M-PACK-D-01b** is the atomic flip: Elixir app + Python ops + scheduler replacement + deploy-config cutover + shim deletion, all together, Radar runs end-to-end from the submodule via the test harness. UI stays in-tree temporarily rendering via the extracted pack. **M-PACK-D-02** moves the UI and wraps up docs. This sequencing retires repo-creation risk in D-01a, cuts over atomically in D-01b, and leaves UI + docs for D-02 — matching the sizing precedent of M-PACK-B-01a/B-01b (see Finding 11 / 2026-04-23 ultrareview).
2. **Declarative surfaces only — no LiveView fallback.** Every Radar view is expressed as a declarative surface using `liminara_widgets` widgets from the MVP catalog (expanded to five widgets per E-21c after the 2026-04-23 widget-catalog gap analysis). Concrete mapping of Radar's current views (verified against `runtime/apps/liminara_web/lib/liminara_web/live/radar_live/` at plan time):
   - **Briefings list** (`/radar/briefings`) → `data_grid` with columns for run_id/status/date/items/clusters/duration, plus a `banner` above it for the scheduler info and "Run now" action.
   - **Briefing detail** (`/radar/briefings/:run_id`) → composition of:
     - metadata (date/items/clusters/sources/duration) as a two-column `data_grid`,
     - optional `banner` for degraded briefings (count + notes, matching M-WARN-03's shape),
     - one `content_card` per cluster (label, summary, key_takeaways list, per-item title/link/source), with the per-cluster degraded pill rendered as a `content_card` prop (not a separate widget),
     - collapsible source-health section as a `data_grid` inside a `content_card`'s detail slot.
   - **Sources list** (`/radar/sources`) → `data_grid`.
   - **DAG visualization** (on run detail) → `dag_map` embedder.

   **Gap analysis artifact.** M-PACK-D-02's spec, when authored, includes a verification table: "Radar current render element" → "chosen widget composition" → "gap (if any)". If any gap is identified that the MVP catalog cannot express, the correct action is to amend E-21c (add the missing widget with its own ADR citation, demo, and two-named-consumer justification) rather than ship a pack-registered custom LiveView. The custom-LiveView escape hatch is deferred indefinitely per the parent epic's "Explicitly deferred" table.
3. **Submodule pinning discipline.** Every change to `radar-pack` lands with its own PR + review in the `radar-pack` repo. The Liminara-side submodule-pointer bump is a separate PR citing the `radar-pack` commit. This avoids churn and gives both repos clean histories.
4. **Scheduler replacement, not migration.** Radar's scheduler GenServer is deleted outright in M-PACK-D-01b. Its functionality moves to a `:cron` trigger declaration in `pack.yaml`, served by `TriggerManager`. There is no in-pack scheduler after extraction.
5. **No behavior changes allowed.** Extraction PRs are mechanical refactor — no optimizations, no threshold adjustments, no UI polish. Anything that isn't "same bytes out for same bytes in" is a separate follow-up PR.
6. **E-22 readiness signoff is the gate — a curated author-signoff, not an exhaustive requirements audit.** E-21d is not done until the admin-pack author (you, as owner of `admin-pack/v2/`) has signed off that the short readiness checkpoint reflects what admin-pack needs for E-22 day 1. The gate is deliberately soft on requirements-completeness (no structured extraction against the 3,086-line architecture doc set) and deliberately strong on the social signal (the author who wrote the admin-pack architecture says "yes, I can start E-22 against this"). Rationale: the real validation is building admin-pack in E-22, not reviewing paper at E-21d wrap; requirements-completeness via paper extraction is work that doesn't pay back when the author is the same person.

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Extraction reveals a schema gap that requires amending E-21a ADRs | Med | Expected and acceptable. ADRs + CUE schemas + fixtures + consumers update together. Preferred over shims. |
| Radar replay breaks during extraction due to path or identity changes | **High** | Replay test runs at every PR during extraction. Pack-instance FS-scope root is configured to match Radar's current paths so artifact content addresses are stable. |
| Custom Radar LiveView UX doesn't map to `liminara_widgets` widgets | Low | Plan-time gap analysis (2026-04-23) found the initial 3-widget MVP catalog insufficient (missing `content_card` for per-cluster briefings and `banner` for degraded alerts). Those are now in the 5-widget MVP (E-21c), each with two-named-consumer justification. If extraction reveals a further gap, the discipline stands: amend E-21c, no escape hatch. Pack-registered LiveView routes remain explicitly deferred per the parent epic. |
| Submodule workflow adds friction to reviewer's cognitive load | Low | Documented in M-PACK-D-01a's tracking (the milestone that first exercises the submodule workflow): "pack repo PR first, pointer bump second." Reviewer check at wrap. Each subsequent milestone (D-01b, D-02) inherits the documented convention. |
| Radar's tests have implicit dependencies on in-tree paths that break when moved | Low | The pre-audit in M-PACK-D-01a (see `radar-references.md`) classifies every in-tree Radar reference before the flip, including test-path dependencies. Expected: tests move with the code; in-tree paths become pack-relative paths; harness provides a consistent working-directory convention. Load-bearing surprises found by the audit are classified and either folded into D-01b's scope or named a D-02 bridge item before D-01b starts. |
| E-22 readiness signoff discovers capabilities the admin-pack author needs that E-21 did not ship | Med | Expected. The signoff is a curated list, not an exhaustive audit; some items will map to "deferred to E-22 with named trigger" or "shipped-differently from what the architecture doc assumed." The gate is the admin-pack author's signoff ("yes, I can start E-22 against this"), not requirements-completeness. Gaps that the signoff misses surface as real pressure during E-22's first milestones; at that point they're concrete and actionable rather than paper-review speculation. |
| Pack authoring guide drifts from reality because it's drafted mid-work and finalized late | Low | Guide uses `examples/file_watch_demo` and the extracted `radar-pack` as its references, not prose assertions. If either changes, the guide is updated atomically in the same PR. |
| "No behavior changes" discipline is hard to maintain during a large refactor | Med | Radar's existing tests are the line: if they pass, behavior is preserved. PRs that require changing a Radar test to pass are suspect and need explicit justification. |

## Dependencies

- **E-21b must be fully merged.** `PackLoader`, `PackRegistry`, `TriggerManager`, `SurfaceRenderer`, `SecretSource`, and advisory FS-scope enforcement must all be available and tested.
- **E-21c must be fully merged.** `liminara-pack-sdk` (both Python and Elixir), `liminara_widgets` widgets, CLIs, and harness must all be available.
- **The `radar-pack` submodule repo must be creatable.** If there are admin/access issues with creating the repo under the target GitHub org, escalate before M-PACK-D-01a starts (D-01a is specifically the milestone that retires this risk — the whole point of the three-milestone split).

## What comes after

- **E-22 (admin-pack)** can start immediately. The E-22 readiness signoff (short curated list + admin-pack-author signoff) is its entry gate; requirements-completeness auditing is deferred to E-22 development where it surfaces as real building pressure.
- **Phase 6 (VSME)** inherits a hardened contract. Its epic spec (existing as E-13) should be revised at the start of Phase 6 to reference the shipped contract.
- **Provider op libraries** (`liminara-ops-pdf`, `-llm`, `-gmail`, etc.) can be extracted from Radar + admin-pack once patterns stabilize. This is a follow-up epic, not part of E-21.

## References

- Parent epic: `work/epics/E-21-pack-contribution-contract/epic.md`
- E-21a (prerequisite): `work/epics/E-21-pack-contribution-contract/E-21a-contract-design.md`
- E-21b (prerequisite): `work/epics/E-21-pack-contribution-contract/E-21b-runtime-pack-infrastructure.md`
- E-21c (prerequisite): `work/epics/E-21-pack-contribution-contract/E-21c-pack-dx.md`
- E-11 Radar (done): `work/done/E-11-radar/` — the thing being extracted
- Current Radar code:
  - `runtime/apps/liminara_radar/`
  - `runtime/python/src/ops/radar_*.py`
  - `runtime/apps/liminara_web/lib/liminara_web/live/radar_live/`
- Admin-pack architecture: `admin-pack/v2/docs/architecture/bookkeeping-pack-on-liminara.md`, `admin-pack/v2/docs/architecture/repo-layout.md`
- Shim policy: `docs/governance/shim-policy.md`
