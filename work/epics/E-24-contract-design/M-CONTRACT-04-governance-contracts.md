---
id: M-CONTRACT-04
epic: E-24
parent: E-24
status: draft
depends_on: M-CONTRACT-02
---

# M-CONTRACT-04: Governance Contracts (8 ADRs)

## Goal

Ship the eight ADRs that govern how packs are registered, composed, extended, and bounded — registry, multi-plan composition, executor taxonomy, schema evolution, repo layout, compile-time boundary enforcement, content-type namespace, and language-agnostic contribution — each paired with its CUE schema, fixtures, worked example, and named reference implementation. After this milestone the pack contract is complete: every downstream sub-epic (E-25 runtime, E-26 DX, E-27 extraction) has an ADR it is required to respect for every pack-level concern.

## Context

This is the third and final ADR-clustering milestone of sub-epic E-24. M-CONTRACT-01 has shipped the contract-TDD harness (CUE in the devcontainer, the local + pre-commit `cue vet` entry point, the schema-evolution loop, the fixture-library directory layout, and the Liminara-local `design-contract` skill + `contract-design` reviewer rule). M-CONTRACT-02 has shipped the foundational ADRs — ADR-MANIFEST-01, ADR-PLAN-01, ADR-OPSPEC-01, ADR-REPLAY-01, ADR-WIRE-01 — together with the schema-evolution check running against their first fixture sets; ADR-MANIFEST-01 in particular has frozen the `schema_version` field shape that ADR-EVOLUTION-01 in this milestone operates on. M-CONTRACT-03 is in flight or merged with the running-systems ADRs — ADR-SURFACE-01, ADR-TRIGGER-01, ADR-FILEWATCH-01, ADR-FSSCOPE-01, ADR-SECRETS-01.

The runtime today provides two executors (`:inline` for Elixir ops, `:port` for Python ops via `runtime/apps/liminara_core/lib/liminara/executor/port.ex`); Radar lives in-tree as `runtime/apps/liminara_radar/`; there is no runtime concept of "language-agnostic pack," "registered pack," "multi-plan pack," or "content-type namespace" beyond what Radar happens to do. The eight ADRs in this milestone codify those concepts as data, without moving any code — every implementation question is owned by E-25. Admin-pack itself runs in E-22, well after E-21 wraps; the anchored-citation discipline declared in the parent sub-epic's success criteria is the substantive defense against pack-level ADRs being designed against Radar alone.

**Partial parallelism with M-CONTRACT-03.** Five of this milestone's eight ADRs do not bind to any shape M-CONTRACT-03 ships and may be authored as soon as M-CONTRACT-02 freezes:

- ADR-EXECUTOR-01 — talks about the `:inline` / `:port` taxonomy and how new executor types are added; orthogonal to triggers, surfaces, FS-scope, and secrets.
- ADR-EVOLUTION-01 — operates on ADR-MANIFEST-01's `schema_version` field (from M-CONTRACT-02); does not touch any 02b shape.
- ADR-BOUNDARY-01 — describes compile-time `boundary` lib usage in the in-tree umbrella; structural concern, no contract-data dependency on 02b.
- ADR-CONTENT-01 — defines the content-type identifier shape (`<pack_id>.<type_name>@<major>`); independent of triggers / surfaces / FS-scope / secrets.
- ADR-LA-01 — language-agnostic principle; the contract is data and the wire protocol exists (ADR-WIRE-01 in 02a), so 02b shapes are not preconditions.

Three ADRs must wait for M-CONTRACT-03 to freeze:

