---
id: E-21a-contract-design
parent: E-21-pack-contribution-contract
phase: 5c
status: planning
depends_on: E-19-warnings-degraded-outcomes
---

# E-21a: Pack Contract Design

## Goal

Produce the authoritative data contract for Liminara's pack contribution model — CUE schemas, ADRs, fixtures, worked examples, tooling — with **zero runtime code moves**. This sub-epic is the critical-path gate that every other E-21 sub-epic builds on.

When E-21a is done:
- The pack contract exists as a reviewable, testable document set.
- CI can enforce schema conformance on any pack manifest or surface file.
- Every downstream design decision (runtime loader, SDK shape, widget catalog, Radar extraction) has an ADR it is required to respect.
- Radar continues to run exactly as it does today — nothing has been rebuilt yet.

## Context

The parent initiative (E-21) turns Liminara into a language-agnostic runtime that loads packs from manifests. Three shapes of failure are possible without a contract-first sub-epic:

1. **The runtime pack loader (E-21b) gets designed against Radar alone**, producing one-pack abstraction dressed up as generic infrastructure.
2. **The SDK (E-21c) locks in ergonomics that the wire protocol cannot honestly express**, creating an implicit contract that diverges from the stated one.
3. **Radar extraction (E-21d) discovers mismatches mid-extraction**, forcing rework of runtime/SDK choices late in the cycle.

E-21a eliminates all three by making the contract reviewable *before* any code-moving milestone begins. ADRs cite both Radar's documented behaviour and admin-pack's documented requirements (`admin-pack/v2/docs/architecture/`) so the contract is tested against two domains, not one.

## Scope

### In scope

- **Contract-TDD tooling** — a repo-level workflow that treats schemas + fixtures as the "tests" for contract designs, and ADRs + worked examples as the "specs." Specifically: the `design-contract` skill, `contract-design` rule, CUE toolchain in the devcontainer, `cue vet` CI check, ADR template extensions.
- **All contract ADRs** listed in the parent epic, each paired with a CUE schema, fixtures (valid + invalid), and a worked example citing Radar and (where relevant) admin-pack's documented needs.
- **A named reference-implementation plan** for each ADR: which existing or near-future code validates the contract. Radar (after E-21d extraction) is the primary; `examples/file_watch_demo` (shipped in E-21c) is the secondary for `:file_watch`.
- **A schema-evolution test harness** — CI runs a compat test that validates every historical fixture against every supported schema version.

### Out of scope

- Any runtime code (PackLoader, PackRegistry, SurfaceRenderer, etc.) — that is E-21b.
- Any SDK or tooling (Python SDK, CLIs, widgets, harness) — that is E-21c.
- Radar extraction — that is E-21d.
- Admin-pack — that is E-22.
- CUE schemas for artifact content-types (kept as MIME strings in MVP; CUE is the upgrade path).

## Constraints

All shared constraints from E-21's parent epic apply. Sub-epic-specific:

- **No code moves in this sub-epic.** The only code-like artifacts shipped are: the `design-contract` skill, `cue vet` CI configuration, ADR template changes, and schema files. Anything that changes the behaviour of `liminara_core` or `liminara_web` belongs to E-21b.
- **Every ADR has a passing `cue vet` fixture set.** An ADR without fixtures is not done.
- **Every ADR names its reference implementation** — the existing or near-future code that demonstrates the contract on real work. "TBD" is not an acceptable reference.

## Success criteria

- [ ] `design-contract` skill exists at `.ai-repo/skills/design-contract.md` (synced to `.claude/skills/design-contract/SKILL.md`), with a defined workflow: draft ADR → write CUE schema → write fixtures → write worked example → name reference implementation → review → merge.
- [ ] `contract-design` rule exists at `.ai-repo/rules/contract-design.md`, enforceable by the reviewer agent.
- [ ] CUE is installed in the devcontainer (`cue` CLI available; version pinned).
- [ ] `cue vet` runs in CI on changed `.cue` files and fails the build on schema violations.
- [ ] ADR template extensions in `.ai/templates/` (or `.ai-repo/templates/` if repo-specific) support the new fields: schema path, fixtures path, worked example path, reference implementation citation.
- [ ] All 16 contract ADRs (listed below) are merged with their accompanying CUE schemas, valid/invalid fixtures, and worked examples.
- [ ] The schema-evolution CI check runs on every PR and validates the current fixture library against the current schemas.
- [ ] A "read this first" index exists at `docs/architecture/contracts/pack-contract-index.md` linking each ADR, schema, and fixture set.
- [ ] Downstream sub-epic specs (E-21b, E-21c, E-21d) reference specific ADRs for every design choice they inherit.
- [ ] M-PACK-A-02a, M-PACK-A-02b, and M-PACK-A-02c each declare their contract-matrix row deltas as explicit acceptance criteria in the milestone spec (`## Contract matrix changes`), and land those rows in `docs/architecture/contracts/01_CONTRACT_MATRIX.md` as part of the milestone's merge. Rule reference: `.ai-repo/rules/liminara.md` → Contract matrix discipline.

