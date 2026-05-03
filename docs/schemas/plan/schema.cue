// plan/schema.cue
//
// Schema for ADR-PLAN-01: the plan-as-data contract.
//
// This schema specifies the YAML form of a Liminara pack's
// computation plan — the static, content-addressable description of
// the DAG of op invocations a `Liminara.Pack.plan/1` callback
// returns. Today, Radar expresses this content as a `%Liminara.Plan{}`
// struct returned from
// `runtime/apps/liminara_radar/lib/liminara/radar.ex:52`, with the
// canonical YAML rendering shape already produced by
// `Liminara.Plan.to_map/1`
// (`runtime/apps/liminara_core/lib/liminara/plan.ex:111`). The on-disk
// `pack.yaml`-companion plan rendering lands at M-RUNTIME-02 (E-25)
// as part of the Radar generated pack.yaml shim. Admin-pack's plan
// representation will conform to the same schema once admin-pack is
// authored (its plan-shape design is anchored to
// admin-pack/v2/docs/architecture/bookkeeping-pack-on-liminara.md §9).
//
// Source-of-truth bindings:
//   - runtime/apps/liminara_core/lib/liminara/plan.ex (the Plan
//     struct, Node sub-struct, and the to_map/1 + from_map/1
//     serialisation pair).
//   - runtime/apps/liminara_radar/lib/liminara/radar.ex (the
//     `plan/1` callback whose output the YAML form renders; the
//     closest live analogue today).
//   - runtime/apps/liminara_core/lib/liminara/pack.ex (the
//     `Liminara.Pack` behaviour's `plan/1` callback declaration).
//
// Conventions inherited (D-2026-04-26-036):
//   1. Single per-fixture entry shape: each fixture is one #Plan
//      document.
//   2. Atom-to-string disjunctions on closed enumerations (the
//      `type` discriminator on input bindings: "literal" | "ref").
//   3. Type-only encoding for derived fields. The schema does not
//      assert "every dep_id matches some other node's id" or "the
//      DAG has no cycles" — those are runtime invariants enforced
//      by `Liminara.Plan.validate/1` (plan.ex:78), not schema-
//      enforceable cross-field rules without leaving CUE.
//   4. Enum values lock to actually-used set, expand additively
//      (input binding types: "literal" | "ref" only; admin-pack's
//      forward-looking ":init" binding is deferred to v1.1.0
//      additively per Q&A 2026-05-02 Q3).
//   5. Optional Elixir-`nil` fields encoded as CUE `?:` optional
//      keys (ref binding's `key?` mirrors the absent-vs-present
//      output-key distinction in `{:ref, id}` vs `{:ref, id, key}`).
//
// D-2026-04-26-037 reminder: absent required struct bodies are NOT a
// schema-level violation class without `cue vet -c`. Invalid fixtures
// in this cohort use leaf-field violations.
//
// D-2026-05-02-038 — cross-topic shape duplication. This schema does
// NOT duplicate any shape from the other M-CONTRACT-02 topics; it is
// self-contained. The `ops_ref: string` field on each node is the
// bare op-name string that — at PackLoader (E-25) time — must match
// some `ops[].execution_spec.identity.name` declared in the pack's
// manifest (op-name presence is a runtime cross-document check, not
// a schema-enforceable constraint).
//
// schema_version field
// ====================
// Mirrors ADR-MANIFEST-01's discipline: integer-major, top-level,
// required, errors when absent. ADR-EVOLUTION-01 (M-CONTRACT-04)
// will operate on this field. A plan-document at the v1.x cohort
// declares `schema_version: 1`. Bumping the manifest's
// `schema_version` and the plan's `schema_version` is independent —
// a pack at MANIFEST v1 can ship a PLAN at v1; if PLAN bumps to v2
// before MANIFEST does (or vice versa), each loader binding checks
// its respective field against its supported-major set.
//
// Op reference: bare op-name, not Elixir module string
// =====================================================
// `Liminara.Plan.to_map/1` today serialises `op_module` as
// `Atom.to_string(node.op_module)` — yielding strings like
// "Elixir.Liminara.Radar.Ops.FetchRss". That shape is Elixir-internal
// and would leak Elixir-isms into Python-authored pack.yaml + admin-
// pack-authored plan.yaml. Per Q&A 2026-05-02 Q2, this schema
// freezes the YAML form as the bare op-name (matching the op's
// `execution_spec.identity.name` in the pack manifest), e.g.
// "radar_fetch_rss", "intake_scan". The Plan.to_map output is NOT
// directly schema-valid against this contract; M-RUNTIME-02's
// generated pack.yaml shim is bound to render the bare-name form
// (mapping op_module -> identity.name via the Specs builders at
// runtime/apps/liminara_radar/lib/liminara/radar/ops/specs.ex).
//
// Literal-value encoding: JSON-encodable, not Elixir inspect
// ===========================================================
// `Liminara.Plan.to_map/1` today serialises `{:literal, value}` as
// `inspect(value)` — a string in Elixir-inspect format ('"hello"',
// '%{...}'). That shape is unparseable by Python or any non-Elixir
// renderer. Per Q&A 2026-05-02 Q4, this schema admits any JSON-
// compatible scalar / object / array as the literal `value` (the
// CUE `_` top-type covers it; runtime authors are responsible for
// emitting JSON-compatible values from their pack-author-side
// renderer). M-RUNTIME-02's generator is bound to emit the
// JSON-compatible form, not Elixir inspect.