- ADR-REGISTRY-01 — pack registration via deployment config has to enumerate the declarable shapes per pack-instance (surface paths, trigger declarations, FS-scope root, secret declarations). All four of those shapes are owned by 02b; the registry config schema cannot be authored without them.
- ADR-MULTIPLAN-01 — multiple plan entrypoints are bound 1:1 to triggers (each plan has its trigger). The trigger declaration shape lives in ADR-TRIGGER-01 (02b); ADR-MULTIPLAN-01 cannot define the per-plan trigger reference until ADR-TRIGGER-01 is final.
- ADR-LAYOUT-01 — pack repo layout enumerates conventional paths including the `surfaces/` directory whose file shape is defined in ADR-SURFACE-01 (02b).

Authors picking up M-CONTRACT-04 may begin work on the five unblocked ADRs in parallel with M-CONTRACT-03 authoring; the three blocked ADRs are queued behind M-CONTRACT-03's merge. The dependency on M-CONTRACT-02 is hard (the schema-evolution check must run against 02a's first schemas) and is recorded in this spec's frontmatter; the soft sequencing constraint on M-CONTRACT-03 is documented here in the spec body (not in frontmatter) so this milestone can land independently if 02b lands first or in parallel.

## Acceptance Criteria

1. **Each ADR exists at its `docs/decisions/NNNN-<slug>.md` path with appropriate Nygard form**
   - Every ADR named in *Design Notes* below ships with: structured Nygard sections (Context → Decision → Consequences) and Nygard-standard status vocabulary; the ADR-template fields the parent sub-epic prescribes for pack-contract ADRs (schema path, fixtures path, worked example path, named reference implementation citation); a `Primary reference` and `Secondary reference` per the parent sub-epic's "ADRs produced" table.
   - ADR numbers are sequential, starting from the next unused number after M-CONTRACT-03's last assignment. Authors check `docs/decisions/` immediately before authoring to confirm the starting number.
   - No ADR uses `TBD` or "see admin-pack" as a reference; references are concrete (existing or scheduled with named owning milestone, matching acceptance criterion in that milestone, defined shape).

2. **Each ADR ships with CUE schema, valid fixtures, invalid fixtures, worked example, and named reference implementation**
   - For each ADR, a paired CUE schema lives at `docs/schemas/<topic>/schema.cue`, valid fixtures live at `docs/schemas/<topic>/fixtures/v1.0.0/*.yaml`, and at least one invalid fixture demonstrates what `cue vet` rejects.
   - Each ADR's worked example exercises the schema against one or more realistic pack snippets; the example is included in the ADR body (not just by reference to a fixture file).
   - Each ADR names its reference implementation per the parent sub-epic's reviewer rubric: existing code, or scheduled code with the named owning milestone, the matching acceptance criterion in that milestone's spec, and a concretely-described shape. Acceptable scheduled-reference shapes for this milestone include: Radar generated `pack.yaml` shim (M-RUNTIME-02), `Liminara.PackRegistry` (M-RUNTIME-02), `boundary` declarations on `Liminara.Pack.API` (M-RUNTIME-01), `radar-pack` submodule layout (M-RADX-01), the admin-pack-shape proxy pack (M-RUNTIME-02/B-03).

3. **ADR-EVOLUTION-01 answers all four pack-runtime version compatibility questions and exercises the algorithm end-to-end**
   - The ADR specifies (a) the declaration format and placement for the manifest's schema-version field — referencing ADR-MANIFEST-01's `schema_version` shape, not redefining it; (b) the chosen compatibility algorithm naming one option from the parent epic's design-space shortlist (P1 strict-major-match-with-additive-tolerance / P2 multiple-historical-schemas-with-deprecation-window / P3 no-version-field-unify-or-fail / P4 pack-declares-compat-range) and justifies the choice against the alternatives; (c) the historical-schema maintenance policy — current-only or multiple-historical, with the deprecation-window length and the trigger for removal (Liminara major version bump? pack-stakeholder signal?); (d) the deprecation-window semantics — load-and-warn / load-with-UI-badge / refuse-load-N-versions-before-removal.
   - The worked example exercises the chosen algorithm with at least one pack-declared-version-vs-runtime-version skew scenario; the scenario shows the input (pack manifest with declared `schema_version` X, runtime running schema Y) and the expected outcome (load / load-with-warning / refuse-with-error and the error shape).
   - The ADR cross-references ADR-MANIFEST-01 explicitly: "ADR-MANIFEST-01 owns the field's shape in the data; this ADR owns the compatibility algorithm operating on that field." A change to one is a coordinated change to both.