## ADRs produced (17)

Each ADR ships with: CUE schema, valid fixtures, invalid fixtures (demonstrating what `cue vet` rejects), worked example (one or two realistic pack snippets), and a named reference implementation citation.

| ADR | Title | Primary reference | Secondary reference |
|---|---|---|---|
| **ADR-LA-01** | Language-agnostic pack contribution | Radar (mixed), admin-pack (Python) | — |
| **ADR-MANIFEST-01** | Pack manifest schema (YAML + CUE) | Radar generated manifest | admin-pack manifest sketch |
| **ADR-PLAN-01** | Plan representation (language-agnostic data) | Radar plan output | admin-pack plan sketch |
| **ADR-OPSPEC-01** | Op execution spec CUE schema (codifies M-TRUTH-01; includes terminal event taxonomy `run_completed` / `run_partial` / `run_failed` per D-2026-04-20-025) | Radar ops | admin-pack op sketches |
| **ADR-WIRE-01** | Port wire protocol schema | Radar Python ops today | — |
| **ADR-SURFACE-01** | Surface declaration schema + widget catalog | Radar runs_dashboard | admin-pack period view |
| **ADR-TRIGGER-01** | Trigger declaration (`:cron`, `:file_watch`, `:manual`) | Radar scheduler | admin-pack intake |
| **ADR-FILEWATCH-01** | File-watch trigger semantics (debounce, coalesce, scan-on-startup, dedup, in-memory queue + rescan-on-restart) | `examples/file_watch_demo` (E-21c) | admin-pack receipt intake |
| **ADR-FSSCOPE-01** | Pack-instance FS-scope declaration | Radar (lancedb_path) | admin-pack data_root |
| **ADR-SECRETS-01** | Secrets declaration + `SecretSource` behaviour | Radar API keys | admin-pack Gmail creds |
| **ADR-CONTENT-01** | Artifact content-type namespace rules | Radar content types | admin-pack item types |
| **ADR-EXECUTOR-01** | Executor-type taxonomy + extensibility (persistent-worker stipulation) | Existing `:inline` + `:port` | future `:container` / `:wasm` |
| **ADR-EVOLUTION-01** | Schema evolution and backward-compat discipline | Kubernetes API versioning | Protobuf evolution |
| **ADR-LAYOUT-01** | Pack repo layout conventions | Radar (post-extraction) | admin-pack |
| **ADR-BOUNDARY-01** | Compile-time boundary enforcement for in-tree packs (`boundary` hex lib + OTP-app splits) | Radar | — |
| **ADR-REGISTRY-01** | Pack registration via deployment config | Radar load path | admin-pack load path |
| **ADR-MULTIPLAN-01** | Multi-workflow packs (multiple plan entrypoints per pack) | Radar (single-plan today) | admin-pack (three-plan) |

Each ADR lives under `docs/decisions/` following the existing ADR convention; the paired CUE schema lives under `docs/architecture/contracts/schemas/<topic>.cue`; fixtures live under `docs/architecture/contracts/fixtures/<topic>/`.

## Milestones

| ID | Title | Summary |
|---|---|---|
| **M-PACK-A-01** | Contract-TDD tooling | Ship the `design-contract` skill, `contract-design` rule, CUE in devcontainer, `cue vet` CI check, ADR template extensions. One-sitting milestone. |
| **M-PACK-A-02a** | Foundational contracts (4 ADRs) | Ship ADR-MANIFEST-01, ADR-PLAN-01, ADR-OPSPEC-01, ADR-WIRE-01 with CUE schemas + fixtures + worked examples. These are the hot path — every other sub-epic blocks on their shape. Ship the schema-evolution CI check in this milestone (it runs against these first schemas and every one that follows). Lands contract-matrix rows for `manifest`, `plan-as-data`, `op-execution-spec`, `wire-protocol`. Refresh the existing warning-contract row to reflect E-19's shipped `Liminara.Warning` + `run_partial` terminal event. |
| **M-PACK-A-02b** | Packs-as-running-systems (5 ADRs) | Ship ADR-SURFACE-01, ADR-TRIGGER-01, ADR-FILEWATCH-01, ADR-FSSCOPE-01, ADR-SECRETS-01 with CUE schemas + fixtures + worked examples. These define how a loaded pack interacts with the world (UI, triggers, filesystem, secrets). Unblocks the bulk of E-21b's runtime plumbing. Lands contract-matrix rows for `surface-declaration`, `trigger`, `file-watch`, `fs-scope`, `secrets`. |
| **M-PACK-A-02c** | Governance (8 ADRs) | Ship ADR-REGISTRY-01, ADR-MULTIPLAN-01, ADR-EXECUTOR-01, ADR-EVOLUTION-01, ADR-LAYOUT-01, ADR-BOUNDARY-01, ADR-CONTENT-01, ADR-LA-01 with CUE schemas + fixtures + worked examples. These govern how packs are registered, composed, extended, and bounded. Can be reviewed in parallel with M-PACK-A-02b once M-PACK-A-02a's foundational shapes are frozen. The `docs/architecture/contracts/pack-contract-index.md` lands in this milestone. Lands contract-matrix rows for the governance contracts that have live sources (`registry`, `executor-taxonomy`, `layout`, `boundary` at minimum; authors evaluate whether meta-ADRs like `schema-evolution`, `language-agnostic`, `multi-plan`, `content-namespace` warrant rows when drafting the milestone spec). |

