---
id: E-21-pack-contribution-contract
phase: 5c
status: planning
depends_on: E-19-warnings-degraded-outcomes
composed_of:
  - E-21a-contract-design
  - E-21b-runtime-pack-infrastructure
  - E-21c-pack-dx
  - E-21d-radar-extraction-and-migration
---

# E-21: Pack Contribution Contract

This folder groups the four epics that together establish Liminara's pack contribution contract. Each sub-epic is independently landable; together they turn Liminara into a language-agnostic runtime that loads external packs from manifests.

## Goal

Turn Liminara into a **language-agnostic runtime for reproducible nondeterministic computation**, and define the contract by which any pack — in any language, in an external repo — contributes to a Liminara deployment.

The contract is a **data schema**, not a set of libraries. A pack is a repository containing a manifest, op implementations as addressable executable units, and optional surface declarations. Liminara's runtime reads the manifest, dispatches execution, and renders declared surfaces. Language SDKs are ergonomic wrappers around the data contract; packs can be written without them.

Validate the contract by extracting Radar into its own pack repo while it keeps running end-to-end, and by ensuring admin-pack (E-22) can be authored start-to-finish without touching Liminara's source.

## Why four sub-epics

The pack contribution work spans four clearly distinct concerns with different audiences, risk profiles, and review cadences:

| Sub-epic | Audience | Risk | What ships |
|---|---|---|---|
| **E-21a** Contract Design | Contract reviewers | Low — docs only | ADRs, CUE schemas, fixtures, `design-contract` skill, `cue vet` CI |
| **E-21b** Runtime Pack Infrastructure | Runtime committers | Medium — internal plumbing; Radar must keep running | PackLoader, PackRegistry, SurfaceRenderer, SecretSource, TriggerManager, A2UI MultiProvider |
| **E-21c** Pack DX | Pack authors (external) | Medium — public surfaces on PyPI + Hex | Python SDK, Elixir SDK, `liminara_ui` widgets, `liminara-new-pack`, `liminara-test-harness`, e2e-harness skill, `file_watch_demo` reference pack |
| **E-21d** Radar Extraction + Migration | Reviewer + regression watchers | High — could break Radar | Radar moves to external `radar-pack` submodule; pack authoring guide; admin-pack-ready checkpoint |

Keeping these as separate, letter-suffixed epics under the shared `E-21-*` folder gives us a single narrative landing page (this file) plus four focused landable spec files.

## Sub-epic sequencing

```
  E-19 (Warnings & Degraded Outcomes)
       │
       ▼
  E-21a — Contract Design
       │
       ├─────────────┐
       ▼             ▼
  E-21b — Runtime  E-21c — DX
       │             │
       └──────┬──────┘
              ▼
        E-21d — Radar Extraction + Migration
              │
              ▼
        E-22 — Admin-pack (external)
```

**E-21a** is the critical-path gate: it ships zero code but defines everything downstream builds on. It must land first.

**E-21b** and **E-21c** can run in parallel after E-21a lands — different audiences, different surfaces, weakly coupled. E-21c can consume E-21b's runtime surfaces via integration tests even before E-21b is fully shipped, as long as the wire protocol from E-21a is stable.

**E-21d** is the capstone — it cannot start until both E-21b and E-21c are merged, because extraction exercises them both.

## Shared context

### Admin-pack is three workflows, not one

Admin-pack is the forcing function for this initiative. It is not a single workflow — it is **three coordinated workflows sharing pack-instance-level state**:

1. **Per-receipt lifecycle.** Receipt arrives → classify → extract candidates → match → resolve.
2. **Per-statement lifecycle.** Statement arrives → extract lines → each line acquires a resolution.
3. **Per-period lifecycle.** Period closes → gather reconciled items → compose bundle → seal.

Shared state lives as pack-instance-level artifacts under the pack's FS-scope root, outside any single run's artifact store. The implication: **a pack declares multiple plan entrypoints**, each tied to its own trigger. One pack produces many workflow shapes.

When a pack processes many items (100 receipts), the UI aggregation (metro map with volume badges) is a pack-declared surface reading pack-instance state — not a new runtime node type. Fan-out within a single DAG is deferred to E-16 (Phase 7 dynamic DAGs).

### Contract-as-data, not library-as-API