4. **ADR-CONTENT-01 specifies the content-type namespace and explicitly excludes per-payload schemas**
   - The ADR specifies all five elements per the parent sub-epic's per-ADR requirements: identifier shape (`<pack_id>.<type_name>@<major_version>`, dot+at delimiters justified against colon-delimiter alternatives by filesystem-path safety + URL-reserved-character avoidance + visual distinction + mechanical-parseability of error messages); validity rules (regex / CUE validator with `pack_id` and `type_name` matching `[a-z][a-z0-9_]*`, version a positive integer, full ID matching `^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*@[1-9][0-9]*$` or CUE equivalent); cross-pack collision rules (a pack may only emit content-types whose IDs start with its declared `pack_id`; reserved `pack_id` values `runtime` / `liminara` / `system` blocked from pack-level emission; runtime validates at artifact emission time); evolution rules (additive-stays-at-same-`@<major>`, breaking-bumps-`@<major+1>`, both versions may coexist until the pack declares a deprecation removal trigger — explicit binding from ADR-EVOLUTION-01 applied to content-types).
   - The ADR's Out-of-Scope section explicitly states "Per-payload CUE schemas (what fields a specific content-type's artifact body carries) are demand-driven per pack — packs author them when they want mechanical payload validation; the MVP runtime validates the namespace string shape at emission time, not the payload body."
   - The worked example includes at least four real-pack content-type IDs — at least two from Radar (citing existing Radar content-type usage in `runtime/apps/liminara_radar/`), at least two from admin-pack's documented item types (anchored-cited under `admin-pack/v2/docs/architecture/`) — plus at least one deliberate-invalid fixture covering one of: cross-pack collision attempt, reserved-`pack_id` use, malformed identifier shape; the invalid fixture shows the expected error shape.

5. **ADR cross-references between this milestone and earlier milestones are recorded explicitly**
   - ADR-MULTIPLAN-01 records its binding to ADR-TRIGGER-01 (M-CONTRACT-03): each plan entrypoint binds 1:1 to a trigger, and the trigger declaration shape is owned by ADR-TRIGGER-01.
   - ADR-REGISTRY-01 records its bindings to ADR-SURFACE-01, ADR-FSSCOPE-01, and ADR-SECRETS-01 (all M-CONTRACT-03): the per-pack registry config entry references surface paths, FS-scope root, and secret declarations, each of whose shape is owned by its respective ADR.
   - ADR-LAYOUT-01 records its binding to ADR-SURFACE-01 (M-CONTRACT-03): the conventional pack repo layout includes a `surfaces/` directory whose file shape is owned by ADR-SURFACE-01.
   - ADR-EVOLUTION-01 records its binding to ADR-MANIFEST-01 (M-CONTRACT-02) per AC 3.
   - ADR-CONTENT-01 records its binding to ADR-EVOLUTION-01 (this milestone) for content-type major-version-bump semantics per AC 4.

