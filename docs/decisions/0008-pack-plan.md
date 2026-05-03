---
id: ADR-0008
working_id: ADR-PLAN-01
title: Pack plan contract — the YAML form of a Liminara pack's computation DAG
status: accepted
date: 2026-05-02
decided_by: Peter Bruinsma
supersedes: []
superseded_by: []
contract:
  schema: docs/schemas/plan/schema.cue
  fixtures: docs/schemas/plan/fixtures/v1.0.0/
  worked_example: docs/schemas/plan/fixtures/v1.0.0/valid/radar-realistic.yaml
  reference_implementation: "runtime/apps/liminara_radar/lib/liminara/radar.ex:52 (term form, today) + M-RUNTIME-02 + runtime/apps/liminara_radar/pack.yaml (YAML rendering, scheduled)"
  schema_version: "1.0.0"
---

# ADR-0008 — Pack plan contract

## Context

A Liminara **plan** is the DAG a pack's `Liminara.Pack.plan/1` callback returns: a list of named nodes, each invoking one op with its inputs bound to literals or to other nodes' outputs. Today, Radar expresses this content as a `%Liminara.Plan{}` Elixir struct returned from [`Liminara.Radar.plan/1`](../../runtime/apps/liminara_radar/lib/liminara/radar.ex) at line 52 — the struct shape (`nodes: %{node_id => Node}`, `insert_order: [node_id]`) and the per-node binding shape (`%{name => {:literal, value} | {:ref, id} | {:ref, id, key}}`) are defined in [`Liminara.Plan`](../../runtime/apps/liminara_core/lib/liminara/plan.ex). The struct already carries a canonical YAML-renderable shape via `Liminara.Plan.to_map/1` (plan.ex:111).

The pack ecosystem this milestone is foundational for needs the same thing for plans that ADR-MANIFEST-01 specifies for pack identity: a **declarative, content-addressable, language-agnostic** description of a pack's computation DAG. PackLoader (E-25) needs to bind plans without compiling Elixir. The Python SDK (E-26) needs to author plans in Python without an Elixir source. Admin-pack (E-22) lives in a separate repository submodule and must declare its bookkeeping plan(s) in the same shape Radar's plan freezes into. Radar's eventual extraction (E-27) needs a portable plan description that ships alongside the pack's source.

The Elixir `Liminara.Pack.plan/1` callback is the binding interface internally; the YAML rendering is its declarative form. Today no pack ships a `pack.yaml`-companion plan rendering; M-RUNTIME-02 (E-25) is scheduled to ship the Radar generated form, and admin- pack will ship its own once authored.

This ADR specifies the target shape. The schema is faithful to Radar's live plan content (every binding shape Radar uses today is admitted) but selectively diverges from `Liminara.Plan.to_map/1`'s current serialisation in two specific places — see Decision below.

## Decision

**Adopt `docs/schemas/plan/schema.cue` as the machine-checkable contract for a Liminara pack plan.**

The plan is the YAML rendering of a pack's computation DAG:

- `schema_version` — integer-major (mirrors ADR-MANIFEST-01).
- `nodes` — ordered list of node declarations, mirroring `Liminara.Plan.insert_order`-walked iteration. Each node carries `node_id`, `op`, and `inputs`.

Sub-decisions, organised against the eight Q&A axes surfaced 2026-05-02:

- **Q1 — `node_id` shape: non-empty string, length 1..63, no regex constraint.** Radar composes node IDs dynamically — for example `fetch_${source["id"]}` at radar.ex:73. A strict snake_case regex (e.g. `^[a-z][a-z0-9_]*$`) would reject legitimate authoring styles where the dynamic component carries hyphens or digits. The 63-character cap is the DNS-label limit, giving forward-compatibility with node IDs flowing into URLs, filesystem paths, or registry keys without truncation. Rejected alternatives: snake_case regex (too tight); no length cap (too loose).

