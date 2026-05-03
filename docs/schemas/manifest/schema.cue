// manifest/schema.cue
//
// Schema for ADR-MANIFEST-01: the pack manifest contract.
//
// This schema specifies the YAML form of a Liminara pack manifest:
// the static, content-addressable description of a pack's identity,
// version, and op set. Today, Radar expresses this content as a
// `Liminara.Pack` Elixir behaviour module
// (`runtime/apps/liminara_radar/lib/liminara/radar.ex`); the YAML
// `pack.yaml` form lands at M-RUNTIME-02 (E-25) as the Radar
// generated pack.yaml shim. Admin-pack's pack.yaml will conform to
// the same schema once admin-pack is authored (E-22-pending).
//
// Source-of-truth bindings:
//   - runtime/apps/liminara_core/lib/liminara/pack.ex (the four
//     callbacks: id/0, version/0, ops/0, plan/1).
//   - runtime/apps/liminara_radar/lib/liminara/radar.ex (the closest
//     live analogue to a Radar pack.yaml: the Pack-implementing
//     module's `id`, `version`, and `ops` declarations).
//   - runtime/apps/liminara_radar/lib/liminara/radar/ops/*.ex (each
//     op's execution_spec/0 — what the per-op declaration in the
//     manifest must accommodate).
//   - runtime/apps/liminara_core/lib/liminara/execution_spec.ex (the
//     ExecutionSpec struct the per-op declaration mirrors —
//     duplicated here per D-2026-05-02-038 rather than imported).
//
// Conventions inherited (D-2026-04-26-036):
//   1. Single per-fixture entry shape: each fixture is one #Manifest
//      document.
//   2. Atom-to-string disjunctions on closed enumerations
//      (determinism class, executor, network capability).
//   3. Type-only encoding for derived fields. The schema does not
//      assert "the runtime executor matches the determinism class"
//      or any other cross-derivation rule.
//   4. Enum values lock to actually-used set, expand additively
//      (network: "none" | "tcp_outbound", same as OPSPEC).
//   5. Optional Elixir-`nil` fields encoded as CUE `?:` optional
//      keys (timeout_ms?, etc.).
//
// D-2026-04-26-037 reminder: absent required struct bodies are NOT a
// schema-level violation class without `cue vet -c`. Invalid fixtures
// in this cohort use leaf-field violations instead.
//
// D-2026-05-02-038 — cross-topic shape duplication. The #ExecutionSpec
// shape below is duplicated byte-identically from
// op-execution-spec/schema.cue#ExecutionSpec; source-of-truth is
// runtime/apps/liminara_core/lib/liminara/execution_spec.ex. Drift
// between the two CUE definitions is caught by the schema-evolution
// loop walking every fixture against every HEAD schema. The
// duplicate-with-comment convention is in force until ADR-EVOLUTION-01
// (M-CONTRACT-04) lands a `#common` package architecture.
//
// schema_version field — the AC5 answer
// =====================================
// A pack manifest's top-level `schema_version` is the contract field
// ADR-EVOLUTION-01 (M-CONTRACT-04) operates on. Concrete choices:
//
//   - Format: integer-major. A manifest that targets schema generation
//     v1.x.y declares `schema_version: 1`. ADR-EVOLUTION-01's eventual
//     compatibility algorithm compares the integer against the loader's
//     supported-major set. Rejected alternative: a semver string
//     (`"1.0.0"`). False precision — a v1.0 vs v1.2 manifest is not
//     incompatible if every change between them is additive (which is
//     the only kind of change v1.x permits per ADR-EVOLUTION-01).
//     Tracking patch-level on the manifest is bookkeeping noise.
//   - Placement: top-level key. Equal-tier with `pack_id` and
//     `pack_version`. Not nested under a `meta:` block.
//   - Required vs optional: required. A manifest without
//     `schema_version` is rejected by the loader at ADR-EVOLUTION-01
//     time; the cohort version is the binding hook for compatibility.
//   - Behaviour when absent: error, citing this ADR + ADR-EVOLUTION-01.
//     A default value (e.g. silently bind absent → 1) makes upgrades
//     dangerous when v2 lands — manifests authored against v1 with the
//     field omitted would silently bind to v2's stricter rules. The
//     error is the safer discipline.
//
// `pack_version` is the pack author's semver-shaped string for the pack
// itself (e.g. Radar's "0.1.0"). Distinct from `schema_version`, which
// pins the manifest's machine-checkable shape.
//
// init declaration (forward-looking)
// ==================================
// The `init` field is approved-next per `docs/architecture/01_CORE.md`
// and admin-pack/v2/docs/architecture/bookkeeping-pack-on-liminara.md
// §3 — `init/0` returns a versioned snapshot of reference data
// (vendor maps, classification markers, prompt templates, etc.). The
// schema admits an optional `init` block today so a pack can declare
// the contract surface ahead of the runtime callback shipping; the
// runtime ignores the field until M-RUNTIME-02's loader binds to it.
// Field is OPTIONAL — packs that don't need reference data omit it.

package manifest

