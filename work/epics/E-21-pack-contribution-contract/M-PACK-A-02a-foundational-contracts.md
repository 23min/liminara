---
id: M-PACK-A-02a
epic: E-21-pack-contribution-contract
parent: E-21a-contract-design
status: draft
depends_on: M-PACK-A-01
---

# M-PACK-A-02a: Foundational contracts (5 ADRs)

## Goal

Ship the five foundational ADRs every other E-21 sub-epic blocks on — manifest, plan-as-data, op execution spec, run-level replay protocol, and port wire protocol — each with its CUE schema, valid + invalid fixtures, worked example, and named reference implementation. Ship the schema-evolution compat-check loop as part of this milestone, walking the first populated `v1.0.0/` fixture cohort and every cohort that follows.

## Context

E-21a sets up the contract-design pipeline; M-PACK-A-01 has shipped the local tooling that loop runs on (CUE in the devcontainer, `cue vet` invocation script, pre-commit hook, `docs/schemas/<topic>/fixtures/v<N>/` directory layout convention, `.ai-repo/skills/design-contract.md`, `.ai-repo/rules/contract-design.md`). The schema-evolution loop itself was deferred to this milestone — without first schemas it had nothing to walk.

Two upstream contracts feed into the ADRs this milestone produces:

- **M-TRUTH-01 (E-20, merged)** locked the canonical Elixir-side execution contract: `execution_spec/0`'s five sections (`identity`, `determinism`, `execution`, `isolation`, `contracts`), the `OpResult` shape, and the warning struct. ADR-OPSPEC-01 codifies that contract as CUE — schema-freezing only, with no runtime semantics changes.
- **E-19 (Warnings & Degraded Outcomes, merged)** locked the warning-bearing terminal-event taxonomy: `Run.Server.finish_run/2` emits `run_completed` for `:success`, `run_partial` for `:partial`, `run_failed` for `:failed` (per D-2026-04-20-025). ADR-OPSPEC-01 codifies this taxonomy alongside the warning shape.

The five ADRs must land together because every downstream sub-epic spec already cites them: E-21b's PackLoader binds to ADR-MANIFEST-01 + ADR-PLAN-01 + ADR-WIRE-01 + ADR-REPLAY-01; E-21c's SDK binds to ADR-MANIFEST-01 + ADR-PLAN-01 + ADR-OPSPEC-01 + ADR-WIRE-01; E-21d's Radar extraction must satisfy all five.

Provenance recording — pack_version + git_commit_hash captured in a run's initial event, used by ADR-REPLAY-01's worked example as a hand-off to that mechanism — is a separate M-PACK-B-01b acceptance criterion, not this milestone's concern. ADR-REPLAY-01 cross-references it without specifying it. Pack-version skew during replay (replaying a run authored against pack version X with pack version Y loaded) is explicitly out of scope and pointed at `work/gaps.md` → "Cross-version pack replay semantics."

## Acceptance Criteria