- **Q2 — `op` shape: bare op-name string, matching the op's `execution_spec.identity.name` in the pack manifest.** `Liminara.Plan.to_map/1` today serialises the op binding as `Atom.to_string(node.op_module)` — yielding strings like `"Elixir.Liminara.Radar.Ops.FetchRss"`. That shape is Elixir- internal and would leak Elixir-isms into Python-authored pack.yaml + admin-pack-authored plan.yaml. The schema freezes the YAML form as the **bare op-name** (e.g. `"radar_fetch_rss"`, `"intake_classify"`), matching the `identity.name` field ADR-OPSPEC-01 already locks. **The contract this ADR freezes is the YAML form, not the current `Plan.to_map/1` output.** M-RUNTIME-02's generated pack.yaml shim is bound to render the bare-name form (mapping `op_module → identity.name` via the `Liminara.Radar.Ops.Specs` builders at `runtime/apps/liminara_radar/lib/liminara/radar/ops/specs.ex`). Rejected alternatives: freeze the Elixir-prefixed string (leaks language convention into the contract); two-field `pack_id`+`op_name` (premature, since v1.0.0 is single-pack-only and the manifest already names the pack at `pack_id`); defer (delays the consumer-pressure forcing function).

- **Q3 — Input bindings: `literal` and `ref` only, no `init`.** Radar uses two binding shapes today: `{:literal, value}` and `{:ref, id, key}` / `{:ref, id}`. Admin-pack §9 introduces a third — `{:init, key}` — referencing reference data populated via the approved-next `Liminara.Pack.init/0` callback. Per D-2026-04-26-036 convention 4 (lock to actually-used set, expand additively), v1.0.0's schema admits only the two Radar-shaped bindings. Admin-pack's `:init` shape lands as a v1.1.0 additive bump when admin-pack materialises and the runtime callback ships (M-RUNTIME-02). The deferral is the cheapest forcing function against designing-for-Radar — admin-pack drives the v1.1.0 pressure, not anticipated speculation. Rejected alternative: admit `{:init, key}` now (over-commits the shape before consumer pressure validates it).

