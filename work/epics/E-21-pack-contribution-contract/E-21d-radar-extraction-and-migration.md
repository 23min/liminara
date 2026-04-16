---
id: E-21d-radar-extraction-and-migration
parent: E-21-pack-contribution-contract
phase: 5c
status: planning
depends_on:
  - E-21b-runtime-pack-infrastructure
  - E-21c-pack-dx
---

# E-21d: Radar Extraction + Migration

## Goal

Move Radar entirely out of the Liminara repo into an external `radar-pack` submodule repo, using the contract (E-21a), runtime (E-21b), and DX (E-21c) that the prior sub-epics shipped. When E-21d is done:

- The Liminara repo contains **zero Radar-specific code**: no `liminara_radar/` app, no `radar_*.py` ops, no `radar_live/` LiveView pages, no Radar routes, no Radar fixtures.
- The `radar-pack` submodule repo is a valid, manifest-driven Liminara pack using `liminara_pack_sdk` (Elixir) for plan ergonomics, `liminara-pack-sdk` (Python) for Python ops, and YAML surface declarations rendered via `liminara_ui` widgets.
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
- **Move Radar LiveView pages and routes**: `runtime/apps/liminara_web/lib/liminara_web/live/radar_live/` → `radar-pack` as declarative surfaces where possible (rendered via `liminara_ui`) or as pack-shipped LiveView modules where custom UX is required. Pack-shipped LiveView registration is via the runtime's pack-loaded-routes mechanism (E-21b).
- **Move Radar's scheduler**: Radar's GenServer scheduler is replaced by a `:cron` trigger declaration in `pack.yaml`, served by `TriggerManager` from E-21b.
- **Move Radar fixtures and test data** that are pack-specific to the submodule. Keep only truly Liminara-runtime fixtures in-tree.
- **Bump the submodule pointer in Liminara** to a pinned commit of `radar-pack` once extraction milestones merge there.
- **Add `radar-pack` to Liminara's default deployment config** so the development/test Liminara instance loads it.
- **Run Radar's full test suite against the extracted form** — unit, integration, replay, and UI tests all pass.
- **Finalize `docs/guides/pack-authoring.md`** with Radar cited as the advanced mixed-language reference alongside `examples/file_watch_demo` as the simple pure-Python reference.
- **Write the admin-pack-ready checkpoint document** (`docs/architecture/contracts/admin-pack-readiness.md`) certifying that every admin-pack requirement documented in `admin-pack/v2/docs/architecture/` maps to a shipped E-21 capability.
- **Write the schema-evolution doc** (`docs/architecture/contracts/schema-evolution.md`) explaining the CUE-backed backward-compat discipline for future pack-schema changes.
- **Roadmap and CLAUDE.md "Current Work" housekeeping** reflecting completion of Phase 5c pack-contract work.

### Out of scope

- Any further runtime-plumbing work (done in E-21b).
- Any further SDK or widget work (done in E-21c). If extraction reveals missing capabilities, reviewer decides whether to open a late-breaking E-21c addendum or defer to follow-up.
- Admin-pack itself (E-22).
- Rewriting Radar's Python op internals. Only their location and packaging change; the op logic stays as-is.
- Provider op library extraction (`liminara-ops-pdf`, etc.) — deferred; Radar vendors what it needs.

## Constraints

Shared E-21 constraints apply. Sub-epic-specific:

- **Radar must work at every merge point.** Staged extraction: Elixir + Python first (M-PACK-D-01), then surfaces + routes (M-PACK-D-02). At each merge point, Radar's end-to-end + replay + briefing UI all pass. If any of these fail, the milestone is not done.
- **No compatibility shims.** Extraction is a one-way move. There is no in-tree fallback for Radar after M-PACK-D-02. The shim policy (`docs/architecture/contracts/02_SHIM_POLICY.md`) applies: any temporary compatibility layer has a named removal trigger.
- **Submodule-first discipline.** Changes land in the `radar-pack` repo first (with its own PR + review). The submodule pointer bump in Liminara is a separate PR that references the `radar-pack` commit hash.
- **No behavior changes.** Radar works exactly as it does today from a user perspective. No new features, no tweaks to clustering thresholds, no UI changes. Pure extraction.
- **Contract gaps found during extraction go back to E-21a.** If extraction reveals a schema that cannot represent Radar's real needs, the correct action is to amend an E-21a ADR (+ CUE schema + fixtures) and update downstream code. Do not hack around the gap in E-21d.