1. **Every ADR listed in the parent epic's *ADRs produced* table for this milestone exists at its `docs/decisions/NNNN-<slug>.md` path** with the appropriate Nygard form (Context → Decision → Consequences + Nygard-standard status vocabulary), per `.ai-repo/rules/liminara.md` "Decision records" section. The set is: ADR-MANIFEST-01, ADR-PLAN-01, ADR-OPSPEC-01, ADR-REPLAY-01, ADR-WIRE-01. Each ADR's frontmatter carries the working keyword ID (e.g. `working_id: ADR-MANIFEST-01`) for cross-reference per D-2026-04-22-028. The on-disk `NNNN` is the next available monotonic four-digit number at write time per D-2026-04-23-030 (current high-water mark at this spec's write is `0003`).

2. **Each ADR ships with its CUE schema, valid fixtures, invalid fixtures, worked example, and named reference implementation citation.** Concretely, for every ADR in the set above:
   - The CUE schema lives at `docs/schemas/<topic>/schema.cue` with `<topic>` matching the contract surface (`manifest`, `plan`, `op-execution-spec`, `replay-protocol`, `wire-protocol`).
   - Valid fixtures live under `docs/schemas/<topic>/fixtures/v1.0.0/` and demonstrate at least one realistic shape and at least one boundary-edge shape.
   - Invalid fixtures live alongside the valid ones (e.g. `docs/schemas/<topic>/fixtures/v1.0.0/invalid/`) and demonstrate the violations `cue vet` rejects, with one fixture per major violation class the schema enforces.
   - The ADR body contains a worked example — one or two realistic snippets — whose YAML form matches a committed valid fixture verbatim.
   - The ADR cites a **named reference implementation**, either existing or scheduled to a specific milestone with a matching acceptance criterion in that milestone's spec. "TBD" is unacceptable; "examples/file_watch_demo built in M-PACK-C-03" is acceptable.

3. **`cue vet` passes against every fixture under `docs/schemas/*/fixtures/v1.0.0/`.** Valid fixtures pass; invalid fixtures pass when paired with an `invalid` assertion mode or the equivalent (the ADR + fixture-layout convention in M-PACK-A-01 specifies which mechanism is used). The check script M-PACK-A-01 shipped invokes the validator without arguments and exits non-zero on any failure.

4. **The schema-evolution compat-check loop is implemented and invocable locally + via pre-commit**, per the parent epic's "Schema-evolution check — specification" subsection. Concretely:
   - The loop walks `docs/schemas/<topic>/fixtures/v<N>/` for every `<topic>` and validates every fixture against the HEAD `docs/schemas/<topic>/schema.cue`.
   - The loop runs in the same hook mechanism `cue vet` uses (a single make-target / script that contributors do not have to remember the invocation for).
   - On failure, the output identifies the failing fixture path, the schema path, and the underlying CUE error in the form `<fixture path> fails against <topic>.cue at <schema path>: <CUE error>`.
   - Backward compatibility (historical fixtures against HEAD schemas) is enforced; forward compatibility (current fixtures against historical schemas) is not — the loop does not look up historical schemas.
   - A test fixture (one breaking schema change against an existing fixture) demonstrates that the failure semantics produce the expected output.

5. **ADR-MANIFEST-01 specifies the `schema_version` field that ADR-EVOLUTION-01 will operate on.** The ADR specifies the field's format (single-major-version integer or semver string — the ADR picks one and justifies), placement in the manifest (top-level key vs. nested), required-vs-optional status, and the runtime behaviour when the field is absent (default value vs. error). The ADR cross-references ADR-EVOLUTION-01 explicitly even though that ADR lands later in M-PACK-A-02c, with text of the form: "ADR-EVOLUTION-01 specifies the compatibility algorithm over this field." ADR-EVOLUTION-01's eventual write-up will cross-reference back.

6. **ADR-OPSPEC-01 codifies the canonical execution contract from M-TRUTH-01 plus the terminal event taxonomy from E-19** (`run_completed`, `run_partial`, `run_failed` per D-2026-04-20-025). Concretely:
   - The CUE schema mirrors M-TRUTH-01's five-section `execution_spec/0` (`identity`, `determinism`, `execution`, `isolation`, `contracts`) field-for-field; field names and shapes match `runtime/apps/liminara_core/lib/liminara/execution_spec/` source of truth.
   - The schema codifies the warning struct (per `Liminara.Warning`'s shape), the `OpResult` shape (per `Liminara.OpResult`), and the `Run.Result` aggregation fields locked by M-WARN-01 (`warning_count`, `degraded_nodes`, derived `degraded`).
   - The schema codifies the three terminal event types as a closed enumeration; their payload shapes (including `run_partial`'s `warning_summary`) match the live Elixir source.
   - The ADR cites M-TRUTH-01's spec (`work/done/E-20-execution-truth/M-TRUTH-01-execution-spec-outcome-design.md`) as primary upstream and D-2026-04-20-025 + E-19 as the terminal-event source.
   - This ADR is schema-freezing only; it does not change runtime semantics or introduce shims.

7. **ADR-REPLAY-01 specifies the run-level replay protocol** — event-log walk order, decision injection, partial-run re-entry, and the replay `Run.Result` shape — as a documentation of the protocol the live runtime already implements. Concretely:
   - The ADR documents the event-log walk performed by `Liminara.Run.Server.rebuild_from_events/2` and the result reconstruction performed by `result_from_event_log/1` (see `runtime/apps/liminara_core/lib/liminara/run/server.ex`).
   - The ADR specifies decision-injection ordering: how recorded `Decision` payloads are surfaced to ops whose execution spec declares `replay_policy: :replay_recorded`. Per-op replay semantics stay in ADR-OPSPEC-01's `determinism.replay_policy`; this ADR specifies only the run-wide protocol.
   - The ADR specifies partial-run re-entry: how a crash-recovered run resumes mid-flight (per the existing `{:continue, {:rebuild, events}}` path).
   - The worked example exercises the run-wide replay walker end-to-end, citing the existing test suite at `runtime/apps/liminara_core/test/liminara/run/replay_test.exs` as the reference implementation.
   - The ADR includes an explicit "Out of scope" subsection naming **pack-version skew** (deferred to `work/gaps.md` → "Cross-version pack replay semantics") and **provenance recording** (owned by M-PACK-B-01b) and pointing at their owners. The ADR does not specify either.
   - The ADR cites `runtime/apps/liminara_core/test/liminara/run/replay_test.exs` + `Liminara.rebuild_from_events/2` as primary reference and D-2026-04-05-023 (Radar run identity from ExecutionContext) as secondary.

8. **ADR-WIRE-01 specifies the port wire protocol** as schema. Concretely:
   - The schema codifies the request/response message shapes Liminara's `Liminara.Executor.Port` exchanges with Python ops today (see `runtime/apps/liminara_core/lib/liminara/executor/port.ex`).
   - The schema codifies the warning-payload shape as it appears on the wire (string-keyed JSON, per D-2026-04-20-026 and the M-WARN-04 fix).
   - Worked example exercises a typical Python op call end-to-end (request, response, decision-bearing response, warning-bearing response, error response).
   - Reference implementation: Radar's existing Python ops (cite a specific Radar Python op file by path).

9. **Anchored-citation discipline holds for every pack-level ADR in this milestone whose secondary reference is admin-pack** — per the parent epic's *ADRs produced* table that's **ADR-MANIFEST-01, ADR-PLAN-01, ADR-OPSPEC-01**. Each such ADR cites a specific file + section anchor inside `admin-pack/v2/docs/architecture/` (e.g. `bookkeeping-pack-on-liminara.md §4.2 — per-receipt lifecycle`), not a generic "see admin-pack" reference. Reviewer follows each anchor, reads the cited section, and judges whether the ADR's design genuinely satisfies the cited need — unanchored citations or substance-failing citations block ADR merge. ADR-WIRE-01 and ADR-REPLAY-01 have no admin-pack secondary and are exempt from this gate.

10. **Reference implementations are concrete.** Every named reference implementation in this milestone's ADR set satisfies the parent epic's reviewer rubric: (a) the owning milestone is named specifically (not just "E-21c"); (b) the reference's shape is concretely described, not gestured at; (c) for scheduled references, a matching acceptance criterion exists in the named owning milestone's spec binding the reference's shape to the ADR. Where this milestone references work in milestones that have not yet been spec'd (e.g. M-PACK-B-01b for provenance recording, M-PACK-C-03 for `examples/file_watch_demo`), the cross-binding is recorded as a forward dependency and the named owning milestone's spec must satisfy it when authored.

11. **Contract-matrix rows declared in `## Contract matrix changes` below land in `docs/architecture/indexes/contract-matrix.md`** as part of this milestone's merge, per `.ai-repo/rules/liminara.md` Contract matrix discipline. Live-source paths in the new rows are accurate at merge time; the existing warning-contract row's `Approved next` column is updated to point at the merged ADR-OPSPEC-01 path rather than at the unmerged spec.

## Constraints

- **No runtime code moves.** This milestone is contract documentation + CUE schemas + fixtures + the schema-evolution loop only. ADR-OPSPEC-01 is schema-freezing of M-TRUTH-01's already-merged shape; ADR-REPLAY-01 documents the protocol the live runtime already implements. Anything that changes runtime behaviour belongs to E-21b.
- **No SDK.** No Python or Elixir SDK code, no ergonomic wrappers, no scaffolders. Those are E-21c.
- **No PackLoader internals.** ADRs may specify what data PackLoader receives and emits; they may not prescribe how it implements its load algorithm. PackLoader internals are E-21b's concern.
- **No per-payload CUE schemas.** ADR-CONTENT-01 (M-PACK-A-02c) defines the namespace shape for content-type identifiers; per-payload schemas (what fields a `radar.cluster_summary@1` artifact body carries) are demand-driven per pack and out of scope.
- **No compatibility shims.** Per D-2026-04-20-026 and the repo-wide shim policy: contract documentation reflects the live + decided-next shape with no fallback clauses for legacy fixture shapes. A schema that needs to evolve evolves additively (CUE unification-compatible) or bumps major version with a deprecation ADR (per ADR-EVOLUTION-01, M-PACK-A-02c) — never via a dual-shape accept-both schema.
- **Schema files cannot reference unmerged schemas circularly.** ADR-MANIFEST-01's `schema_version` field references ADR-EVOLUTION-01 (M-PACK-A-02c) for the algorithm; the cross-reference is documentary, not a CUE import. ADR-MANIFEST-01's CUE schema validates the field shape; ADR-EVOLUTION-01 will, when written, validate the field's algorithmic semantics.
- **The schema-evolution loop is convention layered on `cue vet`, not a separate validation engine.** Per the parent epic's specification: ~20 lines of shell or Elixir; CUE does the validation; the loop iterates and formats errors.

## Design Notes

- **ADR numbering.** At this spec's write, `docs/decisions/` contains `0001-failure-recovery-strategy.md`, `0002-visual-execution-states.md`, and `0003-doc-tree-taxonomy.md`. Per D-2026-04-23-030, the on-disk filename is `NNNN-<slug>.md` (no `ADR-` prefix); the frontmatter `id` is `ADR-NNNN` (4-digit zero-padded). Per D-2026-04-22-028, each new ADR claims the next monotonic number at write time. The five ADRs in this milestone will land at numbers between `0004` and `0008`; the keyword IDs (`ADR-MANIFEST-01` etc.) are recorded in each frontmatter as `working_id`. Authors grep `docs/decisions/` for the next free number before claiming it.
- **Schema topic names.** Each ADR's CUE schema lands under a `<topic>` directory whose name is the canonical contract surface name. The mapping is: ADR-MANIFEST-01 → `docs/schemas/manifest/`, ADR-PLAN-01 → `docs/schemas/plan/`, ADR-OPSPEC-01 → `docs/schemas/op-execution-spec/`, ADR-REPLAY-01 → `docs/schemas/replay-protocol/`, ADR-WIRE-01 → `docs/schemas/wire-protocol/`. These names also appear as new rows in the contract matrix.
- **First fixture cohort lives under `v1.0.0/`.** Per the parent epic's fixture-library layout: M-PACK-A-02a lands the first schemas; their fixtures live at `docs/schemas/<topic>/fixtures/v1.0.0/`. Future schema bumps (additive or breaking) land their new fixtures under a matching `v<N>/` directory; old fixtures stay frozen.
- **Schema-evolution loop language choice.** The loop is invoked the same way `cue vet` is invoked — most likely a make target / shell script in the same harness M-PACK-A-01 shipped. Authors may write it in Elixir if it composes more naturally with existing repo tooling; the parent epic explicitly does not pin the language. Whichever is chosen, the entry-point command + invocation flow is documented alongside the existing `cue vet` invocation.
- **ADR-OPSPEC-01's source-of-truth bindings.** The CUE schema mirrors `runtime/apps/liminara_core/lib/liminara/execution_spec.ex`, `runtime/apps/liminara_core/lib/liminara/op_result.ex`, `runtime/apps/liminara_core/lib/liminara/warning.ex`, `runtime/apps/liminara_core/lib/liminara/run.ex` (`Run.Result`), and the `run_completed` / `run_partial` / `run_failed` payload shapes in `runtime/apps/liminara_core/lib/liminara/run/server.ex`'s `finish_run/2`. Field rename or shape divergence between live source and schema fails the contract-matrix wrap-time check.
- **ADR-REPLAY-01's source-of-truth bindings.** The protocol description mirrors `runtime/apps/liminara_core/lib/liminara/run/server.ex` (`rebuild_from_events/2`, `result_from_event_log/1`, the `{:continue, {:rebuild, events}}` re-entry path). The reference implementation is the existing test suite at `runtime/apps/liminara_core/test/liminara/run/replay_test.exs`.
- **ADR-WIRE-01's source-of-truth bindings.** The protocol description mirrors `runtime/apps/liminara_core/lib/liminara/executor/port.ex`. Wire-level warning payload shape is the string-keyed shape locked by M-WARN-04 + D-2026-04-20-026.
- **Cross-references.** Every ADR's frontmatter or body cites: M-TRUTH-01 spec path (where the upstream contract was locked), the parent sub-epic spec (`work/epics/E-21-pack-contribution-contract/E-21a-contract-design.md`), and the relevant decisions log entries (D-2026-04-20-025, D-2026-04-05-023, D-2026-04-22-028, D-2026-04-23-030). ADR-OPSPEC-01 also cites the merged E-19 epic.
- **Worked-example fixture parity.** Each ADR's worked example must match a committed valid fixture verbatim — when the ADR is rendered alongside the fixture, the YAML body is identical. This enforces that the ADR's authored example is one the schema validates, catching drift between worked-example prose and the actual data shape.

## Out of Scope

- **Runtime code (PackLoader, PackRegistry, Executor dispatch, TriggerManager, SurfaceRenderer, SecretSource, FSScope enforcer, A2UI MultiProvider).** Owned by E-21b.
- **SDK and tooling (Python SDK, Elixir SDK, `liminara-new-pack`, `liminara-test-harness`, e2e-harness skill, widgets, `examples/file_watch_demo`).** Owned by E-21c.
- **Radar extraction.** Owned by E-21d.
- **The other 13 ADRs in E-21a's *ADRs produced* table.** Owned by M-PACK-A-02b (5 ADRs: SURFACE-01, TRIGGER-01, FILEWATCH-01, FSSCOPE-01, SECRETS-01) and M-PACK-A-02c (8 ADRs: REGISTRY-01, MULTIPLAN-01, EXECUTOR-01, EVOLUTION-01, LAYOUT-01, BOUNDARY-01, CONTENT-01, LA-01).
- **Per-content-type payload CUE schemas.** Demand-driven per pack; the namespace shape lands in ADR-CONTENT-01 (M-PACK-A-02c).
- **Pack-version skew during replay.** Deferred to `work/gaps.md` → "Cross-version pack replay semantics."
- **Provenance recording in run initial events.** Owned by M-PACK-B-01b as a runtime concern; ADR-REPLAY-01 references it but does not specify it.
- **Repo-wide CI integration of the schema-evolution loop.** Deferred to the separate CI initiative tracked in `work/gaps.md` as the "E-21a CI alignment" follow-up; this milestone delivers local + pre-commit invocation only.

## Dependencies

- **M-PACK-A-01 must be merged.** Provides the CUE toolchain in the devcontainer (pinned via shared tool-versions file), the `cue vet` invocation script, the pre-commit hook, the `docs/schemas/<topic>/fixtures/v<N>/` directory layout convention, the `.ai-repo/skills/design-contract.md` project binding, and the `.ai-repo/rules/contract-design.md` reviewer rule. Without these, this milestone has no harness to run schemas or fixtures against. Spec path: `work/epics/E-21-pack-contribution-contract/M-PACK-A-01-*.md` (parked branch).
- **E-19 must be merged.** Provides the warning-bearing terminal-event taxonomy (`run_completed` / `run_partial` / `run_failed`) and the `Liminara.Warning` struct shape ADR-OPSPEC-01 codifies. Spec path: `work/done/E-19-warnings-degraded-outcomes/epic.md`.
- **M-TRUTH-01 (E-20) must be merged.** Provides the canonical Elixir-side execution contract ADR-OPSPEC-01 codifies as CUE. Spec path: `work/done/E-20-execution-truth/M-TRUTH-01-execution-spec-outcome-design.md`.
- **Parent sub-epic spec.** `work/epics/E-21-pack-contribution-contract/E-21a-contract-design.md` — defines the per-ADR content requirements this milestone implements.

## Contract matrix changes

Per `.ai-repo/rules/liminara.md` Contract matrix discipline. Reviewer verifies these rows land in `docs/architecture/indexes/contract-matrix.md` before wrap.

**Rows added** (one per topic this milestone ships a schema for):

- `manifest` — Live source: `docs/schemas/manifest/schema.cue`. Approved next: ADR-EVOLUTION-01 (M-PACK-A-02c) when it lands. Drift guard: `cue vet` + schema-evolution loop.
- `plan-as-data` — Live source: `docs/schemas/plan/schema.cue`. Approved next: PackLoader binding in E-21b. Drift guard: `cue vet` + schema-evolution loop.
- `op-execution-spec` — Live source: `docs/schemas/op-execution-spec/schema.cue` plus the Elixir source files it mirrors (`runtime/apps/liminara_core/lib/liminara/execution_spec/`, `op_result.ex`, `warning.ex`, `run.ex`). Approved next: SDK bindings in E-21c. Drift guard: `cue vet` + schema-evolution loop + cross-binding check between schema field names and Elixir struct fields.
- `replay-protocol` — Live source: `docs/schemas/replay-protocol/schema.cue` plus `runtime/apps/liminara_core/lib/liminara/run/server.ex` (`rebuild_from_events/2`, `result_from_event_log/1`). Approved next: provenance recording in M-PACK-B-01b. Drift guard: existing replay test suite at `runtime/apps/liminara_core/test/liminara/run/replay_test.exs`.
- `wire-protocol` — Live source: `docs/schemas/wire-protocol/schema.cue` plus `runtime/apps/liminara_core/lib/liminara/executor/port.ex`. Approved next: SDK port bindings in E-21c. Drift guard: `cue vet` + the existing port executor tests.

(Authors should verify these row names against any naming conventions already in use in `docs/architecture/indexes/contract-matrix.md` at write time and reconcile if a different canonical name is in use; the row's *what the contract is* role is the binding part, the row label is editorial.)

**Rows updated:**

- **Warning and degraded-success contract** (existing row). The `Approved next` column currently points at `work/epics/E-21-pack-contribution-contract/E-21a-contract-design.md (ADR-OPSPEC-01 will codify warning shape + the run_completed/run_partial/run_failed terminal event taxonomy)`. Update to point at the merged ADR-OPSPEC-01 path (`docs/decisions/NNNN-op-execution-spec.md` — actual NNNN known at merge) and the merged CUE schema path (`docs/schemas/op-execution-spec/schema.cue`). The `Live source` column is unchanged — runtime code is unchanged by this milestone. The `Drift guard` text is updated to reflect that the warning + terminal-event shape now has a CUE codification that downstream consumers bind to.

**Rows retired:** None.

## References

- Parent sub-epic: `work/epics/E-21-pack-contribution-contract/E-21a-contract-design.md`
- Parent epic: `work/epics/E-21-pack-contribution-contract/epic.md`
- Predecessor milestone: `work/epics/E-21-pack-contribution-contract/M-PACK-A-01-*.md` (parked branch)
- Upstream contracts:
  - `work/done/E-20-execution-truth/M-TRUTH-01-execution-spec-outcome-design.md` (canonical execution contract)
  - `work/done/E-19-warnings-degraded-outcomes/epic.md` (warning + terminal-event taxonomy)
  - `work/done/E-19-warnings-degraded-outcomes/M-WARN-01-runtime-warning-contract.md` (warning shape detail)
- Live runtime sources mirrored:
  - `runtime/apps/liminara_core/lib/liminara/execution_spec/`
  - `runtime/apps/liminara_core/lib/liminara/op_result.ex`
  - `runtime/apps/liminara_core/lib/liminara/warning.ex`
  - `runtime/apps/liminara_core/lib/liminara/run.ex`
  - `runtime/apps/liminara_core/lib/liminara/run/server.ex`
  - `runtime/apps/liminara_core/lib/liminara/executor/port.ex`
  - `runtime/apps/liminara_core/test/liminara/run/replay_test.exs`
- Decision log entries:
  - D-2026-04-20-025 (`run_partial` is a first-class terminal event type)
  - D-2026-04-20-026 (no backward-compat shims for in-flight contract fixes)
  - D-2026-04-05-023 (Radar run identity is runtime-owned)
  - D-2026-04-22-028 (ADR working-keyword IDs in frontmatter; superseded by D-030 on filename)
  - D-2026-04-23-030 (filename `NNNN-<slug>.md`, ID `ADR-NNNN`)
- Contract-matrix index: `docs/architecture/indexes/contract-matrix.md`
- Repo rules: `.ai-repo/rules/liminara.md` (Contract matrix discipline; Decision records — two surfaces; Truth discipline; Doc-tree boundaries)
- Admin-pack architecture (for anchored citations in ADR-MANIFEST-01, ADR-PLAN-01, ADR-OPSPEC-01): `admin-pack/v2/docs/architecture/bookkeeping-pack-on-liminara.md`, `admin-pack/v2/docs/architecture/repo-layout.md`
