---
id: ADR-0007
working_id: ADR-MANIFEST-01
title: Pack manifest contract — the YAML form of a Liminara pack's identity
status: accepted
date: 2026-05-02
decided_by: Peter Bruinsma
supersedes: []
superseded_by: []
contract:
  schema: docs/schemas/manifest/schema.cue
  fixtures: docs/schemas/manifest/fixtures/v1.0.0/
  worked_example: docs/schemas/manifest/fixtures/v1.0.0/valid/radar-realistic.yaml
  reference_implementation: M-RUNTIME-02 + runtime/apps/liminara_radar/pack.yaml
  schema_version: "1.0.0"
---

# ADR-0007 — Pack manifest contract

## Context

A Liminara **pack** today is an Elixir module implementing the `Liminara.Pack` behaviour — four callbacks (`id/0`, `version/0`, `ops/0`, `plan/1`) declared in [`runtime/apps/liminara_core/lib/liminara/pack.ex`](../../runtime/apps/liminara_core/lib/liminara/pack.ex) and implemented by domain modules like [`Liminara.Radar`](../../runtime/apps/liminara_radar/lib/liminara/radar.ex). A reference-data callback `init/0` is approved-next per `docs/architecture/01_CORE.md`. This shape works while every pack is written in Elixir and lives inside the Liminara umbrella — the runtime imports the module directly.

The pack ecosystem this milestone is foundational for breaks that assumption. PackLoader (E-25) needs to load packs without compiling them into the umbrella. The Python SDK (E-26) needs to author packs in Python with no Elixir source at all. The admin-pack (E-22) lives in a separate repository submodule. Radar's eventual extraction (E-27) needs a portable description of itself that ships alongside the pack's source. Each consumer needs a **declarative, content- addressable, language-agnostic** description of a pack's static identity — a YAML manifest the loader reads before any code runs.

The Elixir `Liminara.Pack` behaviour is the binding interface internally; the manifest is its YAML rendering. Today no pack ships a `pack.yaml`; M-RUNTIME-02 (E-25) is scheduled to land the Radar generated `pack.yaml` shim, and admin-pack will ship its own once authored. Both must conform to the same schema, validated by `cue vet`, before either loader binds to it. Without a frozen contract, the two consumers will derive subtly-divergent shapes from their respective concrete needs and the schema will be back-rationalised on top.

This ADR specifies the target shape. The schema is forward-looking in its primary surface (no live `pack.yaml` exists yet) but backward-anchored in its content: every field maps to a live runtime concept (`Liminara.Pack` callback, `Liminara.ExecutionSpec` struct field, op-class taxonomy locked in M-TRUTH-01).

## Decision

**Adopt `docs/schemas/manifest/schema.cue` as the machine-checkable contract for a Liminara pack manifest.**

The manifest is the YAML rendering of a pack's static identity:

- `pack_id` — snake_case lowercase string, the wire form of `Liminara.Pack.id/0` (an Elixir atom internally).
- `pack_version` — semver-shaped string, the value `Liminara.Pack.version/0` returns.
- `schema_version` — integer-major (see sub-decision below).
- `ops` — list of op declarations, each carrying the full `ExecutionSpec` shape returned by the op's `execution_spec/0`.
- `init` (optional) — declared reference-data version + key list, surfacing the approved-next `Liminara.Pack.init/0` callback.

The manifest does NOT include `plan/1` — `plan` is a code function emitting a runtime DAG, not declarable static data. The PackLoader (E-25) binds `plan` from the loaded module separately from the manifest.

Sub-decisions:

- **Schema topic name: `manifest`.** Matches the row name in the contract matrix declared by M-CONTRACT-02. The shorter `pack` was rejected because it conflicts with the broader use of "pack" as a code+manifest+install bundle; `manifest` names the specific contract surface this ADR governs.

- **Fixture cohort `v1.0.0/`.** First populated cohort under the layout convention M-CONTRACT-01 shipped. Future additive evolution bumps minor (`v1.1.0/`); breaking evolution bumps major (`v2.0.0/`) and lands a deprecation ADR per ADR-EVOLUTION-01 (M-CONTRACT-04).