Every mature DAG/pipeline framework converges on one of two shapes. The library-coupled approach (Airflow, Prefect, Dagster) creates predictable failure modes — upgrade pain, single-language lock-in, hard sandboxing, difficult sharing. The data-contract approach (Argo, Flyte, Kubeflow, GitHub Actions, N8N, Zapier, Windmill) gives workflow portability, multi-language support, and version independence.

Liminara's replay-correctness property reinforces this: plans stored as immutable data the runtime owns end-to-end make replay first-class. Library-coupled plans tie replay to library versions.

## Shared constraints

These apply to every sub-epic:

- **Language-agnostic by construction.** No language is privileged. The runtime is Elixir internally; pack authors can use any language. The Python SDK is the first polished binding because that's where packs are today; other language SDKs can be added without framework changes. (ADR-LA-01 in E-21a.)
- **Contract-as-data.** The contract is CUE schemas + wire protocols. Packs can be written without any Liminara SDK if they emit valid data. SDKs are ergonomics.
- **Backward compatibility by schema evolution.** Manifest declares `schema_version`. Additive schema changes stay backward-compatible by CUE unification. Breaking changes bump major version with a deprecation window. CI runs a compat test against every historical fixture.
- **No library imports from packs into Liminara internals.** Packs may depend on `liminara-pack-sdk` (Python), `liminara_pack_sdk` (Elixir, optional), or nothing. They may NOT depend on `liminara_core`, `liminara_observation`, `liminara_web`, `ex_a2ui`, `dag_map`, or `liminara_ui`. Credo boundary rules enforce this for in-tree code; for external packs, the property is structural.
- **Contract-first discipline.** No milestone in any sub-epic is accepted as done without its ADRs, CUE schemas, fixtures passing `cue vet`, worked examples, and named reference implementation(s). Radar is the primary reference implementation; `examples/file_watch_demo` (shipped in E-21c) is the secondary reference for `:file_watch`.
- **Radar extraction must not regress.** At every merge point during E-21d, Radar must still execute end-to-end, replay correctly, and surface in the observation UI.
- **E-19 first.** Op declarations expose warning surfaces; the SDK reflects the E-19 contract. E-19 must merge before E-21a begins.
- **Wire-level A2UI compliance.** MultiProvider is server-side plumbing only. Wire format stays A2UI v0.9.
- **Compatibility shims banned.** Any exception needs a named removal trigger in the owning milestone spec.
- **No main-branch work.** Executed on `epic/E-21-pack-contribution-contract`; milestone branches from it. Submodule pointers (Radar, admin-pack, ex_a2ui, dag_map) update only after the submodule repo merges.

## Milestone totals

- **E-21a** — 4 milestones (M-PACK-A-01, M-PACK-A-02a, M-PACK-A-02b, M-PACK-A-02c)
- **E-21b** — 3 milestones (M-PACK-B-01, M-PACK-B-02, M-PACK-B-03)
- **E-21c** — 3 milestones (M-PACK-C-01, M-PACK-C-02, M-PACK-C-03)
- **E-21d** — 2 milestones (M-PACK-D-01, M-PACK-D-02)

Total: **12 milestones across 4 sub-epics**.

## Dependency shape (runtime)

```
                ┌─────────────────────────────────────────────────────┐
                │                 LIMINARA RUNTIME                     │
                │                                                       │
                │  liminara_core                                        │
                │  ┌──────────────────────────┐                        │
                │  │ Liminara.Pack.API.*      │ Elixir language binding│
                │  │  (structs, behaviours,   │ of the contract; peer  │
                │  │   plan data, content-    │ to Python SDK — not    │
                │  │   type, fs_scope)        │ the contract itself.   │
                │  └──────────────────────────┘                        │
                │  ┌──────────────────────────┐                        │
                │  │ Runtime internals        │                        │
                │  │  PackLoader (manifest)   │                        │
                │  │  PackRegistry (config)   │                        │
                │  │  Executor dispatch       │                        │
                │  │  TriggerManager          │                        │
                │  │  SurfaceRenderer         │                        │
                │  │  SecretSource behaviour  │                        │
                │  │  FSScope enforcer        │                        │
                │  └──────────────────────────┘                        │
                │                                                       │
                │  liminara_observation → liminara_core                │
                │  liminara_web → liminara_core, liminara_observation, │
                │                 liminara_ui                          │
                │  liminara_ui → ex_a2ui, dag_map (NO liminara_core)   │
                │  liminara_pack_sdk (Elixir, optional)                │
                │    → Liminara.Pack.API                               │
                └─────────────────────────────────────────────────────┘

   ═══════════ CONTRACT BOUNDARY (CUE schemas + wire protocols) ═══════════

   A pack (external repo, any language):
       pack.yaml                    manifest (CUE-validated)
       src/                         op + plan + init entrypoints
       surfaces/*.yaml              surface declarations (CUE-validated)
       tests/                       unit + e2e tests
       containers/                  optional Dockerfiles for container ops
       [custom-widgets/]            optional prebuilt JS bundles

   Pack deps (pack's own package manifest):
       Python pack:    liminara-pack-sdk                  (PyPI)
       Container pack: zero                                (wire protocol only)
       Mixed pack:     liminara-pack-sdk + optional Elixir sugar
       Future Rust/Go: liminara-pack-sdk-rs / -go         (when written)

       Packs MAY NOT depend on: ex_a2ui, dag_map, liminara_ui,
         liminara_core, liminara_observation, liminara_web.

   Pack-dev tooling (OS-level, one-time install):
       liminara-new-pack       scaffolds pack repos (pipx)
       liminara-test-harness   spins up local runtime with pack mounted (pipx)
```