## Success criteria

- [ ] `radar-pack` submodule repo exists, initialized with conventional layout per ADR-LAYOUT-01.
- [ ] Liminara's repo contains zero Radar-specific code:
  - [ ] no `runtime/apps/liminara_radar/` app directory
  - [ ] no `radar_*.py` files under `runtime/python/src/ops/`
  - [ ] no `radar_live/` directory under `liminara_web/live/`
  - [ ] no Radar-specific route in `liminara_web`'s router
  - [ ] no Radar-specific test fixtures in-tree beyond generic shared ones
  - [ ] no Radar mentions in `liminara_core` / `liminara_observation` / `liminara_web` code (except as a deployment-config entry in dev/test)
- [ ] `radar-pack`'s `pack.yaml` passes `cue vet` against the manifest schema.
- [ ] `radar-pack`'s surface declarations pass `cue vet` against the surface schema.
- [ ] Radar's end-to-end pipeline test (fetch → extract → dedup → cluster → rank → render → briefing) passes against the extracted pack run via `liminara-test-harness`.
- [ ] Radar's replay test (discovery → replay → identical artifacts) passes against the extracted pack.
- [ ] Radar's briefing UI works in the browser when a Liminara instance has `radar-pack` in its deployment config.
- [ ] Radar's cron scheduling works via `TriggerManager`'s `:cron` trigger (no bespoke scheduler in the pack or runtime).
- [ ] The Liminara dev/test deployment config loads `radar-pack` by path; production-like configs load it by git ref.
- [ ] Pack authoring guide finalized at `docs/guides/pack-authoring.md`, walks zero-to-running in under one page, cites both `file_watch_demo` and `radar-pack`.
- [ ] Admin-pack-ready checkpoint doc at `docs/architecture/contracts/admin-pack-readiness.md` enumerates every admin-pack requirement from `admin-pack/v2/docs/architecture/` and maps it to a shipped E-21 capability (or an explicitly deferred follow-up).
- [ ] Schema-evolution doc at `docs/architecture/contracts/schema-evolution.md` explains the CUE-backed backward-compat discipline.
- [ ] Roadmap updated: Phase 5c pack-contract work marked complete; admin-pack (E-22) listed as ready to start.
- [ ] `CLAUDE.md` "Current Work" section updated to reflect the post-E-21 state.

## Milestones

| ID | Title | Summary |
|---|---|---|
| **M-PACK-D-01** | Radar Elixir app + Python ops extraction | Create `radar-pack` submodule repo. Move `liminara_radar/` Elixir app + `radar_*.py` Python ops to the submodule. Generate `pack.yaml`. Migrate the scheduler to a `:cron` trigger declaration. Bump submodule pointer. Liminara's dev/test config loads `radar-pack`. Radar e2e + replay pass. Radar UI may still render via current LiveView pages (to be extracted in the next milestone). |
| **M-PACK-D-02** | Radar surfaces + routes extraction + docs wrap-up | Move `radar_live/` LiveView pages and routes to `radar-pack` — as declarative surface YAMLs rendered by `liminara_ui` where possible, as pack-shipped LiveView modules where custom UX requires. Bump submodule pointer. Finalize pack authoring guide. Write admin-pack-readiness checkpoint. Write schema-evolution doc. Roadmap + CLAUDE.md housekeeping. Liminara repo is free of Radar code. |

## Technical direction