- **`schema_version` field — integer-major, top-level, required, errors-when-absent.** The four AC5 questions answered concretely:
  - **Format.** Integer (e.g. `schema_version: 1`). Rejected alternative: semver string (`"1.0.0"`). False precision — a v1.0 vs v1.2 manifest is not incompatible if every change between them is additive (which is the only kind of change v1.x permits per ADR-EVOLUTION-01). Tracking patch-level on the manifest is bookkeeping noise. The integer maps directly onto ADR-EVOLUTION-01's compatibility algorithm: a loader that supports majors `{1, 2}` accepts manifests where `schema_version ∈ {1, 2}` and rejects everything else.
  - **Placement.** Top-level key, equal-tier with `pack_id` and `pack_version`. Rejected alternative: nested under a `meta:` block — adds indirection without payoff.
  - **Required vs. optional.** Required.
  - **Behaviour when absent.** Loader error, citing this ADR + ADR-EVOLUTION-01. Rejected alternative: silently default to `schema_version: 1`. A v2-aware loader presented with an unmarked manifest would silently bind it to v2's stricter rules, breaking authors who omitted the field expecting v1 semantics. The error is the safer discipline.

- **Atom-to-string encoding for `pack_id`.** Internally `:radar` (atom); on the wire `"radar"` (string with snake_case constraint `^[a-z][a-z0-9_]*$`). Same convention OPSPEC uses for determinism class and other Elixir-atom-shaped fields per D-2026-04-26-036.

- **`pack_version` semver constraint.** Regex `^[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9.]+)?$`. Allows pre-release suffix (e.g. `0.1.0-alpha.3`); does not enforce the build-metadata `+build` tail. Loose enough not to block legitimate authoring styles; tight enough to reject obvious mistakes (`"v1"`, `"1"`).

- **Per-op declaration is the full ExecutionSpec, inline.** Each `ops[].execution_spec` mirrors `Liminara.ExecutionSpec` returned by the op's `execution_spec/0`. Per D-2026-05-02-038, the `#ExecutionSpec` shape is byte-duplicated from `op-execution-spec/schema.cue#ExecutionSpec` rather than imported across topics — the M-CONTRACT-01 runner does not wire CUE cross-package imports, and the duplicate-with-comment convention is in force until ADR-EVOLUTION-01 (M-CONTRACT-04) lands a `#common` package architecture.

- **Optional `init` block — opt-in declaration of approved-next reference data.** `Liminara.Pack.init/0` is approved-next per `docs/architecture/01_CORE.md` and admin-pack §3 (where it returns vendor maps, classification markers, prompt templates, etc.). The schema admits an optional `init` block today so a pack can declare the contract surface ahead of the runtime callback shipping; the runtime ignores the field until M-RUNTIME-02's loader binds to it. Omitted by packs without reference data (Radar has none today).

- **Closed schemas throughout.** Every `#Definition` uses `close()` — a fixture with a typo'd or wishfully-added field fails vet. The five `ExecutionSpec` sections are fixed; the determinism / executor / network enumerations are fixed. New sections or new enum values require a migration ADR.