## Explicitly deferred

These surface repeatedly across the sub-epics' scopes; capturing them once here:

| Capability | Deferred to |
|---|---|
| Admin-pack itself | E-22 |
| Fan-out / dynamic DAGs (per-item parallelism within a DAG) | E-16 (Phase 7) |
| Cross-run artifact queries | E-23 |
| Multi-instance pack tenancy | E-15 (Phase 7) |
| Hard FS isolation (Landlock) | E-12 |
| Container / wasm / remote executors | TBD post-VSME |
| CUE schemas for artifact content-types | TBD demand-driven |
| Secret-source adapters beyond env var | Demand-driven (Vault, AWS SM, etc.) |
| Durable trigger queue (survive runtime crashes with pending runs) | E-14 (Phase 7; Oban-backed) |
| Worker distribution queues (multi-node execution) | TBD post-VSME |
| Per-item durable queues between ops (streaming semantics) | Not planned; reconsider if a streaming workload surfaces |
| Port executor process pooling | Tracked in `work/gaps.md`; future runtime work, not E-21 |
| Additional language SDKs (Rust, Go, Java, TS) | Demand-driven |
| `liminara_ui` `pdf_viewer` widget | E-22 (admin-pack receipts/statements) or earlier if a named consumer demands it |
| `liminara_ui` `timeline` widget | Demand-driven (no current consumer; process-mining pack is the likely trigger) |
| Pack-registered custom LiveView routes (UI escape hatch) | Demand-driven; E-21 requires declarative surfaces rendered by `SurfaceRenderer`. If a view cannot be expressed with `liminara_ui` widgets, amend E-21c to add the missing widget rather than open this hatch. |
| Provider op libraries (pdf, llm, gmail, etc.) | Post-extraction of Radar and admin-pack |
| Gate-queue UI as runtime primitive | Pack-level in E-21; may become framework-level later |
| Bundle abstraction as runtime primitive | Pack-level in E-21; may become framework-level later |

## References

- Decision **D-012**: Phase 5c scope rule (only items Radar has proven). This initiative is the documented exception; admin-pack is the second-pack forcing function.
- Decision **D-013**: `Radar correctness → Radar hardening → VSME → platform generalization`.
- Decision **D-014**: roadmap status labels.
- Decision **D-2026-04-01-001**: A2UI as secondary observation UI — this initiative promotes A2UI to primary pack UI surface.
- Decision **D-2026-04-01-003**: Python ops via `:port` — retained; this initiative generalizes the port protocol to any language.
- **M-TRUTH-01**: Execution spec + outcome design. E-21a codifies its structs as CUE.
- **E-19**: Warnings & Degraded Outcomes (prerequisite).
- **E-12**: Op Sandbox (downstream; hard FS enforcement).
- **E-11**: Radar (done; reference implementation that E-21d extracts).
- Admin-pack architecture: `admin-pack/v2/docs/architecture/bookkeeping-pack-on-liminara.md`, `admin-pack/v2/docs/architecture/repo-layout.md`.
- Comparable systems: Argo Workflows, Flyte, Kubeflow Pipelines, GitHub Actions, N8N, Zapier, Windmill, Temporal.