## Technical direction

1. **CUE as the source of truth for manifest, plan, surfaces, and execution spec.** YAML/JSON are on-the-wire representations; CUE is the authoritative schema. `cue vet` is the validation boundary.
2. **ADRs cite both Radar and admin-pack** wherever the contract touches pack-level concerns. Contracts derived from Radar alone are explicitly flagged as one-pack abstractions and require secondary review.
3. **The schema-evolution discipline is set here, not later.** Every CUE schema file carries a `schema_version`. Breaking changes bump major version + add deprecation ADR. Additive changes stay compatible by CUE unification. CI runs the compat test against all historical fixtures on every PR.
4. **Reference implementations are named at ADR-writing time**, not deferred. If no real code validates the contract, the contract is too abstract.
5. **Pack repo layout (ADR-LAYOUT-01)** prescribes conventional paths but allows deviation if manifest entrypoints resolve. The scaffolder (E-21c) produces the conventional layout; non-conventional packs are supported but not blessed.

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| 17 ADRs is a lot to merge sequentially | Low | Split across three clustered milestones (M-PACK-A-02a foundational, M-PACK-A-02b running-systems, M-PACK-A-02c governance). M-PACK-A-02b and M-PACK-A-02c can be reviewed in parallel once M-PACK-A-02a's foundational shapes are frozen. No one milestone carries more than eight ADRs. |
| ADRs pushed to close the sub-epic before admin-pack's needs are honestly reflected | High | Explicit success criterion that each pack-level ADR names both a Radar citation and an admin-pack citation. Reviewer checks the secondary citation is substantive, not ceremonial. |
| CUE toolchain learning curve slows ADR authoring | Low | M-PACK-A-01 ships the `design-contract` skill that embodies the workflow; authors follow the skill's checklist rather than re-deriving. |
| Schema-evolution test fails on historical fixtures | Low | Fixtures written during E-21a start as the historical baseline; every schema change runs the test. No prior fixtures exist to be incompatible with at M-PACK-A-02 landing time. |
| ADR scope creeps into runtime design | Med | ADR template includes a "non-implementation" reminder: ADRs specify shape, not runtime behaviour. PackLoader design is E-21b; ADRs cannot prescribe its internals. |

## Dependencies

- **E-19 must merge before M-PACK-A-01 starts.** ADR-OPSPEC-01 codifies the warning/degraded-outcome contract; it cannot land before E-19 finalizes that contract.
- **M-TRUTH-01 must be referenced** — ADR-OPSPEC-01 is the CUE codification of M-TRUTH-01's ExecutionSpec.

## What downstream sub-epics get from E-21a

- **E-21b** (runtime) inherits: ADR-MANIFEST-01, ADR-PLAN-01, ADR-WIRE-01, ADR-TRIGGER-01, ADR-FILEWATCH-01, ADR-FSSCOPE-01, ADR-SECRETS-01, ADR-EXECUTOR-01, ADR-REGISTRY-01, ADR-SURFACE-01, ADR-MULTIPLAN-01. These constrain PackLoader, TriggerManager, SurfaceRenderer, SecretSource, etc.
- **E-21c** (DX) inherits: ADR-MANIFEST-01, ADR-PLAN-01, ADR-OPSPEC-01, ADR-WIRE-01, ADR-SURFACE-01, ADR-LAYOUT-01, ADR-CONTENT-01. These constrain the Python SDK shape, widget catalog, scaffolder output.
- **E-21d** (extraction) inherits: ADR-LAYOUT-01, ADR-BOUNDARY-01, ADR-REGISTRY-01, plus effectively all others (Radar's extracted form must be a valid pack per every schema).

## References

- Parent epic: `work/epics/E-21-pack-contribution-contract/epic.md`
- M-TRUTH-01 spec: `work/done/E-20-execution-truth/M-TRUTH-01-execution-spec-outcome-design.md`
- E-19: `work/epics/E-19-warnings-degraded-outcomes/epic.md`
- Admin-pack architecture: `admin-pack/v2/docs/architecture/bookkeeping-pack-on-liminara.md`, `repo-layout.md`
- CUE documentation: https://cuelang.org/