- **Q4 — Literal-value encoding: JSON-compatible scalars / objects / arrays, not Elixir inspect strings.** `Liminara.Plan.to_map/1` today serialises `{:literal, value}` as `{type: "literal", value: inspect(value)}` — an Elixir- inspect-formatted string (`'"hello"'`, `'%{...}'`). Python or any non-Elixir renderer cannot author or parse this format. The schema admits any JSON-compatible value (CUE's `_` top-type covers it). **As with Q2, the contract this ADR freezes is the YAML form, not the current `Plan.to_map/1` output.** M-RUNTIME-02's generator is bound to emit the JSON-compatible form. Rejected alternatives: freeze the inspect format (language leak); require all literals to be JSON-encoded strings (loses YAML's structural expressivity for object/array values).

- **Q5 — Ref output key: optional.** Radar uses both ref shapes today — whole-output (`{:ref, "compose_briefing"}` style — see `add_render_html` in radar.ex:165) and key-bound (`{:ref, "compose_briefing", "briefing"}` in the same node's fan-in). Both shapes appear in the `Liminara.Plan` deserialisation paths at plan.ex:140-150. The schema admits both via an optional `key?` on `#RefBinding`. Rejected alternatives: require key always (would reject Radar's existing whole-output refs); forbid key (would reject Radar's key-bound refs in `compose_briefing` and elsewhere).

- **Q6 — No plan-level identity.** Radar's plan today carries no `id`, `name`, or `version` field at the plan level — its identity is the run's identity, and the pack manifest already carries `pack_id` and `pack_version`. v1.0.0 admits no plan-level identity fields; the closed `#Plan` definition rejects any top-level key beyond `schema_version` and `nodes`. Rejected alternative: admit `plan_id`/`plan_version` (premature, no consumer demand).

- **Q7 — Single-plan per document; multi-plan deferred.** ADR-MULTIPLAN-01 (M-CONTRACT-04) is the home for multi-plan semantics (named plan sets, per-input plan selection, per-period plans). v1.0.0's schema is strictly **one plan per YAML document** — a `#Plan` is the top-level unifier. Multi-plan packs in admin-pack-shaped scenarios (one plan per period, one plan per file-watch trigger) drive the eventual v1.x.0 additive bump or v2.0.0 break, owned by ADR-MULTIPLAN-01. Rejected alternative: admit a `plans: [...]` block now (over-commits the shape before the multi-plan ADR's design lands).

- **Q8 — Static DAG only; no conditional/skip flags.** Radar's plan today is fully static — every node lands unconditionally. Admin-pack §9 shows `enabled: input.use_llm` as a per-node gating flag alongside inputs. v1.0.0's schema admits no conditional/skip shape; the closed `#Node` definition rejects any keys beyond `node_id`, `op`, and `inputs`. Like Q3 and Q7, this is consumer-pressure-deferred — when admin-pack materialises and the runtime semantics for plan-level conditionals are designed, an additive v1.x.0 bump or v2.0.0 break introduces the shape. Rejected alternative: admit `enabled: bool` now (over-commits before the runtime gating semantics are designed).

- **Q9 — Deps implicit via `inputs.ref` bindings, no separate `deps:` field.** `Liminara.Plan.check_dangling_refs/1` (plan.ex:183) walks `node.inputs` values to extract refs; there is no separate `deps:` list. The schema mirrors this: dependencies are derived from `#RefBinding.ref` values at runtime, not declared redundantly. Cycle detection and dangling-ref detection happen at PackLoader time per `Liminara.Plan.validate/1` (plan.ex:78), not at schema time — CUE cannot express either constraint as a unification rule. Rejected alternatives: require explicit `deps: [node_id]` per node (redundant, drift-prone); admit both `deps:` and `inputs.ref` (two sources of truth, the worse kind of redundancy).

- **Q10 — Top-level `schema_version: int`, required, integer- major.** Mirrors ADR-MANIFEST-01's discipline. ADR-EVOLUTION-01 (M-CONTRACT-04) operates on this field. Rendered separately from the manifest's `schema_version`: the manifest's field pins the manifest's machine-checkable shape, the plan's field pins the plan's. A pack at MANIFEST v1 can ship a PLAN at v1 today; if either bumps independently, each loader binding checks its respective field against its supported-major set. Rejected alternative: drop the field (would break ADR- EVOLUTION-01's compatibility-algorithm hook for plans).

- **Closed schemas throughout.** Every `#Definition` uses `close()` — a fixture with a typo'd or wishfully-added field fails vet. The two binding type discriminators (`"literal"`, `"ref"`) are fixed; new binding types or new top-level/node- level fields require an additive v1.x.0 bump or a v2.0.0 break per ADR-EVOLUTION-01.

## Consequences

**What becomes easier:**

- M-RUNTIME-02 (E-25) generates a Radar `pack.yaml`-companion plan rendering whose shape is validated by `cue vet` before the PackLoader binds to it; schema drift surfaces at authoring time rather than at runtime.
- The Python SDK (E-26) authors plan YAML directly without generating Elixir source; downstream Elixir consumers vet the same shape via the same schema.
- Admin-pack (E-22) ships plan YAML whose shape is constrained identically to Radar's; the §9 plan rendering becomes a v1.0.0- conformant document once the §9 shape's two forward-looking binding shapes (`:init`, `enabled:`) materialise as additive bumps.
- ADR-EVOLUTION-01 (M-CONTRACT-04) has a concrete plan-level field (`schema_version: int`) to operate on; the compatibility- algorithm shape is constrained in advance.

**What becomes harder:**

- `Liminara.Plan.to_map/1`'s current output is **not** directly schema-valid against this contract, because of the Q2 and Q4 divergences (op-module Elixir-string vs. bare op-name; Elixir- inspect literal vs. JSON-compatible value). M-RUNTIME-02's generator must perform the bare-op-name + JSON-literal rendering at write-time. Until M-RUNTIME-02 lands, no live `Plan.to_map/1` call site directly produces a fixture-valid document; the radar-realistic fixture in this bundle is the hand-rendered analogue.
- Adding a new binding type (`:init`, future `:env`, etc.) now requires an additive schema edit (and matching fixture) on top of the runtime edit. The contract-matrix wrap-time check catches drift but does not auto-update the schema.
- The shape duplication discipline (D-2026-05-02-038) does not apply to this schema — `plan/schema.cue` is self-contained and references no shape from another topic. The cross-topic binding the schema *does* carry — `op` matches a manifest's `ops[].execution_spec.identity.name` — is a runtime cross- document check, not a CUE import. PackLoader (E-25) enforces it at bind time.

**What we accept:**

- The plan is forward-looking on its admin-pack-shaped surface. The `:init` and `enabled:` shapes admin-pack §9 uses are deliberately deferred to additive v1.x.0 bumps. The risk is bounded: admin-pack itself does not yet exist as live code, so no live consumer is broken by their absence; when admin-pack materialises and surfaces concrete shape, the v1.1.0 bump is mechanical.
- The Q2 / Q4 divergence from `Plan.to_map/1` means a future `Plan.to_map/1` refactor (e.g. switching to bare-name op serialisation, switching literal serialisation to `Jason.encode_to_iodata`) brings the runtime shape into alignment with the schema. M-RUNTIME-02 may surface pressure to do this proactively; if it does, the alignment work is in scope for that milestone.

## Schema-backed contract

The `contract:` frontmatter block names the bundle. Each piece tests a different property of the contract:

- **`schema`** — `docs/schemas/plan/schema.cue`. The authoritative shape. Cited in the `plan-as-data` row of `docs/architecture/indexes/contract-matrix.md` (added by M-CONTRACT-02's matrix-pass).

- **`fixtures`** — `docs/schemas/plan/fixtures/v1.0.0/`. Four valid fixtures (`single-op-no-deps.yaml` — the boundary- edge minimal plan; `linear-chain.yaml` — three-node a → b → c; `diamond.yaml` — a → {b, c} → d exercising fan-out + fan-in with the optional ref-key distinction; `radar-realistic.yaml` — the worked example, the YAML rendering of `Radar.plan/1` for a 2-source input; `bookkeeping-admin-pack-shape.yaml` — the admin-pack §9 plan rendered with its two forward-looking binding shapes elided to v1.0.0-admissible forms). Seven invalid fixtures, each exercising a distinct violation class: missing required `schema_version`, `nodes` empty list, node_id empty string, node_id over the 63-char cap, binding `type` out of the closed `{"literal", "ref"}` enum, extra top-level field beyond the close()d shape, `op` empty string.

- **`worked_example`** — the realistic fixture `docs/schemas/plan/fixtures/v1.0.0/valid/radar-realistic.yaml` is the worked example. Its YAML body is the ADR's worked example verbatim; the Worked example section below quotes the structural shape — header plus a representative slice of the 13-node DAG — without modification (the full fixture lives in the cohort).

- **`reference_implementation`** — [`runtime/apps/liminara_radar/lib/liminara/radar.ex:52`](../../runtime/apps/liminara_radar/lib/liminara/radar.ex) is the existing implementation today (Radar's `plan/1` callback returning a `%Liminara.Plan{}` struct). The YAML rendering deadline is M-RUNTIME-02 (E-25) + `runtime/apps/liminara_radar/pack.yaml` (the generated pack.yaml shim renders the plan into the contracted YAML form per Q2 and Q4). The dual citation reflects the Q2/Q4 design choice: today's Elixir term shape and tomorrow's contracted YAML shape are both load-bearing — neither alone captures the full reference-impl binding.

- **`schema_version`** — `1.0.0` (the cohort label, not the per-plan integer field). The first frozen cohort. Bumping this requires either an additive change (minor bump, fixtures stay in `v1.0.0/`, new fixtures land in `v1.1.0/`) or a breaking change (major bump + deprecation ADR per ADR-EVOLUTION-01 when it lands in M-CONTRACT-04).

### Worked example

The Radar plan for a 2-source input (one RSS source `news_se`, one web source `tech_eu`) — 13 nodes, mixing literal and ref bindings, with both whole-output and key-bound ref shapes. The full plan lives at [`docs/schemas/plan/fixtures/v1.0.0/valid/radar-realistic.yaml`](../schemas/plan/fixtures/v1.0.0/valid/radar-realistic.yaml); the structural shape — header + a representative slice covering fetch (literal binding), collect (key-bound ref fan-in), normalize (simple key ref), dedup (multiple literal kinds + key ref), and the tail render (single key ref) — is reproduced inline below.

```yaml
schema_version: 1
nodes:
  # Fetch nodes — dynamic node_ids (`fetch_${source_id}`),
  # op selected by source type (rss → radar_fetch_rss).
  # Source description carried as a JSON-compatible literal map.
  - node_id: "fetch_news_se"
    op: "radar_fetch_rss"
    inputs:
      source:
        type: "literal"
        value:
          id: "news_se"
          type: "rss"
          url: "https://example.se/feed.xml"
          enabled: true

  # Collect — fan-in from each fetch node by `result` output key.
  - node_id: "collect_items"
    op: "collect_items"
    inputs:
      fetch_news_se:
        type: "ref"
        ref: "fetch_news_se"
        key: "result"
      fetch_tech_eu:
        type: "ref"
        ref: "fetch_tech_eu"
        key: "result"

  # Normalize — single key-bound ref into the items output.
  - node_id: "normalize"
    op: "radar_normalize"
    inputs:
      items:
        type: "ref"
        ref: "collect_items"
        key: "items"

  # Dedup — mixes a key-bound ref with multiple literal kinds
  # (string, integer-as-string for the dims field).
  - node_id: "dedup"
    op: "radar_dedup"
    inputs:
      items:
        type: "ref"
        ref: "embed"
        key: "items"
      lancedb_path:
        type: "literal"
        value: "/var/lib/liminara/radar/lancedb"
      dims:
        type: "literal"
        value: "256"

  # … 8 further nodes elided here; full 13-node fixture lives in
  # docs/schemas/plan/fixtures/v1.0.0/valid/radar-realistic.yaml.

  # Render HTML — terminal node, single key-bound ref.
  - node_id: "render_html"
    op: "render_html"
    inputs:
      briefing:
        type: "ref"
        ref: "compose_briefing"
        key: "briefing"
```

What each part means in domain terms:

- **`schema_version: 1`** — the plan binds to schema-cohort generation 1. ADR-EVOLUTION-01 (M-CONTRACT-04) operates on this field independently of ADR-MANIFEST-01's same-named field.
- **`fetch_news_se` / `fetch_tech_eu` node_ids** — dynamically composed at plan-build time from each source's `id` field (`build_fetch_plan/1` at radar.ex:69 emits `"fetch_#{source["id"]}"`). The 1..63 length constraint admits every realistic source-id flavour.
- **`op: "radar_fetch_rss"`** — the bare op-name matching `Liminara.Radar.Ops.FetchRss.execution_spec().identity.name`. The PackLoader (E-25) resolves this to the live op module via the manifest at bind time.
- **`type: "literal"` with structured `value:`** — the JSON-compatible literal payload (a map for the source description, a string for the path, a string-encoded integer for `dims`). The schema's `_` top-type admits any YAML-structurable shape.
- **`type: "ref"` with `ref:` + optional `key:`** — both whole-output and key-bound ref shapes appear in this fixture. The optional `key:` lets a single source node provide multiple named outputs (`collect_items` provides both `items` and `source_health`; `dedup` provides `result`).

The admin-pack-shaped fixture ([`bookkeeping-admin-pack-shape.yaml`](../schemas/plan/fixtures/v1.0.0/valid/bookkeeping-admin-pack-shape.yaml)) exercises the same schema with a different concrete pack — 15 nodes drawn from the per-period bookkeeping plan in `bookkeeping-pack-on-liminara.md` §9, with the §9 source's two forward-looking binding shapes elided to v1.0.0-admissible forms (the `apply_no_doc` node's `{:init, :no_doc_patterns}` binding becomes an explicit literal pattern list; the `llm_escalation` node's `enabled: input.use_llm` per-node gate is omitted, the node unconditionally present).

### Reference implementation

**Existing implementation** (per Assertion 4 in `.ai-repo/rules/contract-design.md`):

[`runtime/apps/liminara_radar/lib/liminara/radar.ex:52`](../../runtime/apps/liminara_radar/lib/liminara/radar.ex) — `Liminara.Radar.plan/1` returns a `%Liminara.Plan{}` struct whose content is what the worked example renders as YAML. The struct shape is defined at [`runtime/apps/liminara_core/lib/liminara/plan.ex:11`](../../runtime/apps/liminara_core/lib/liminara/plan.ex) (`%Liminara.Plan{nodes: map(), insert_order: [String.t()]}`) with the per-node `Node` shape at plan.ex:14 (`%Node{node_id, op_module, inputs}`). The serialisation pair `Liminara.Plan.to_map/1` (plan.ex:111) and `from_map/1` (plan.ex:128) renders this term form to/from a JSON-encodable map; that map is the closest live analogue to the YAML form this ADR freezes, with the Q2 / Q4 divergences flagged in Decision above.

**Scheduled-to-exist implementation**:

`runtime/apps/liminara_radar/pack.yaml`, generated by M-RUNTIME-02 (E-25)'s Radar generated-`pack.yaml` shim. The file does not yet exist; M-RUNTIME-02 is bound to ship it at the shape this schema freezes, including the bare-op-name (Q2) and JSON-compatible literal (Q4) renderings — not the current `Plan.to_map/1` output verbatim. The cross-binding is recorded as a forward dependency: when M-RUNTIME-02 is spec'd (it has not yet been authored at this ADR's write time per AC10's "milestones not yet spec'd" allowance), its spec must include an acceptance criterion citing this ADR's schema as the constraint the generated file satisfies.

**Live-source primary citations** (alongside both implementations, per the AC10 rubric — these are the live runtime analogues that constrain the schema's content):

- [`runtime/apps/liminara_core/lib/liminara/plan.ex`](../../runtime/apps/liminara_core/lib/liminara/plan.ex) — the `Liminara.Plan` module. Defines the struct shape, the Node sub-struct, the input-binding tuple shapes (`{:literal, value}` / `{:ref, id}` / `{:ref, id, key}`), and the `to_map/1` + `from_map/1` serialisation pair the YAML form mirrors (with Q2/Q4 divergences).
- [`runtime/apps/liminara_core/lib/liminara/pack.ex`](../../runtime/apps/liminara_core/lib/liminara/pack.ex) — the `Liminara.Pack` behaviour. The `plan/1` callback declaration whose return value the manifest's plan field renders.
- [`runtime/apps/liminara_radar/lib/liminara/radar.ex`](../../runtime/apps/liminara_radar/lib/liminara/radar.ex) — Radar's `Liminara.Pack` implementation. The `plan/1` callback at line 52 is the existing reference; the per-source-type `op_for_type/1` switch (line 170-172) and the dynamic `node_id` composition in `build_fetch_plan/1` (line 69) are the source of the fixture's two `fetch_${source_id}` nodes.

### Anchored admin-pack citation

**Secondary reference (per Assertion 1 in `.ai-repo/rules/contract-design.md`):**

`admin-pack/v2/docs/architecture/bookkeeping-pack-on-liminara.md §9 — The Plan — DAG construction` is the load-bearing anchor. The section presents a concrete 15-node bookkeeping pack plan showing per-period DAG construction with `Plan.add_node/4` calls mirroring the Elixir `Liminara.Plan` API. The shapes the section exercises overlap with this ADR's schema in three concrete ways:

1. **Identical `node_id` + `op` + `inputs` structure.** Each `Plan.add_node` call carries an author-assigned string `node_id`, an op module reference, and an inputs map — exactly the three fields the `#Node` shape freezes. The `bookkeeping-admin-pack-shape.yaml` fixture in this bundle's cohort renders 15 of those nodes as YAML and unifies against the v1.0.0 schema.

2. **Identical literal + ref binding shapes.** The §9 plan uses `{:ref, "node_id"}` and `{:ref, "node_id", :output_key}` bindings (e.g. `{:ref, "extract_statement", :unmatched}`), which this ADR's `#RefBinding` admits. Literal bindings appear as map values (e.g. `gate_type: "match_review"` on the `review_gate` node), which this ADR's `#LiteralBinding` admits.

3. **Two forward-looking shapes deferred per Q3 and Q8.** The §9 plan introduces `{:init, key}` references (e.g. `patterns: {:init, :no_doc_patterns}` on `apply_no_doc`) and per-node gating flags (e.g. `enabled: input.use_llm` on `llm_escalation`). v1.0.0's schema does not admit these; they are deferred to additive v1.x.0 bumps when admin-pack materialises and the runtime semantics are designed.

A complementary anchor — `admin-pack/v2/docs/architecture/bookkeeping-pack-on-liminara.md §9 → "Plan style: per-period vs per-item"` — articulates the multi-plan pressure that ADR-MULTIPLAN-01 (M-CONTRACT-04) will own. The §9 sub-section frames per-period vs per-item plan modelling as a shape-design choice, recommending per-period outer plans with item-flow modelled as DAG semantics within. This ADR's Q7 deferral (single-plan-per-document v1.0.0; multi-plan deferred) is the mirror of that §9 sub-section's open shape question.

This citation is admin-pack-secondary to Radar-primary. Radar today exercises the plan contract through its `Liminara.Radar.plan/1` callback (the live analogue per the existing-implementation citation above); admin-pack's bookkeeping flow will exercise the same contract once authored. The two-pack pressure prevents this ADR from being a one-pack abstraction.

## Validation

The schema, fixtures, and worked example all vet locally:

```sh
$ ./scripts/cue-vet
$ echo $?
0
```

Field-for-field correspondence between the schema and the live `Liminara.Plan` shape is the contract-matrix wrap-time check. A future rename in `plan.ex` (e.g. dropping the optional `key` field on the ref tuple) that doesn't update `schema.cue` is caught by the matrix audit before the milestone wraps.

The schema-evolution loop in `scripts/cue-vet` walks every fixture in `docs/schemas/plan/fixtures/v1.0.0/` against the HEAD schema on every commit (via the pre-commit hook) and on every `scripts/cue-vet` no-args invocation. A schema change that breaks an existing fixture either reverts the change or lands a deprecation ADR + major version bump per ADR-EVOLUTION-01 (when M-CONTRACT-04 lands).

## References

- **Parent sub-epic spec:** `work/epics/E-24-contract-design/epic.md`
- **Owning milestone:** `work/epics/E-24-contract-design/M-CONTRACT-02-foundational-contracts.md`
- **Predecessor ADRs in this milestone:**
  - [`docs/decisions/0004-op-execution-spec.md`](./0004-op-execution-spec.md) — ADR-OPSPEC-01. The `op` field on each `#Node` matches the `identity.name` field this ADR locks.
  - [`docs/decisions/0005-port-wire-protocol.md`](./0005-port-wire-protocol.md) — ADR-WIRE-01.
  - [`docs/decisions/0006-replay-protocol.md`](./0006-replay-protocol.md) — ADR-REPLAY-01.
  - [`docs/decisions/0007-pack-manifest.md`](./0007-pack-manifest.md) — ADR-MANIFEST-01. The `schema_version: int` integer-major discipline mirrors this ADR's same-named field.
- **Forward-references (deferred to M-CONTRACT-04):**
  - ADR-MULTIPLAN-01 specifies multi-plan / plan-set semantics deferred per Q7. Its eventual write-up will cross-reference back.
  - ADR-EVOLUTION-01 specifies the compatibility algorithm over this ADR's `schema_version` field. Its eventual write-up will cross-reference back.
- **Contract-matrix index (row added by M-CONTRACT-02 wrap-pass):** `docs/architecture/indexes/contract-matrix.md`
- **Reviewer rule (the four assertions):** `.ai-repo/rules/contract-design.md`
- **Authoring overlay (Liminara bindings on the upstream skill):** `.ai-repo/skills/design-contract.md`
- **Decision log entries:**
  - `D-2026-04-22-028` — ADR working-keyword IDs in frontmatter (now superseded by D-030 on filename, retained for the `working_id:` convention).
  - `D-2026-04-23-030` — ADR filename `NNNN-<slug>.md`, ID `ADR-NNNN`. This ADR is `0008-pack-plan.md` per the convention; the working-keyword ID `ADR-PLAN-01` lives in `working_id:`.
  - `D-2026-04-26-036` — CUE encoding conventions inherited from ADR-OPSPEC-01's bundle.
  - `D-2026-04-26-037` — CUE struct-presence is shape-only; invalid fixtures use leaf-field violations.
  - `D-2026-05-02-038` — Cross-topic CUE shape duplication accepted; cross-schema imports deferred to ADR-EVOLUTION-01. Not exercised by this schema (plan/schema.cue is self-contained).
- **Live runtime sources mirrored:**
  - `runtime/apps/liminara_core/lib/liminara/plan.ex` — the `Liminara.Plan` module (struct, Node sub-struct, to_map/1, from_map/1, validate/1, the three input-binding tuple shapes).
  - `runtime/apps/liminara_core/lib/liminara/pack.ex` — the `Liminara.Pack` behaviour's `plan/1` callback declaration.
  - `runtime/apps/liminara_radar/lib/liminara/radar.ex` — Radar's `plan/1` implementation. The 13-node DAG, the dynamic `fetch_${source_id}` node ID composition, and the `op_for_type/1` switch are the source of the worked-example fixture.
- **Admin-pack secondary anchors (live content; not E-22-pending):**
  - `admin-pack/v2/docs/architecture/bookkeeping-pack-on-liminara.md §9 — The Plan — DAG construction`
  - `admin-pack/v2/docs/architecture/bookkeeping-pack-on-liminara.md §9 → "Plan style: per-period vs per-item"`
- **Approved-next architecture document:** `docs/architecture/01_CORE.md` (the `Liminara.Pack.init/0` reference-data callback whose `:init` binding shape is deferred per Q3).
