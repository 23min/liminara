# M-CONTRACT-02: Foundational contracts (5 ADRs) — Tracking

**Started:** 2026-04-26
**Completed:** —
**Branch:** milestone/M-CONTRACT-02 (cut from `epic/E-24-contract-design` at `949b049`)
**Spec:** work/epics/E-24-contract-design/M-CONTRACT-02-foundational-contracts.md
**Commits:** —

<!-- Status is not carried here. The milestone spec's frontmatter `status:` field is
     canonical. `**Completed:**` is filled iff the spec is `complete`. -->

## Acceptance Criteria

- [ ] AC1: Every ADR (ADR-MANIFEST-01, ADR-PLAN-01, ADR-OPSPEC-01, ADR-REPLAY-01, ADR-WIRE-01) exists at `docs/decisions/NNNN-<slug>.md` in Nygard form with `working_id` frontmatter; on-disk `NNNN` is the next available monotonic number at write time (current high-water mark `0003`).
- [ ] AC2: Each ADR ships its CUE schema (`docs/schemas/<topic>/schema.cue`), valid + invalid fixtures under `fixtures/v1.0.0/`, a worked example matching a committed valid fixture verbatim, and a named reference-implementation citation (existing `<file>:<line>` or scheduled `<milestone-id>` + named file/module).
- [x] AC3: `cue vet` passes against every fixture under `docs/schemas/*/fixtures/v1.0.0/` — valid pass, invalid reject — via the `scripts/cue-vet` runner.
- [x] AC4: Schema-evolution compat-check loop is invocable locally + via pre-commit, walks all topics, fails with the spec-defined output format on a deliberate breaking-schema test fixture, and that demonstration is committed (the breaking change is reverted).
- [ ] AC5: ADR-MANIFEST-01 specifies the `schema_version` field (format, placement, required/optional, default-vs-error on absence) and cross-references ADR-EVOLUTION-01.
- [ ] AC6: ADR-OPSPEC-01 codifies M-TRUTH-01's five-section `execution_spec/0` (`identity`, `determinism`, `execution`, `isolation`, `contracts`), `OpResult`, `Warning`, `Run.Result` aggregation fields, and the closed enumeration of terminal events (`run_completed` / `run_partial` / `run_failed`) with payload shapes matching live source. Schema-freezing only.
- [ ] AC7: ADR-REPLAY-01 specifies the run-level replay protocol mirroring `Run.Server.rebuild_from_events/2` + `result_from_event_log/1` + the `{:continue, {:rebuild, events}}` re-entry path; reference impl is `replay_test.exs`; pack-version skew + provenance recording are explicitly out-of-scope with owners cited.
- [ ] AC8: ADR-WIRE-01 codifies the request/response shapes of `Liminara.Executor.Port`, the string-keyed warning payload (per D-2026-04-20-026), with a Radar Python op as reference impl.
- [ ] AC9: Anchored-citation discipline holds — ADR-MANIFEST-01, ADR-PLAN-01, ADR-OPSPEC-01 each cite a specific `admin-pack/v2/docs/architecture/<file>.md §<section>` anchor with substantive description.
- [x] AC10: Every named reference implementation satisfies the parent-epic rubric (named owning milestone, concrete shape, matching AC in the owning milestone's spec for scheduled refs).
- [x] AC11: Contract-matrix rows for `manifest`, `plan-as-data`, `op-execution-spec`, `replay-protocol`, `wire-protocol` land in `docs/architecture/indexes/contract-matrix.md` with accurate live-source paths; the existing warning-contract row's `Approved next` column is updated to point at the merged ADR-OPSPEC-01.

## Decisions made during implementation

<!-- Decisions that came up mid-work that were NOT pre-locked in the milestone spec.
     For each: what was decided, why, and a link to a decision record if one was
     opened. If no new decisions arose, say "None — all decisions are pre-locked
     in the milestone spec." -->

- _Pending._

## Work Log

<!-- One entry per AC (preferred) or per meaningful unit of work.
     Header: "AC<N> — <short title>" or "<short title>" if not AC-scoped.
     First line: one-line outcome · commit <SHA> · tests <N/M>
     Optional prose paragraph for non-obvious context: what changed, file:line
     references, why a detour was needed. Append-only — don't rewrite earlier entries. -->

### Preflight — 2026-04-26

CUE binary was missing from the devcontainer (Dockerfile install at `.devcontainer/Dockerfile:43-49` was never picked up by an existing container; rebuild deferred). Installed `cue 0.16.1` ad-hoc into `~/.local/bin` matching the pinned version + canonical curl-from-GitHub source. `cue version` reports `v0.16.1`. Survives until the devcontainer is rebuilt.

Branch `milestone/M-CONTRACT-02` cut from `epic/E-24-contract-design@949b049`; that base carries the M-CONTRACT-01 merge plus the framework-bump, dead-code-audit, and milestone-rename commits per D-2026-04-26-034 / D-2026-04-26-035.

### AC3 + AC4 — Cohort verification + schema-evolution loop demonstration — 2026-05-02

Full v1.0.0 cohort: 5 topics × (3-5 valid + 6-8 invalid) = **19 valid + 33 invalid = 52 fixtures**.
- `manifest`: 3 valid, 8 invalid
- `op-execution-spec`: 3 valid, 6 invalid
- `plan`: 5 valid, 7 invalid
- `replay-protocol`: 4 valid, 6 invalid
- `wire-protocol`: 4 valid, 6 invalid

`./scripts/cue-vet` (no-arg, walks every fixture against HEAD schema): exit 0, no output. **AC3 pass** — every valid fixture validates; every invalid fixture is rejected.

**AC4 failure-semantics demonstration on the live cohort:** temporarily added `demo_required_field: string` to `#Plan` close()'d block in `docs/schemas/plan/schema.cue`. Ran `./scripts/cue-vet`; the loop reported all 5 plan valid fixtures failing with the spec-defined format `<fixture path> fails against <topic>.cue at <schema path>: <CUE error>` and exited non-zero. Captured stderr:

```
/workspaces/liminara/docs/schemas/plan/fixtures/v1.0.0/valid/bookkeeping-admin-pack-shape.yaml fails against plan.cue at /workspaces/liminara/docs/schemas/plan/schema.cue: demo_required_field: incomplete value string:
    ./docs/schemas/plan/schema.cue:119:23
/workspaces/liminara/docs/schemas/plan/fixtures/v1.0.0/valid/diamond.yaml fails against plan.cue at /workspaces/liminara/docs/schemas/plan/schema.cue: demo_required_field: incomplete value string:
    ./docs/schemas/plan/schema.cue:119:23
/workspaces/liminara/docs/schemas/plan/fixtures/v1.0.0/valid/linear-chain.yaml fails against plan.cue at /workspaces/liminara/docs/schemas/plan/schema.cue: demo_required_field: incomplete value string:
    ./docs/schemas/plan/schema.cue:119:23
/workspaces/liminara/docs/schemas/plan/fixtures/v1.0.0/valid/radar-realistic.yaml fails against plan.cue at /workspaces/liminara/docs/schemas/plan/schema.cue: demo_required_field: incomplete value string:
    ./docs/schemas/plan/schema.cue:119:23
/workspaces/liminara/docs/schemas/plan/fixtures/v1.0.0/valid/single-op-no-deps.yaml fails against plan.cue at /workspaces/liminara/docs/schemas/plan/schema.cue: demo_required_field: incomplete value string:
    ./docs/schemas/plan/schema.cue:119:23
```

Reverted the schema change. Re-ran `./scripts/cue-vet`: exit 0, no output. **AC4 pass** — output format matches the spec verbatim, exit code is non-zero on failure, all 5 plan valid fixtures correctly identified, repo state restored. The durable failure-semantics regression coverage lives in `scripts/tests/test-cue-vet.sh` Tests 7 + 9 (synthetic fixtures, exercises both standard `<fixture> fails against <topic>` and inverted `<fixture> in invalid/ unexpectedly passed against <topic>` formats); all 7 M-CONTRACT-01 harness tests pass against the populated cohort.

Pre-commit hook wiring confirmed at `scripts/pre-commit-cue:36-58` — vets staged `.cue` files and runs the schema-evolution loop when any staged path matches `docs/schemas/<topic>/fixtures/v<N>/(valid|invalid)/`.

### AC10 + AC11 — Contract-matrix rows + reviewer-rubric pass — 2026-05-02

**AC11 — Contract-matrix rows landed.** Five rows added to `docs/architecture/indexes/contract-matrix.md`:
- `Op execution spec` — live source `docs/schemas/op-execution-spec/schema.cue` + Elixir source-of-truth files; approved next ADR-OPSPEC-01 + SDK bindings + dynamic-pipeline contract-grammar extension per D-2026-05-02-039
- `Pack manifest contract` — live source `docs/schemas/manifest/schema.cue` + Radar Pack-implementing module declarations; approved next ADR-MANIFEST-01 + ADR-EVOLUTION-01 + M-RUNTIME-02 generated pack.yaml
- `Plan-as-data contract` — live source `docs/schemas/plan/schema.cue` + `plan.ex` + Radar `plan/1`; approved next ADR-PLAN-01 + PackLoader binding + ADR-MULTIPLAN-01/ADR-DYNAMIC-PIPELINE-01
- `Replay protocol` — live source `docs/schemas/replay-protocol/schema.cue` + `run/server.ex`; approved next ADR-REPLAY-01 + provenance recording in M-RUNTIME-02
- `Port wire protocol` — live source `docs/schemas/wire-protocol/schema.cue` + `executor/port.ex`; approved next ADR-WIRE-01 + SDK port bindings + warning_payload extraction (gap)

Existing `Warning and degraded-success contract` row's `Approved next` column updated: the prior text pointed at the unmerged sub-epic spec; now points at `docs/decisions/0004-op-execution-spec.md` (merged ADR-OPSPEC-01) plus the merged CUE schema at `docs/schemas/op-execution-spec/schema.cue`. Drift-guard column extended to note `scripts/cue-vet` validation against `docs/schemas/op-execution-spec/fixtures/v1.0.0/`. `last_reviewed: 2026-05-02`.

All 22 cited live-source/supporting paths verified to exist on disk via path-existence sweep.

**AC10 — Reviewer-rubric pass.** Reviewed each ADR's `reference_implementation` frontmatter against parent-epic rubric + contract-design reviewer rule (`.ai-repo/rules/contract-design.md`):

| ADR | Reference impl shape | Verdict |
|---|---|---|
| OPSPEC-01 | `runtime/apps/liminara_core/lib/liminara/execution_spec.ex:45` (existing `<file>:<line>`) | ✓ |
| WIRE-01 | `runtime/python/src/ops/radar_summarize.py:42` (existing `<file>:<line>`) | ✓ |
| REPLAY-01 | **Updated** — promoted `runtime/apps/liminara_core/lib/liminara/run/server.ex:283` (`rebuild_from_events/2`) as primary; demoted `replay_test.exs:45 + crash_recovery_test.exs:111` to "end-to-end demonstration" | ✓ (after fix) |
| MANIFEST-01 | `M-RUNTIME-02 + runtime/apps/liminara_radar/pack.yaml` (scheduled-to-exist with milestone ID + named file) | ✓ |
| PLAN-01 | Dual citation: `runtime/apps/liminara_radar/lib/liminara/radar.ex:52` (term form, today) + `M-RUNTIME-02 + runtime/apps/liminara_radar/pack.yaml` (YAML rendering, scheduled) | ✓ |

REPLAY-01 was the load-bearing finding: AC7 said "cite the existing test suite as the reference implementation," but the reviewer-rule Assertion 4 explicitly rejects test code for the existing-implementation form. The reviewer-rule discipline is more recently articulated and authoritative; resolution is to cite the live runtime as primary (`run/server.ex:283`) and demote the test suite to "end-to-end demonstration" alongside `crash_recovery_test.exs:111` for the mid-run-resume branch. The ADR body's "Live runtime secondary citations" section already had the live-runtime citations marked as secondary; the fix promotes them.

**Reviewer-rule Assertions 1 + 3 swept across pack-level ADRs (MANIFEST-01, PLAN-01, OPSPEC-01):**
- **Assertion 1 (anchored admin-pack citations):** all three carry `bookkeeping-pack-on-liminara.md §<N> — <description>` form with substantive descriptions. MANIFEST-01: §3 (Pack identity), §5 (Provider Op libraries), §7 (Pack-specific Ops). PLAN-01: §9 (The Plan — DAG construction) + §9 sub-section (Plan style: per-period vs per-item). OPSPEC-01: §8 (terminal-event taxonomy on bookkeeping flow), §5 (Provider Op libraries with determinism classes).
- **Assertion 3 (Radar-primary + admin-pack-secondary):** PLAN-01's frontmatter dual-cites Radar primary `radar.ex:52`. MANIFEST-01 carries Radar primary in body via the `runtime/apps/liminara_radar/lib/liminara/radar.ex` reference + `pack.yaml` scheduled secondary. OPSPEC-01's body Radar-primary citation prose patched to cite the actual recordable Radar ops at `summarize.ex:10` (`def determinism, do: :recordable`) + `llm_dedup_check.ex` + the per-op execution-spec builders at `radar/ops/specs.ex` — Radar's op shape exercised at the citation layer.

WIRE-01 + REPLAY-01 are exempt from Assertions 1 + 3 per the parent-epic *ADRs produced* table (Radar-only by deliberate scoping).

**Audit-resolved (initially flagged, confirmed compliant after deeper read):**
- OPSPEC-01's worked-example fixture op names (`csv_to_transactions`, `claude_complete`, `gmail_fetch_attachment`) initially appeared to be fictional Radar op names. **Audit confirms** they are deliberately sourced from `bookkeeping-pack-on-liminara.md §5 — Provider Op libraries` (lines 222, 199, 189 respectively) — one per determinism class. The cohort design is **admin-pack-anchored worked examples**: Radar's op shape is exercised at the prose-citation layer (`summarize.ex:10` + `llm_dedup_check.ex` + `specs.ex`), admin-pack's op shape is exercised at the fixture layer. Two-pack pressure is enforced at both citation and worked-example layers. OPSPEC-01 body prose updated to record this rationale explicitly (replaced the prior "illustrative op name" framing). **No fixture or schema change needed.**

**Final cue-vet sweep:** `./scripts/cue-vet` exits 0; all 7 M-CONTRACT-01 harness tests still pass.