package plan

// ─── Top-level fixture entry: one plan document. ───────────────────

#Plan: close({
	// Per-plan schema-cohort version. Required.
	// Integer-major. ADR-EVOLUTION-01 (M-CONTRACT-04) operates on this
	// field. Mirrors the discipline locked in ADR-MANIFEST-01 — see
	// `docs/schemas/manifest/schema.cue` for the full sub-decisions.
	schema_version: int & >=1

	// Ordered list of nodes, mirroring the `insert_order`-walked
	// shape that `Liminara.Plan.to_map/1` produces. Order is
	// significant: `Plan.from_map/1` reconstructs the plan by
	// folding nodes back in declaration order. Required; at least
	// one node.
	nodes: [...#Node] & [_, ...]
})

#Node: close({
	// Author-assigned node identifier. Unique within this plan.
	// Non-empty string with a 63-character cap (DNS-label limit, same
	// rationale as MANIFEST.pack_id). No regex constraint — Radar
	// composes node IDs dynamically (e.g. "fetch_${source_id}" at
	// `runtime/apps/liminara_radar/lib/liminara/radar.ex:73`); a
	// strict snake_case regex would reject legitimate authoring
	// styles. Per Q&A 2026-05-02 Q1.
	node_id: string & =~"^.{1,63}$" & !=""

	// The op this node invokes, named as the op's bare
	// `execution_spec.identity.name` (e.g. "radar_fetch_rss",
	// "intake_classify"). At PackLoader (E-25) time this string
	// must resolve to an `ops[].execution_spec.identity.name` in
	// the pack's manifest — a cross-document check the loader
	// performs at bind time, not a schema-enforceable rule. Per
	// Q&A 2026-05-02 Q2.
	op: string & !=""

	// Map of input-name -> input-binding. Each binding is either a
	// literal value or a reference to another node's output.
	// Required key; empty map permitted (a node with no inputs is
	// the typical first-in-DAG shape).
	inputs: {[string]: #InputBinding}
})

// Input binding: discriminated by `type`. The two shapes mirror
// `Liminara.Plan`'s `{:literal, value}` and `{:ref, id, key}` /
// `{:ref, id}` Elixir tuple forms (plan.ex:140-150 deserialisation,
// plan.ex:256-262 serialisation). Per Q&A 2026-05-02 Q3, only these
// two binding types are admitted in v1.0.0 — admin-pack's forward-
// looking `{:init, key}` shape is deferred to a v1.1.0 additive bump
// when admin-pack materialises and pressure-tests it.
#InputBinding: #LiteralBinding | #RefBinding

#LiteralBinding: close({
	type: "literal"
	// JSON-encodable value: scalar, object, or array. The schema
	// admits the `_` top-type because the literal payload is
	// op-specific; a config map for one op, a number for another,
	// a string for a third. Runtime authors are responsible for
	// emitting JSON-compatible values (see schema preamble for
	// the rationale against Elixir-`inspect` rendering). Per Q&A
	// 2026-05-02 Q4.
	value: _
})

#RefBinding: close({
	type: "ref"
	// The `node_id` of another node in this plan whose output this
	// binding consumes. PackLoader (E-25) checks dangling-ref at
	// bind time (mirroring `Liminara.Plan.check_dangling_refs/1` at
	// plan.ex:183); this schema validates only the field's shape.
	ref: string & !=""
	// Optional output key — names a specific named output of the
	// referenced node (e.g. `{ref: "extract_statement", key: "unmatched"}`).
	// Absent → consume the referenced node's whole output. Mirrors
	// the `{:ref, id, key}` / `{:ref, id}` Elixir tuple variants.
	// Per Q&A 2026-05-02 Q5.
	key?: string & !=""
})

// Top-level: every YAML fixture under fixtures/v1.0.0/ unifies with
// this constraint. `close()` so fixtures with stray top-level keys
// are rejected.
#Plan