6. **Anchored-citation discipline holds for the five ADRs subject to it**
   - Every pack-level ADR in this milestone whose secondary reference is admin-pack — ADR-REGISTRY-01, ADR-MULTIPLAN-01, ADR-LAYOUT-01, ADR-CONTENT-01, ADR-LA-01 — cites a specific file + section anchor inside `admin-pack/v2/docs/architecture/` (e.g. `bookkeeping-pack-on-liminara.md §4.2 — per-receipt lifecycle`), not a generic "see admin-pack" reference.
   - The reviewer follows each anchored citation, reads the cited section, and judges whether the ADR's design genuinely satisfies the cited need — not merely whether a citation is present.
   - Unanchored citations block ADR merge.
   - The remaining three ADRs in this milestone — ADR-EXECUTOR-01, ADR-EVOLUTION-01, ADR-BOUNDARY-01 — are exempt from the anchored-citation gate (their secondary references are not admin-pack), but each must still cite a substantive secondary reference per the existing risks-table rule. ADR-EXECUTOR-01 cites future `:container` / `:wasm` executors as the pressure surface; ADR-EVOLUTION-01 cites Protobuf evolution as the secondary; ADR-BOUNDARY-01 has no secondary reference declared in the parent sub-epic's ADR table and is exempt from the secondary-reference rule too.

7. **Reference implementations are concrete, with named owning milestones for scheduled references**
   - Every reference implementation citation follows the parent sub-epic's reviewer rubric: existing references cite the live source path; scheduled references cite the owning milestone by ID, the matching acceptance criterion in that milestone's spec binding the reference's shape to the ADR, and a concretely-described shape (described, not gestured at).
   - For ADR-EXECUTOR-01: the existing `:inline` and `:port` taxonomy lives in `runtime/apps/liminara_core/lib/liminara/executor.ex` and `runtime/apps/liminara_core/lib/liminara/executor/port.ex`; the ADR cites both paths directly.
   - For ADR-BOUNDARY-01: scheduled reference is M-RUNTIME-01's `boundary` declarations on `Liminara.Pack.API`; the ADR cites M-RUNTIME-01 by ID and the matching acceptance criterion ("Boundary enforcement at compile time per ADR-BOUNDARY-01").
   - For ADR-REGISTRY-01: scheduled reference is M-RUNTIME-02's `Liminara.PackRegistry` reading `config :liminara, :packs` at boot; the ADR cites M-RUNTIME-02 by ID and the matching acceptance criterion.
   - For ADR-MULTIPLAN-01: scheduled reference is the admin-pack-shape proxy pack (M-RUNTIME-02 loaded; M-RUNTIME-04 executed); the ADR cites both milestones and their matching acceptance criteria.
   - For ADR-LAYOUT-01: scheduled reference is the `radar-pack` submodule conventional layout in M-RADX-01; the ADR cites M-RADX-01 by ID and the matching acceptance criterion.