- **Field set bounded by D-036 convention 4.** Per D-2026-04-26-036 convention 4 (lock to actually-used set, expand additively), the schema admits only fields with concrete consumer demand today. The single conventional-manifest field included for v1.0.0 is **`description?: string`** — a free-form human-readable one- or two-sentence pack summary, useful in log lines, error contexts, and future pack-registry surfaces (per Q&A 2026-05-02 Q4). The schema is plaintext-only; Markdown is reserved for a future v1.x bump if a renderer-side consumer demands it. **Excluded** for v1.0.0: `maintainers`, `tags`, `license`, and `plan_module`. Each carries a non-trivial sub-decision that should be made under consumer pressure rather than blind: maintainer format (emails / GH handles / affiliation), SPDX vs free-form license, per-pack vs project-level inheritance, splitting `plan/1` off the pack module (today PackLoader binds `plan/1` from the loaded module's named callback, not a manifest pointer). Future additive evolution adds them when a consumer needs them.

## Consequences

**What becomes easier:**

- M-RUNTIME-02 (E-25) generates a Radar `pack.yaml` whose shape is validated by `cue vet` before the PackLoader binds to it; schema drift surfaces at authoring time rather than at runtime.
- The Python SDK (E-26) authors `pack.yaml` directly without generating Elixir source; downstream Elixir consumers vet the same shape via the same schema.
- Admin-pack (E-22) ships a `pack.yaml` whose shape is constrained identically to Radar's; no Elixir reference implementation is required for the schema to apply.
- ADR-EVOLUTION-01 (M-CONTRACT-04) has a concrete field (`schema_version: int`) to operate on; the compatibility-algorithm shape is constrained in advance.

**What becomes harder:**

- Adding a new pack-level capability now requires an additive schema edit (and possibly a new fixture) on top of the runtime edit. The contract-matrix wrap-time check catches drift but does not auto-update the schema.
- The `#ExecutionSpec` shape is duplicated between `op-execution-spec/schema.cue` and `manifest/schema.cue`. A rename to `Liminara.ExecutionSpec` requires editing both schemas
  + their fixture cohorts. ADR-EVOLUTION-01 (M-CONTRACT-04) will migrate the duplicates to `#common` package imports; until then, the duplicate-with-comment convention per D-2026-05-02-038 is the authoring discipline.
- `init/0`'s shape is declared in the schema before the runtime callback ships. If M-RUNTIME-02 surfaces shape pressure that contradicts the current `#InitDeclaration` (e.g. needs nested versioning or a content-hash-of-snapshot field), the schema bumps additively (v1.1.0) or breakingly (v2.0.0 + deprecation ADR) at that point. The risk is bounded because the field is optional in v1.0.0.

**What we accept:**

- The manifest is forward-looking. No live `runtime/apps/liminara_radar/pack.yaml` exists today; the reference implementation is scheduled-to-exist per Assertion 4 in `.ai-repo/rules/contract-design.md`. M-RUNTIME-02 (E-25) is bound to ship the file at the schema's frozen shape; if M-RUNTIME-02 surfaces shape pressure, this ADR is reopened rather than the schema silently mutating to fit the new generator.
- The `schema_version` field's integer-major form trades expressive precision for compatibility-algorithm simplicity. ADR-EVOLUTION-01 (M-CONTRACT-04) may revisit if the v1 → v2 migration surfaces pressure for finer granularity; the conversion (integer → string-prefix-of-semver) is mechanical.

## Schema-backed contract

The `contract:` frontmatter block names the bundle. Each piece tests a different property of the contract:

- **`schema`** — `docs/schemas/manifest/schema.cue`. The authoritative shape. Cited in the `manifest` row of `docs/architecture/indexes/contract-matrix.md` (added by M-CONTRACT-02's matrix-pass).

- **`fixtures`** — `docs/schemas/manifest/fixtures/v1.0.0/`. Three valid fixtures (one realistic — the Radar pack's full 13-op shape, used as the worked example; one boundary-edge — a one-op pure pack with the optional `init` block omitted; one admin-pack-shaped — bookkeeping with five representative ops drawn from §5 + §7 of `bookkeeping-pack-on-liminara.md`, exercising the optional `init` block). Six invalid fixtures, each exercising a distinct violation class: missing required `schema_version`, `pack_id` not snake_case, `pack_version` not semver, op `determinism.class` out of taxonomy, op `isolation.network` out of taxonomy, version-field types swapped.

- **`worked_example`** — the realistic fixture `docs/schemas/manifest/fixtures/v1.0.0/valid/radar-realistic.yaml` is the worked example. Its YAML body is the ADR's worked example verbatim; the Worked example section below quotes the structural shape — a header plus a representative op slice — without modification (the full 13-op fixture lives in the cohort).

- **`reference_implementation`** — `M-RUNTIME-02 + runtime/apps/liminara_radar/pack.yaml`. The Radar generated `pack.yaml` shim is scheduled-to-exist per Assertion 4 in `.ai-repo/rules/contract-design.md`; M-RUNTIME-02 (E-25) is bound to ship the file at this schema's frozen shape. Live-source primary citations alongside (the closest analogues the runtime exposes today):
  - [`runtime/apps/liminara_core/lib/liminara/pack.ex:1`](../../runtime/apps/liminara_core/lib/liminara/pack.ex) — the `Liminara.Pack` behaviour. The four required callbacks (`id/0`, `version/0`, `ops/0`, `plan/1`) define what the manifest renders as YAML data.
  - [`runtime/apps/liminara_radar/lib/liminara/radar.ex:1`](../../runtime/apps/liminara_radar/lib/liminara/radar.ex) — Radar's Pack behaviour implementation. The closest live analogue to a `pack.yaml`: the same `id`, `version`, and `ops` that the worked-example fixture renders.
  - [`runtime/apps/liminara_radar/lib/liminara/radar/ops/specs.ex`](../../runtime/apps/liminara_radar/lib/liminara/radar/ops/specs.ex) — `Liminara.Radar.Ops.Specs.port/4` and `inline/4` build the `Liminara.ExecutionSpec` structs the worked-example fixture's per-op blocks render as YAML.

- **`schema_version`** — `1.0.0` (the cohort label, not the per-manifest integer field). The first frozen cohort. Bumping this requires either an additive change (minor bump, fixtures stay in `v1.0.0/`, new fixtures land in `v1.1.0/`) or a breaking change (major bump + deprecation ADR per ADR-EVOLUTION-01 when it lands in M-CONTRACT-04).

### Worked example

The Radar pack — daily intelligence briefing pipeline, 13 ops, no reference-data callback declared. The full manifest lives at [`docs/schemas/manifest/fixtures/v1.0.0/valid/radar-realistic.yaml`](../schemas/manifest/fixtures/v1.0.0/valid/radar-realistic.yaml); the structural shape — header + one representative op of each determinism class — is reproduced inline below.

```yaml
schema_version: 1
pack_id: "radar"
pack_version: "0.1.0"
description: "Daily intelligence briefing pipeline: fetches sources, dedupes and clusters items, ranks and summarizes the cluster set, and renders the briefing as HTML."

ops:
  # side_effecting / port — RSS fetcher, talks to the network,
  # replays as :skip (the file already exists).
  - execution_spec:
      identity:
        name: "radar_fetch_rss"
        version: "1.0"
      determinism:
        class: "side_effecting"
        cache_policy: "none"
        replay_policy: "skip"
      execution:
        executor: "port"
        entrypoint: "radar_fetch_rss"
        requires_execution_context: false
      isolation:
        env_vars: []
        network: "tcp_outbound"
        bootstrap_read_paths: []
        runtime_read_paths: []
        runtime_write_paths: []
      contracts:
        inputs: {}
        outputs: {}
        decisions:
          may_emit: false
        warnings:
          may_emit: true

  # pure / port — normalise items, deterministic, replays as
  # :reexecute (idempotent given the same input artifacts).
  - execution_spec:
      identity:
        name: "radar_normalize"
        version: "1.0"
      determinism:
        class: "pure"
        cache_policy: "content_addressed"
        replay_policy: "reexecute"
      execution:
        executor: "port"
        entrypoint: "radar_normalize"
        requires_execution_context: false
      isolation:
        env_vars: []
        network: "none"
        bootstrap_read_paths: []
        runtime_read_paths: []
        runtime_write_paths: []
      contracts:
        inputs: {}
        outputs:
          items: "artifact"
        decisions:
          may_emit: false
        warnings:
          may_emit: false

  # pinned_env / port — embedding op, deterministic given the
  # environment, content-addressed-with-environment cache.
  - execution_spec:
      identity:
        name: "radar_embed"
        version: "1.0"
      determinism:
        class: "pinned_env"
        cache_policy: "content_addressed_with_environment"
        replay_policy: "reexecute"
      execution:
        executor: "port"
        entrypoint: "radar_embed"
        requires_execution_context: false
      isolation:
        env_vars: []
        network: "none"
        bootstrap_read_paths: []
        runtime_read_paths: []
        runtime_write_paths: []
      contracts:
        inputs: {}
        outputs:
          items: "artifact"
        decisions:
          may_emit: false
        warnings:
          may_emit: false

  # recordable / port — LLM call, decisions recorded, replays as
  # :replay_recorded (no LLM re-call).
  - execution_spec:
      identity:
        name: "radar_summarize"
        version: "1.0"
      determinism:
        class: "recordable"
        cache_policy: "none"
        replay_policy: "replay_recorded"
      execution:
        executor: "port"
        entrypoint: "radar_summarize"
        requires_execution_context: false
      isolation:
        env_vars:
          - "ANTHROPIC_API_KEY"
        network: "tcp_outbound"
        bootstrap_read_paths: []
        runtime_read_paths: []
        runtime_write_paths: []
      contracts:
        inputs: {}
        outputs: {}
        decisions:
          may_emit: true
        warnings:
          may_emit: true

  # pure / inline — HTML renderer, runs in-process. The only
  # `inline` op in Radar today.
  - execution_spec:
      identity:
        name: "render_html"
        version: "1.0"
      determinism:
        class: "pure"
        cache_policy: "content_addressed"
        replay_policy: "reexecute"
      execution:
        executor: "inline"
        entrypoint: "render_html"
        requires_execution_context: false
      isolation:
        env_vars: []
        network: "none"
        bootstrap_read_paths: []
        runtime_read_paths: []
        runtime_write_paths: []
      contracts:
        inputs: {}
        outputs:
          html: "artifact"
        decisions:
          may_emit: false
        warnings:
          may_emit: false

  # … 8 further ops elided here; full 13-op cohort lives in
  # docs/schemas/manifest/fixtures/v1.0.0/valid/radar-realistic.yaml.
```

What each part means in domain terms:

- **`schema_version: 1`** — the manifest binds to schema-cohort generation 1. ADR-EVOLUTION-01 (M-CONTRACT-04) operates on this field; a v2-aware loader would either accept this manifest under v2 backwards-compatibility rules (if v1 → v2 was additive) or reject it with a "schema_version too old" error (if v2 broke).
- **`pack_id: "radar"`** — the YAML rendering of `Liminara.Radar.id/0` returning the atom `:radar`. The PackLoader re-atomises this string at load time.
- **`pack_version: "0.1.0"`** — Radar's pack-author-controlled version string, distinct from the schema-cohort integer above. Bumped by Radar's authors; tracks the pack's own evolution.
- **`ops`** — the 13-element list mirrors `Liminara.Radar.ops/0`. Each `ops[].execution_spec` mirrors the corresponding op module's `execution_spec/0` return value field-for-field. The PackLoader (E-25) walks this list and dispatches each op's invocation through the executor named in `execution.executor`.
- **No `init` block** — Radar declares no reference-data callback today; the optional block is omitted entirely.

The admin-pack-shaped fixture ([`bookkeeping-admin-pack-shape.yaml`](../schemas/manifest/fixtures/v1.0.0/valid/bookkeeping-admin-pack-shape.yaml)) exercises the same schema with a different concrete pack — five ops spanning provider libraries (`pdfplumber_extract`, `tesseract_ocr`, `claude_complete`, `gmail_fetch_attachment`) and pack-specific domain logic (`intake_classify`) per `bookkeeping-pack-on-liminara.md` §5 + §7 — and demonstrates the optional `init` block populated with the reference-data keys declared in §3.

### Reference implementation

**Scheduled-to-exist implementation** (per Assertion 4 in `.ai-repo/rules/contract-design.md`):

`runtime/apps/liminara_radar/pack.yaml`, generated by M-RUNTIME-02 (E-25)'s Radar generated-`pack.yaml` shim. The file does not yet exist; M-RUNTIME-02 is bound to ship it at the shape this schema freezes. The cross-binding is recorded as a forward dependency: when M-RUNTIME-02 is spec'd (it has not yet been authored at this ADR's write time per AC10's "milestones not yet spec'd" allowance), its spec must include an acceptance criterion citing this ADR's schema as the constraint the generated file satisfies.

**Live-source primary citations** (alongside the scheduled implementation, per the AC10 rubric — these are the live runtime analogues that constrain the schema's content even before the target file exists):

- [`runtime/apps/liminara_core/lib/liminara/pack.ex:1`](../../runtime/apps/liminara_core/lib/liminara/pack.ex) — the `Liminara.Pack` behaviour. Defines the four required callbacks (`id/0`, `version/0`, `ops/0`, `plan/1`); the manifest's `pack_id`, `pack_version`, and `ops` fields are the YAML rendering of the first three. `plan/1` is intentionally absent from the manifest — it is code, not data, and the PackLoader binds it from the loaded module's named callback, not from the manifest.
- [`runtime/apps/liminara_radar/lib/liminara/radar.ex:1`](../../runtime/apps/liminara_radar/lib/liminara/radar.ex) — Radar's Pack behaviour implementation. The 13-op list returned by `Liminara.Radar.ops/0` is what the worked-example fixture renders as `ops:`; the order is the order in this module.
- [`runtime/apps/liminara_radar/lib/liminara/radar/ops/specs.ex`](../../runtime/apps/liminara_radar/lib/liminara/radar/ops/specs.ex) — `Liminara.Radar.Ops.Specs.port/4` and `inline/4` are the builders Radar's op modules call to assemble their `Liminara.ExecutionSpec` structs. The worked-example fixture's per-op `execution_spec` blocks render those struct values as YAML.

Pack-level reference is also embodied in the per-op specs of every Radar op module under [`runtime/apps/liminara_radar/lib/liminara/radar/ops/`](../../runtime/apps/liminara_radar/lib/liminara/radar/ops/); each module's `execution_spec/0` return value is one entry of the worked example's `ops` list.

### Anchored admin-pack citation

**Secondary reference (forward-looking, per Assertion 1 in `.ai-repo/rules/contract-design.md`):**

`admin-pack/v2/docs/architecture/bookkeeping-pack-on-liminara.md §3 — Pack identity (id, version, ops, plan, init declarations)` is the load-bearing anchor. The section shows the four `Liminara.Pack` callbacks plus the approved-next `init/0` callback in concrete form, and enumerates the reference-data keys the bookkeeping pack would populate at init time (`vendor_canonical_map`, `no_doc_patterns`, `classification_markers`, `bank_descriptors`, `match_thresholds`, `llm_prompts`, `swedish_locale`). This is the same pack-identity surface this ADR's schema freezes; the admin-pack- shaped fixture in this bundle's cohort renders that shape as YAML.

A complementary anchor — `admin-pack/v2/docs/architecture/bookkeeping-pack-on-liminara.md §7 — Pack-specific Ops` — enumerates seventeen ops by name + class spanning all four determinism classes (`intake_classify (pure)`, `llm_match_escalate (recordable)`, `export_period_folder (side_effecting)`, the implicit pinned_env class on `tesseract_ocr` from §5) plus the entrypoint shapes that the manifest's per-op `execution_spec.execution.entrypoint` field must accommodate. This anchor demonstrates the manifest schema's expressivity across the four-class taxonomy on a real second pack.

A third anchor — `admin-pack/v2/docs/architecture/bookkeeping-pack-on-liminara.md §5 — Provider Op libraries` — names individual provider-library ops by their declared determinism class (`pdfplumber_extract (pure)`, `tesseract_ocr (pinned_env)`, `claude_complete (recordable)`, `gmail_fetch_attachment (side_effecting)`). The admin-pack-shaped fixture renders four of these as concrete manifest entries.

This citation is admin-pack-secondary to Radar-primary. Radar today exercises the manifest contract through its `Liminara.Pack`-shaped declarations (the live analogue per the live-source citations above); admin-pack's bookkeeping flow will exercise the same contract once authored. The two-pack pressure prevents this ADR from being a one-pack abstraction.

## Validation

The schema, fixtures, and worked example all vet locally:

```sh
$ ./scripts/cue-vet
$ echo $?
0
```

Field-for-field correspondence with the live `Liminara.Pack` behaviour is the contract-matrix wrap-time check. A future rename in `pack.ex` (e.g. `id/0` → `name/0`) that doesn't update `schema.cue` is caught by the matrix audit before the milestone wraps.

The schema-evolution loop in `scripts/cue-vet` walks every fixture in `docs/schemas/manifest/fixtures/v1.0.0/` against the HEAD schema on every commit (via the pre-commit hook) and on every `scripts/cue-vet` no-args invocation. A schema change that breaks an existing fixture either reverts the change or lands a deprecation ADR + major version bump per ADR-EVOLUTION-01 (when M-CONTRACT-04 lands).

## References

- **Parent sub-epic spec:** `work/epics/E-24-contract-design/epic.md`
- **Owning milestone:** `work/epics/E-24-contract-design/M-CONTRACT-02-foundational-contracts.md`
- **Predecessor ADRs in this milestone:**
  - [`docs/decisions/0004-op-execution-spec.md`](./0004-op-execution-spec.md) — ADR-OPSPEC-01. The per-op declaration shape's `#ExecutionSpec` is duplicated from there per D-2026-05-02-038.
  - [`docs/decisions/0005-port-wire-protocol.md`](./0005-port-wire-protocol.md) — ADR-WIRE-01.
  - [`docs/decisions/0006-replay-protocol.md`](./0006-replay-protocol.md) — ADR-REPLAY-01.
- **Forward-reference (deferred to M-CONTRACT-04):** ADR-EVOLUTION-01 specifies the compatibility algorithm over this ADR's `schema_version` field. ADR-EVOLUTION-01's eventual write-up will cross-reference back.
- **Contract-matrix index (row added by M-CONTRACT-02 wrap-pass):** `docs/architecture/indexes/contract-matrix.md`
- **Reviewer rule (the four assertions):** `.ai-repo/rules/contract-design.md`
- **Authoring overlay (Liminara bindings on the upstream skill):** `.ai-repo/skills/design-contract.md`
- **Decision log entries:**
  - `D-2026-04-22-028` — ADR working-keyword IDs in frontmatter (now superseded by D-030 on filename, retained for the `working_id:` convention).
  - `D-2026-04-23-030` — ADR filename `NNNN-<slug>.md`, ID `ADR-NNNN`. This ADR is `0007-pack-manifest.md` per the convention; the working-keyword ID `ADR-MANIFEST-01` lives in `working_id:`.
  - `D-2026-04-26-036` — CUE encoding conventions inherited from ADR-OPSPEC-01's bundle.
  - `D-2026-04-26-037` — CUE struct-presence is shape-only; invalid fixtures use leaf-field violations.
  - `D-2026-05-02-038` — Cross-topic CUE shape duplication accepted; cross-schema imports deferred to ADR-EVOLUTION-01.
- **Live runtime sources mirrored:**
  - `runtime/apps/liminara_core/lib/liminara/pack.ex` — the `Liminara.Pack` behaviour.
  - `runtime/apps/liminara_radar/lib/liminara/radar.ex` — Radar's Pack implementation.
  - `runtime/apps/liminara_radar/lib/liminara/radar/ops/specs.ex` — `Liminara.Radar.Ops.Specs` `port/4` and `inline/4` builders.
  - Each Radar op module under `runtime/apps/liminara_radar/lib/liminara/radar/ops/`.
- **Admin-pack secondary anchors (E-22-pending allowance):**
  - `admin-pack/v2/docs/architecture/bookkeeping-pack-on-liminara.md §3 — Pack identity`
  - `admin-pack/v2/docs/architecture/bookkeeping-pack-on-liminara.md §7 — Pack-specific Ops`
  - `admin-pack/v2/docs/architecture/bookkeeping-pack-on-liminara.md §5 — Provider Op libraries`
- **Approved-next architecture document:** `docs/architecture/01_CORE.md` (the `Liminara.Pack.init/0` reference-data callback's approved-next status).