// Schema cohort: v1.0.0. Fixtures live under fixtures/v1.0.0/ and
// pair with this HEAD schema. Bumping the cohort (additive in
// v1.1.0; breaking in v2.0.0 with a deprecation ADR) is governed by
// ADR-EVOLUTION-01 (M-CONTRACT-04) when it lands.
//
// No package-level CUE constant for the cohort version: the
// directory name `fixtures/v1.0.0/` is the canonical cohort
// identifier; nothing reads a CUE-side constant. Other M-CONTRACT-02
// schemas (op-execution-spec, wire-protocol, replay-protocol) carry
// a documentary `schema_version: "1.0.0"` field at top level; this
// schema cannot, because the per-manifest `schema_version` integer
// field below would collide on unification. Per Q&A 2026-05-02 (Q8)
// the field is dropped here in favour of this comment rather than
// renamed to `_schema_version`.

// ─── Top-level fixture entry: one pack manifest. ───────────────────

#Manifest: close({
	// Per-manifest schema-cohort version (the AC5 field). Required.
	// Integer-major. ADR-EVOLUTION-01 (M-CONTRACT-04) operates on this
	// field. Absent → loader error; no default.
	schema_version: int & >=1

	// Pack identifier as the YAML rendering of `Liminara.Pack.id/0`.
	// Elixir-side this is an atom (`:radar`, `:bookkeeping`); on the
	// wire it is a snake_case lowercase string. Required.
	//
	// Regex shape: leading lowercase letter, then optional
	// alphanumeric-segments separated by single underscores. Forbids
	// trailing underscore and double underscores (typo-aesthetic and
	// Python-dunder collision respectively). The 63-character cap is
	// the DNS-label limit — forward-compatible with pack IDs flowing
	// into URLs, filesystem paths, or registry keys without
	// truncation. Per Q&A 2026-05-02 (Q5); tightening after v1.0.0
	// would be a v2.0.0 break.
	pack_id: string & =~"^[a-z]([a-z0-9]+(_[a-z0-9]+)*)?$" & =~"^.{1,63}$"

	// Pack-author-controlled version string. Semver-shaped (with an
	// optional pre-release suffix). Distinct from `schema_version`.
	// Required.
	pack_version: string & =~"^[0-9]+\\.[0-9]+\\.[0-9]+(-[a-z0-9.]+)?$"

	// List of op declarations the pack provides. Each entry contains
	// the YAML form of `Liminara.Op.execution_spec/0`. Required;
	// at least one op.
	ops: [...#OpDeclaration] & [_, ...]

	// Optional human-readable description of the pack — one or two
	// sentences for log lines, error contexts, and future
	// pack-registry surfaces. Free-form string, plaintext (not
	// Markdown — Markdown is reserved for a future v1.x bump if a
	// renderer-side consumer demands it). No length cap. Per Q&A
	// 2026-05-02 (Q4) this is the one conventional-manifest field
	// included in v1.0.0; `maintainers`, `tags`, `license`, and
	// `plan_module` are deferred to additive v1.1.0+ bumps when
	// consumers materialize.
	description?: string

	// Optional reference-data declaration, surfacing the
	// approved-next `Liminara.Pack.init/0` callback per
	// docs/architecture/01_CORE.md and admin-pack §3. Packs that do
	// not declare init data omit this block entirely.
	init?: #InitDeclaration
})

#OpDeclaration: close({
	// The op's full execution spec as it would land in YAML. Mirrors
	// the runtime `Liminara.ExecutionSpec` struct returned by the op's
	// `execution_spec/0`.
	execution_spec: #ExecutionSpec
})

#InitDeclaration: close({
	// Authoring-time version of the reference-data snapshot, bumped
	// when the pack's reference data changes. Replays use the version
	// that existed at the time of the original run (per admin-pack
	// §3). Free-form string; no semver discipline (the value is
	// content-addressed alongside the rest, so the string is a label
	// not a comparator).
	version: string & !=""

	// Names of the reference-data keys the pack populates at init
	// time (e.g. ["vendor_canonical_map", "classification_markers"]).
	// Not used by the loader for validation today; surfaces the
	// declared keys for human review and for future tooling.
	reference_data_keys: [...string]
})

// ─── ExecutionSpec ─────────────────────────────────────────────────
//
// Duplicated from op-execution-spec/schema.cue#ExecutionSpec
// (D-2026-05-02-038). Source-of-truth:
// runtime/apps/liminara_core/lib/liminara/execution_spec.ex.
// Drift between the two CUE definitions is caught by the
// schema-evolution loop walking every fixture against HEAD schemas.

#ExecutionSpec: close({
	identity:    #Identity
	determinism: #Determinism
	execution:   #Execution
	isolation:   #Isolation
	contracts:   #Contracts
})

#Identity: close({
	name:    string & !=""
	version: string & !=""
})

#Determinism: close({
	class:         "pure" | "pinned_env" | "recordable" | "side_effecting"
	cache_policy:  "content_addressed" | "content_addressed_with_environment" | "none"
	replay_policy: "reexecute" | "replay_recorded" | "skip"
})

#Execution: close({
	executor:                   "inline" | "task" | "port"
	entrypoint:                 string & !=""
	timeout_ms?:                int & >0
	requires_execution_context: bool
})

#Isolation: close({
	env_vars:             [...string]
	network:              "none" | "tcp_outbound"
	bootstrap_read_paths: [...string]
	runtime_read_paths:   [...string]
	runtime_write_paths:  [...string]
})

#Contracts: close({
	inputs:    {[string]: _}
	outputs:   {[string]: _}
	decisions: close({may_emit: bool})
	warnings:  close({may_emit: bool})
})

// Top-level: every YAML fixture under fixtures/v1.0.0/ unifies with
// this constraint. `close()` so fixtures with stray top-level keys
// are rejected.
#Manifest