8. **All fixtures pass `cue vet` against their schemas; the schema-evolution loop passes**
   - Running M-CONTRACT-01's local entry point against the full fixture library exits zero with all fixtures from this milestone present.
   - Running the schema-evolution loop (per the parent sub-epic's "Schema-evolution check — specification" subsection) against the accumulated fixture library — including this milestone's new fixtures plus the fixtures from M-CONTRACT-02 and M-CONTRACT-03 — exits zero.
   - Each invalid fixture demonstrates the failure semantics specified by M-CONTRACT-01: `<fixture path> fails against <topic>.cue at <schema path>: <CUE error>`.
   - Pre-commit hook runs the same checks on the merge commit and blocks if any fail.

## Constraints

- **No runtime code moves.** No file under `runtime/` is modified; no app under `runtime/apps/` gains, loses, or reshapes a module. The runtime executes exactly as it does at the start of this milestone. ADRs document shape, not behaviour.
- **ADRs cannot prescribe PackLoader, PackRegistry, Boundary checker, or Executor dispatch internals.** Those are E-25's concern. ADRs in this milestone may name a reference implementation in a specific E-25/c/d milestone but cannot dictate the implementing milestone's internal design beyond the contract this milestone defines.
- **No compatibility shims.** Per repo policy in `.ai-repo/rules/liminara.md`, shims are banned. The partial-parallelism dependency between this milestone and M-CONTRACT-03 is not a shim — it is a documented sequencing arrangement, not a surface preserving a lie.
- **No framework template edits.** `.ai/templates/adr.md` is not modified; ADR template field extensions are upstream framework work ([ai-workflow#37](https://github.com/23min/ai-workflow/issues/37)) and ADR authors include the schema/fixture/worked-example/reference-implementation fields inline per ADR until the upstream issue lands.
- **No CI changes.** `.github/workflows/` is not modified; repo-wide CI integration is a separate, deferred initiative.
- **No CUE-tooling changes.** The local entry point and pre-commit hook from M-CONTRACT-01 are reused as-is; this milestone authors no replacement.
- **No per-payload CUE schemas authored.** ADR-CONTENT-01 covers the namespace only; per-payload CUE for specific content-types is demand-driven per pack and out of scope for the entire E-24 sub-epic.
- **Per the parent sub-epic's branch policy: no main-branch work.** This milestone executes on `epic/E-21-pack-contribution-contract` with a milestone branch from it. Spec authoring (this document) is the exception and lands on `main` with `status: draft`.

## Design Notes

### ADRs to author

Each ADR ships at the next sequential `NNNN` number under `docs/decisions/`. Authors confirm the starting number by listing `docs/decisions/` immediately before authoring; M-CONTRACT-03's last assigned number determines the start. The ADR list below is the source of truth for this milestone's scope; if a row is added or removed during authoring, that change is the scope change.

| ADR | Title | Primary reference | Secondary reference | 02b dependency |
|---|---|---|---|---|
| **ADR-EXECUTOR-01** | Executor-type taxonomy + extensibility (persistent-worker stipulation) | Existing `:inline` + `:port` | future `:container` / `:wasm` | none — independent |
| **ADR-EVOLUTION-01** | Schema evolution and backward-compat discipline (binds to ADR-MANIFEST-01's `schema_version`) | Kubernetes API versioning | Protobuf evolution | none — independent |
| **ADR-BOUNDARY-01** | Compile-time boundary enforcement for in-tree packs (`boundary` hex lib + OTP-app splits) | Radar | — | none — independent |
| **ADR-CONTENT-01** | Content-type identifier shape + namespace + collision + evolution rules | Radar content types | admin-pack item types | none — independent |
| **ADR-LA-01** | Language-agnostic pack contribution | Radar (mixed) + admin-pack (Python) | — | none — independent |
| **ADR-REGISTRY-01** | Pack registration via deployment config | Radar load path | admin-pack load path | depends on ADR-SURFACE-01, ADR-FSSCOPE-01, ADR-SECRETS-01 |
| **ADR-MULTIPLAN-01** | Multi-workflow packs (multiple plan entrypoints per pack) | Radar (single-plan today) | admin-pack (three-plan) | depends on ADR-TRIGGER-01 |
| **ADR-LAYOUT-01** | Pack repo layout conventions | Radar (post-extraction) | admin-pack | depends on ADR-SURFACE-01 |

### Partial-parallelism rationale

The five ADRs in the "none — independent" rows above can be authored in parallel with M-CONTRACT-03 authoring, beginning as soon as M-CONTRACT-02's foundational shapes are frozen. They do not bind to any data shape that M-CONTRACT-03 owns; their inputs are M-CONTRACT-02 artifacts (ADR-MANIFEST-01 for ADR-EVOLUTION-01) or repo state independent of E-24 (existing executor source files for ADR-EXECUTOR-01; in-tree umbrella structure for ADR-BOUNDARY-01).

The three ADRs in the "depends on …" rows must wait for M-CONTRACT-03 to merge — not just to have its drafts circulating, but to have its CUE schemas and fixtures locked. ADR-REGISTRY-01's CUE schema for the per-pack config entry references `surface_path: SurfacePath` (ADR-SURFACE-01), `fs_scope_root: FSScopeRoot` (ADR-FSSCOPE-01), and `secrets: [SecretDeclaration]` (ADR-SECRETS-01); writing those references against unfrozen 02b shapes risks rework. Same logic for ADR-MULTIPLAN-01 (its plan-entry shape includes `trigger: TriggerDeclaration` from ADR-TRIGGER-01) and ADR-LAYOUT-01 (its conventional layout includes `surfaces/` whose file shape is from ADR-SURFACE-01).

### Cross-references to record in ADR bodies

| ADR (this milestone) | References | Note |
|---|---|---|
| ADR-EVOLUTION-01 | ADR-MANIFEST-01 (M-CONTRACT-02) | Field shape lives in MANIFEST; algorithm lives here. |
| ADR-CONTENT-01 | ADR-EVOLUTION-01 (this milestone) | Content-type major-version bump semantics inherit EVOLUTION's deprecation rules. |
| ADR-MULTIPLAN-01 | ADR-TRIGGER-01 (M-CONTRACT-03) | Each plan entrypoint binds 1:1 to a trigger. |
| ADR-REGISTRY-01 | ADR-SURFACE-01, ADR-FSSCOPE-01, ADR-SECRETS-01 (M-CONTRACT-03) | Per-pack config entry references each. |
| ADR-LAYOUT-01 | ADR-SURFACE-01 (M-CONTRACT-03) | Conventional `surfaces/` directory shape. |

### ADR-EVOLUTION-01 authoring — chosen algorithm format

The ADR's "Decision" section names exactly one option from the parent epic's design-space shortlist (P1 / P2 / P3 / P4) and justifies the choice against the alternatives (one paragraph per rejected alternative explaining why it was not chosen). The authoring agent has full latitude to choose; constraint is only that the choice is made and justified.

### ADR-CONTENT-01 worked-example fixture sourcing

The four real-pack content-type IDs in the worked example must be cited concretely. For Radar, examples are sourced from in-tree Radar (`runtime/apps/liminara_radar/`); use grep / read to find the actual content-type strings Radar emits today. For admin-pack, the two IDs are sourced from `admin-pack/v2/docs/architecture/` per the anchored-citation discipline — anchor must include file + section + the specific item-type description being cited.

### Contract-matrix-row evaluation for meta-ADRs

The parent sub-epic spec describes contract-matrix rows for "meta-ADRs" (`schema-evolution`, `language-agnostic`, `multi-plan`, `content-namespace`) as author's-discretion: "authors evaluate whether meta-ADRs … warrant rows when drafting the milestone spec." This spec's `Contract matrix changes` section below records the evaluation outcome.

**Resolved policy:** matrix rows are added when their live source ships, not when the ADR ships. A row whose live source is "scheduled" or "TBD" creates drift-by-construction — the matrix's purpose is to point at *what the contract is and where its live source lives*, and a promissory pointer doesn't satisfy that. Concretely:

- Four ADRs in this milestone have live sources today: `registry` (Radar load path), `executor-taxonomy` (`Liminara.Executor` + `Port`), `layout` (in-tree `runtime/apps/liminara_radar/`), `boundary` (existing `boundary` lib usage). Their rows land in 02c.
- Three meta-ADRs would have **future** live sources in E-25: `schema-evolution` (PackLoader compat-check), `content-namespace` (Executor / Artifact.Store emission validation), `multi-plan` (PackRegistry plan-entrypoints map). Their rows land in the E-25 milestone that ships the enforcer; the ADR itself still ships in 02c.
- One meta-ADR is structural and already covered: `language-agnostic` is implicit in ADR-WIRE-01's row from M-CONTRACT-02; no separate row.

This policy decision is recorded here so future readers don't try to retroactively backfill matrix rows during 02c's wrap or treat the deferred rows as drift.

## Out of Scope

- Runtime code: PackLoader, PackRegistry, SurfaceRenderer, TriggerManager, SecretSource, FSScope enforcer, Boundary checker (E-25).
- SDKs, CLIs, widgets, and the test harness (E-26).
- Radar extraction to a submodule, boundary enforcement implementation, pack-authoring guide (E-27).
- Admin-pack itself (E-22).
- Per-payload CUE schemas for specific content-types — demand-driven per pack, not a runtime concern, not in any E-21 sub-epic.
- ADRs from M-CONTRACT-02 (foundational) or M-CONTRACT-03 (running-systems) — those land in their owning milestones.
- Additional language SDKs beyond what ADR-LA-01 prescribes (Rust, Go, Java, TypeScript bindings) — demand-driven per the parent epic's deferred-capabilities table.
- Cross-version pack replay semantics — explicitly deferred to `work/gaps.md` per ADR-REPLAY-01 (M-CONTRACT-02).
- Multi-instance pack tenancy — deferred per the parent epic's deferred-capabilities table.

## Dependencies

- **Hard dependency: M-CONTRACT-02 is merged.** This milestone's ADR-EVOLUTION-01 binds to ADR-MANIFEST-01's `schema_version` field shape; without M-CONTRACT-02's first frozen schemas the schema-evolution check has no historical fixtures to validate against. Frontmatter: `depends_on: M-CONTRACT-02`.
- **Soft sequencing constraint: three of eight ADRs wait for M-CONTRACT-03 to freeze.** ADR-REGISTRY-01, ADR-MULTIPLAN-01, and ADR-LAYOUT-01 cannot be authored against unfrozen 02b shapes. The other five ADRs (ADR-EXECUTOR-01, ADR-EVOLUTION-01, ADR-BOUNDARY-01, ADR-CONTENT-01, ADR-LA-01) may begin in parallel with M-CONTRACT-03 authoring. This is documented in *Context* and *Design Notes* above; not recorded as a frontmatter dependency because the milestone can land with the five unblocked ADRs first if 02b slips, then add the three blocked ADRs once 02b merges.
- **M-CONTRACT-01 has shipped** the CUE toolchain in the devcontainer, the local + pre-commit `cue vet` entry point, the schema-evolution loop, the fixture-library directory layout, and the Liminara-local `design-contract` skill. This milestone reuses all of those without modification.
- **E-19 has merged.** Already a hard dependency of the parent sub-epic; no per-milestone constraint inherited beyond what M-CONTRACT-02 already satisfied.
- **No dependency on E-25, E-26, or E-27 code shipping.** Scheduled-reference citations to milestones in those sub-epics (M-RUNTIME-01, M-RUNTIME-02, M-RUNTIME-04, M-RADX-01) are forward references; the cited milestones do not need to exist as code at this milestone's wrap, only as approved specs with the matching acceptance criteria the citations bind to.

## Contract matrix changes

Per `.ai-repo/rules/liminara.md` → "Contract matrix discipline." Rows land in `docs/architecture/indexes/contract-matrix.md` as part of this milestone's merge.

**Rule applied: rows are added when their live source ships.** A matrix row points at *what the contract is and where its live source lives*. A row whose live source is "scheduled but not yet shipped" is a promissory note, not a pointer, and creates drift-by-construction. The four ADRs in this milestone's set whose live sources exist today get rows here; the four whose live sources ship in E-25 get their rows in the E-25 milestone that lands the enforcer. The ADRs themselves all ship in 02c regardless — only the matrix-row landing waits.

**Rows added in this milestone (4 — all with live sources today):**

- `Pack registration` — live source: Radar's existing load path (`runtime/config/runtime.exs` pack-load configuration + the surrounding application-startup code that consumes it); approved next: ADR-REGISTRY-01 + `docs/schemas/pack-registry/`. Author confirms exact live-source path and canonical row name against the existing matrix at landing time.
- `Executor taxonomy` — live source: `runtime/apps/liminara_core/lib/liminara/executor.ex` + `runtime/apps/liminara_core/lib/liminara/executor/port.ex`; approved next: ADR-EXECUTOR-01 + `docs/schemas/executor-taxonomy/`. Author confirms canonical row name at landing time.
- `Pack repo layout` — live source: in-tree `runtime/apps/liminara_radar/` (Radar's current pre-extraction layout demonstrates the convention); approved next: ADR-LAYOUT-01 + `docs/schemas/pack-layout/` (with row's live-source path updated when E-27 lands the extracted `radar-pack` submodule). Author confirms canonical row name at landing time.
- `Compile-time pack boundary` — live source: existing `boundary` library declarations in the OTP-app structure under `runtime/apps/`; approved next: ADR-BOUNDARY-01 + `docs/schemas/boundary/`. Author confirms exact `boundary`-using files at landing time and updates the row's live-source list when E-25's `pack/api*.ex` modules land.

**Rows deferred to E-25 (3 — live source ships with the enforcer):**

The following ADRs ship in this milestone, but their matrix rows land in the E-25 milestone that ships the enforcing code. Each E-25 milestone declaring one of these enforcers must include the corresponding row in its own `## Contract matrix changes` section.

- `Schema evolution policy` (ADR-EVOLUTION-01) — row lands with **M-RUNTIME-02** (PackLoader's compat-check call site enforcing the chosen algorithm against ADR-MANIFEST-01's `schema_version` field).
- `Content-type namespace` (ADR-CONTENT-01) — row lands with whichever E-25 milestone introduces artifact-emission-time content-type validation (`Liminara.Executor` or `Liminara.Artifact.Store`). **E-25's draft spec does not yet have an explicit acceptance criterion binding this validation to a concrete module — that AC needs to be added when E-25's milestone specs are drafted.** Flagged in this milestone's tracking doc as a downstream-spec obligation.
- `Multi-plan packs` (ADR-MULTIPLAN-01) — row lands with **M-RUNTIME-02** (admin-pack-shape proxy pack loads three plans; `PackRegistry.get/1` returns the declared shape).

**Row deliberately not added (1):**

- `Language-agnostic contract` (ADR-LA-01) — no single live-source path; the property is structural (cuts across PackLoader / Executor / wire protocol) and is already covered by ADR-WIRE-01's matrix row from M-CONTRACT-02. Recording the rationale here so future readers don't try to add it.

**Rows updated:** none expected. Author re-checks `docs/architecture/indexes/contract-matrix.md` immediately before landing; if a row's live-source path needs updating because of intervening work, that update is part of this milestone's PR.

**Rows retired:** none.

## References

- Parent sub-epic: `work/epics/E-21-pack-contribution-contract/E-24-contract-design.md`
- Parent epic: `work/epics/E-21-pack-contribution-contract/epic.md`
- Sibling milestones:
  - `work/epics/E-21-pack-contribution-contract/M-CONTRACT-01-contract-tdd-tooling.md`
  - `work/epics/E-21-pack-contribution-contract/M-CONTRACT-02-foundational-contracts.md` (when authored)
  - `work/epics/E-21-pack-contribution-contract/M-CONTRACT-03-packs-as-running-systems.md` (when authored)
- Downstream sub-epics:
  - `work/epics/E-21-pack-contribution-contract/E-25-runtime-pack-infrastructure.md`
  - `work/epics/E-21-pack-contribution-contract/E-26-pack-dx.md`
  - `work/epics/E-21-pack-contribution-contract/E-27-radar-extraction-and-migration.md`
- Repo rules: `.ai-repo/rules/liminara.md` ("Contract matrix discipline" + "Decision records — two surfaces, one policy")
- Contract matrix: `docs/architecture/indexes/contract-matrix.md`
- Admin-pack architecture (anchored-citation source): `admin-pack/v2/docs/architecture/bookkeeping-pack-on-liminara.md`, `admin-pack/v2/docs/architecture/repo-layout.md`
- Framework upstream issue: [ai-workflow#37](https://github.com/23min/ai-workflow/issues/37) (`design-contract` skill skeleton + ADR template field extensions) — referenced in *Constraints* as the upstream owner of the framework template work this milestone defers