1. **Staged extraction, validated at each stage.** M-PACK-D-01 moves the Elixir app + Python ops first; UI stays in-tree temporarily rendering via the extracted pack. M-PACK-D-02 moves the UI. This sequencing means the first extraction risk (Elixir + Python coordination) is tested before the second (surface rendering coordination).
2. **Surfaces-first, LiveView-fallback.** For each Radar LiveView page, try first to express it as a declarative surface using `liminara_ui` widgets. The briefing view (list + detail) and runs dashboard (table) should be expressible as `data_grid` + `pdf_viewer` compositions. The DAG visualization uses the `dag_map` embedder widget. If any view has custom UX that generic widgets don't cover, ship it as a pack-provided LiveView module registered via the runtime's pack-loaded-routes mechanism.
3. **Submodule pinning discipline.** Every change to `radar-pack` lands with its own PR + review in the `radar-pack` repo. The Liminara-side submodule-pointer bump is a separate PR citing the `radar-pack` commit. This avoids churn and gives both repos clean histories.
4. **Scheduler replacement, not migration.** Radar's scheduler GenServer is deleted outright in M-PACK-D-01. Its functionality moves to a `:cron` trigger declaration in `pack.yaml`, served by `TriggerManager`. There is no in-pack scheduler after extraction.
5. **No behavior changes allowed.** Extraction PRs are mechanical refactor — no optimizations, no threshold adjustments, no UI polish. Anything that isn't "same bytes out for same bytes in" is a separate follow-up PR.
6. **Admin-pack-readiness doc is the gate.** E-21d is not done until every documented admin-pack requirement maps to a shipped E-21 capability or a named deferred follow-up. The checkpoint doc is reviewed against `admin-pack/v2/docs/architecture/bookkeeping-pack-on-liminara.md` explicitly, line by line.

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Extraction reveals a schema gap that requires amending E-21a ADRs | Med | Expected and acceptable. ADRs + CUE schemas + fixtures + consumers update together. Preferred over shims. |
| Radar replay breaks during extraction due to path or identity changes | **High** | Replay test runs at every PR during extraction. Pack-instance FS-scope root is configured to match Radar's current paths so artifact content addresses are stable. |
| Custom Radar LiveView UX doesn't map to `liminara_ui` widgets | Med | Known escape hatch: pack-shipped LiveView modules. E-21d is free to use this; the pack-authoring guide documents when to use widgets vs LiveView. |
| Submodule workflow adds friction to reviewer's cognitive load | Low | Documented in M-PACK-D-01's tracking: "pack repo PR first, pointer bump second." Reviewer check at wrap. |
| Radar's tests have implicit dependencies on in-tree paths that break when moved | Med | Expected. Tests move with the code; in-tree paths become pack-relative paths; harness provides a consistent working-directory convention. |
| Admin-pack-readiness checkpoint discovers unshipped capabilities | Med | Expected that some checklist items map to "deferred to E-22" or "deferred to a named follow-up." The checkpoint is about being honest, not about shipping everything. |
| Pack authoring guide drifts from reality because it's drafted mid-work and finalized late | Low | Guide uses `examples/file_watch_demo` and the extracted `radar-pack` as its references, not prose assertions. If either changes, the guide is updated atomically in the same PR. |
| "No behavior changes" discipline is hard to maintain during a large refactor | Med | Radar's existing tests are the line: if they pass, behavior is preserved. PRs that require changing a Radar test to pass are suspect and need explicit justification. |

## Dependencies

- **E-21b must be fully merged.** `PackLoader`, `PackRegistry`, `TriggerManager`, `SurfaceRenderer`, `SecretSource`, and advisory FS-scope enforcement must all be available and tested.
- **E-21c must be fully merged.** `liminara-pack-sdk` (both Python and Elixir), `liminara_ui` widgets, CLIs, and harness must all be available.
- **The `radar-pack` submodule repo must be creatable.** If there are admin/access issues with creating the repo under the target GitHub org, escalate before M-PACK-D-01 starts.

## What comes after

- **E-22 (admin-pack)** can start immediately. The admin-pack-readiness checkpoint is its entry gate.
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
- Shim policy: `docs/architecture/contracts/02_SHIM_POLICY.md`
