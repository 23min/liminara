---
id: M-CONTRACT-03
epic: E-24
parent: E-24
status: draft
depends_on: M-CONTRACT-02
---

# M-CONTRACT-03: Packs-as-running-systems (5 ADRs)

## Goal

Ship the five ADRs that define how a loaded pack interacts with the world — UI surfaces, triggers, file-watch semantics, filesystem scope, and secrets — each paired with a CUE schema, valid + invalid fixtures, a worked example, and a named reference implementation. After this milestone, E-25's runtime plumbing (`SurfaceRenderer`, `TriggerManager`, file-watch loop, FS-scope enforcement, `SecretSource`) has a fixed contract to build against.

## Context

M-CONTRACT-02 has merged: ADR-MANIFEST-01, ADR-PLAN-01, ADR-OPSPEC-01, ADR-REPLAY-01, and ADR-WIRE-01 are in `docs/decisions/` with paired CUE schemas under `docs/schemas/`, fixtures under `docs/schemas/<topic>/fixtures/v1.0.0/`, and the schema-evolution loop wired into pre-commit (M-CONTRACT-01). Those five ADRs lock the foundational data shapes (manifest, plan, op execution spec, replay protocol, port wire protocol) that the present milestone's ADRs build on.

Live runtime context this milestone references but does not modify:

- `runtime/apps/liminara_radar/lib/liminara/radar/scheduler.ex` — Radar's GenServer scheduler. Per D-2026-04-01-008 and D-2026-04-02-017, schedule state is not persisted; on restart, the next-fire time is recomputed from the wall clock. ADR-TRIGGER-01 codifies this as fire-and-forget.
- `runtime/apps/liminara_core/lib/liminara/executor.ex` — the executor that performs MVP's advisory FS-scope check (ADR-FSSCOPE-01 Surface A). E-25 M-RUNTIME-04 wires the check; this milestone documents its contract shape.
- `Liminara.Secrets.Registry` (decided-next, lands in E-25 M-RUNTIME-03) — the per-run registry that powers ADR-SECRETS-01 Boundary 1 scrubbing.
- `Liminara.Warning` and the `:suspected_secret_leak` warning code (E-19's contract, shipped) — the channel ADR-SECRETS-01 Boundary 2 emits through.

E-12 (Op Sandbox) is approved-next but not yet implemented. ADR-FSSCOPE-01 Surface B (runtime conformance — Landlock or audit-hook based) lands in E-12; this milestone specifies the contract shape so E-12 can implement it without redesign. Admin-pack ships in E-22, time-displaced from this contract work; per the parent sub-epic's anchored-citation discipline, every pack-level ADR here cites a specific file + section anchor inside `admin-pack/v2/docs/architecture/`.

`examples/file_watch_demo` is the named reference implementation for ADR-FILEWATCH-01. It is **scheduled** (E-26 M-DX-03), not yet built; this milestone cites it under the parent sub-epic's "Reference implementations are named at ADR-writing time, either existing or scheduled-to-exist in a specific named milestone" rule (Technical direction §4).

## Acceptance Criteria

1. **Five ADRs exist as merged files under `docs/decisions/`**
   - Each ADR is filed at `docs/decisions/NNNN-<slug>.md` per the framework convention (`NNNN` is 4-digit zero-padded; `id:` frontmatter is `ADR-NNNN`; `renamed_from:` entry includes the keyword placeholder ID for cross-reference). ADR numbers are claimed monotonically from the next free integer at write time per D-2026-04-23-030; the five ADRs in this milestone occupy a contiguous block immediately above whatever M-CONTRACT-02's last claimed number is.
   - Each ADR uses the Nygard form (Status, Context, Decision, Consequences) with status `accepted` at merge.
   - Each ADR's frontmatter cites its keyword placeholder ID (`ADR-SURFACE-01`, `ADR-TRIGGER-01`, `ADR-FILEWATCH-01`, `ADR-FSSCOPE-01`, `ADR-SECRETS-01`) as the working title cross-reference.

2. **Each ADR ships the default content set defined by E-24**
   - Paired CUE schema lives at `docs/schemas/<topic>/schema.cue` (one topic per ADR; `<topic>` slugs locked in *Design Notes*).
   - Valid fixtures live under `docs/schemas/<topic>/fixtures/v1.0.0/`; invalid fixtures (demonstrating what `cue vet` rejects) live alongside under a named subdirectory or filename convention locked in *Design Notes*.
   - At least one worked example showing realistic pack snippets is embedded in the ADR body or referenced inline from a fixture.
   - A named reference implementation citation is present and concrete per the parent sub-epic's reviewer rubric: existing code path with file reference, OR a scheduled milestone with a named owning milestone, a matching acceptance criterion, and a defined-shape description (see AC 8 for `examples/file_watch_demo`).

3. **ADR-SURFACE-01 specifies the surface-declaration shape and widget catalog**
   - The surface declaration schema covers: surface ID, owning pack, declared widget identifiers from the catalog, widget-input bindings to artifacts/run state, and surface-level metadata (route slug, title, intended consumer).
   - The widget catalog enumerates the MVP widget set and pins each entry's input-binding shape; widgets not in the catalog are not declarable in MVP.
   - The primary reference implementation is Radar's `runs_dashboard` (existing in `runtime/apps/liminara_web/`); the secondary reference is admin-pack's period view, cited with a specific file + section anchor under `admin-pack/v2/docs/architecture/`.
   - The worked example shows at least one Radar surface declaration and one admin-pack-shape declaration validating against the schema.

4. **ADR-TRIGGER-01 specifies the trigger-declaration shape and codifies fire-and-forget cron restart-recovery**
   - The trigger schema covers `:cron`, `:file_watch`, and `:manual` discriminants with per-discriminant required fields (cron expression for `:cron`; watch-path + glob + debounce knobs for `:file_watch`; manual is parameterless beyond declaration).
   - The ADR explicitly codifies `:cron` restart-recovery semantics as **fire-and-forget**: on runtime restart, next-fire time is recomputed from the wall clock; fire times that passed during downtime are not backfilled. The Decision section cites D-2026-04-01-008 and D-2026-04-02-017 as the upstream basis and notes that this matches Radar's existing `Scheduler` behaviour with no new persistence required.
   - The worked example includes a simulated-restart scenario spanning a missed fire time and asserts no catch-up run is emitted.
   - The Consequences section cross-references **E-14 (Postgres + Oban)** as the escalation path for richer catch-up semantics (catch-up-once, catch-up-all, manual-catch-up-only); the ADR does not prescribe E-14's eventual choice but flags that durable catch-up requires E-14's persistence layer and is decided then, not now.
   - The ADR explicitly states that file-watch restart semantics are owned by ADR-FILEWATCH-01, not this ADR.
   - The primary reference is Radar's scheduler (existing); the secondary reference is admin-pack's intake, cited with a specific file + section anchor under `admin-pack/v2/docs/architecture/`.

5. **ADR-FILEWATCH-01 specifies file-watch semantics**
   - The ADR specifies, at minimum: debounce window, coalescing behaviour for rapid sequential events on the same path, scan-on-startup (whether files present at boot are processed), de-duplication policy (how the same file is or is not re-processed), an in-memory event queue, and rescan-on-restart behaviour (the runtime rescans the watched directory at boot rather than relying on durable queue state).
   - The schema captures the watch declaration's data shape (watched path or paths, glob patterns, debounce window, dedup key shape).
   - The primary reference implementation is `examples/file_watch_demo`, cited as scheduled in **E-26 M-DX-03** with the parent sub-epic's named-scheduled-reference rule satisfied: M-DX-03 has a matching acceptance criterion binding the demo's shape to this ADR (verified at this milestone's review by reading the M-DX-03 spec); the demo's intended shape is described concretely in the ADR (single watch directory, one or more glob patterns, an op that consumes each detected file, a fixture data set demonstrating debounce and dedup).
   - The secondary reference is admin-pack receipt intake, cited with a specific file + section anchor under `admin-pack/v2/docs/architecture/`.

6. **ADR-FSSCOPE-01 specifies two distinct contract surfaces, not one**
   - The Decision section names both surfaces explicitly:
     - **Surface A — Declaration integrity.** Does the op's declared `runtime_read_paths` / `runtime_write_paths` (from `ExecutionSpec.Isolation`) resolve under the pack's declared FS-scope root? Source of truth: the declared data. Check time: before invocation. Implementation: `Liminara.Executor`'s advisory check, **shipped in MVP** via E-25 M-RUNTIME-04; warning event on violation; op still runs. Surface A is not strengthened by E-12.
     - **Surface B — Runtime conformance.** Do the op's actual filesystem syscalls (`open`, `openat`, `renameat`, …) stay within the declared FS-scope root? Source of truth: runtime behaviour. Check time: during op execution. Implementation: Landlock or equivalent kernel sandbox, **added in E-12** (not shipped in MVP). Layer 2 Python-runner audit hooks per `work/gaps.md` "Op sandbox" entry + D-2026-04-02-011 are an alternative implementation; which lands first is an E-12-era choice, not an E-24 choice.
   - The ADR states explicitly that **both surfaces are first-class contract shapes from the start**, and that the runtime implementation of Surface B arrives in E-12. Neither is a shim under `docs/governance/shim-policy.md` (the policy's lie-preservation test fails for both).
   - The ADR does **not** claim "advisory is an intermediate contract, not a shim"; the Consequences section explicitly retracts that one-surface framing.
   - The ADR's test-coverage guidance specifies that Surface A's fixture (op declares a path outside FS-scope root → warning) does **not** cover Surface B's fixture (op writes a path outside FS-scope root without declaring it → Landlock kill / audit-hook warning); the ADR notes that E-12 will need its own fixtures.
   - The CUE schema captures the FS-scope root declaration shape (the data Surface A operates on). Schema content for Surface B (any runtime-side capability metadata E-12 needs) is explicitly out of scope for this ADR's schema; the ADR notes that E-12 may extend the schema additively when it ships.
   - The primary reference is Radar's `lancedb_path` (existing); the secondary reference is admin-pack's `data_root`, cited with a specific file + section anchor under `admin-pack/v2/docs/architecture/`.

7. **ADR-SECRETS-01 specifies two distinct contract boundaries, not one**
   - The Decision section names both boundaries explicitly:
     - **Boundary 1 — Liminara-internal scrubbing (reliable).** Every observation emitter (event log writer, A2UI message builder, logger) runs outbound strings through `Liminara.Secrets.Registry` (a per-run registry of resolved secret values). Matches are redacted to `[REDACTED:<name>]`. Runtime *guarantee*.
     - **Boundary 2 — Pack-code discipline (best-effort signal).** Pack code receives resolved secrets as plaintext (env var or whatever shape `SecretSource` produces). If pack code stringifies a secret into op results, exception messages, or logs, the registry-driven scrub catches it best-effort at emission time and emits a `:suspected_secret_leak` warning event (per E-19's warning contract) attributing the leak to the emitting op. Signal, not guarantee.
   - The ADR states explicitly which failure modes are caught (direct logger leak via marker; pack-op stringify-return; exception message containing secret) and which are not (split across fields; base64-encoded; hashed).
   - The ADR's authoring-guide section codifies the pack-code discipline rule: "never `str(secret)` or include secrets in exception messages; use the SDK-provided `scrub_secrets(text)` helper when you must render a string that might touch them."
   - The ADR does **not** claim runtime-enforced secret safety. The `SecretSource` behaviour is the plumbing for *secret delivery* — env var in MVP; Vault, Azure Key Vault, Doppler as future adapters per `work/gaps.md` "Secret-management maturity" entry. The ADR cross-references that gap as the home of further hardening.
   - The CUE schema captures the secret-declaration shape that lives in `pack.yaml` (declared secret name, source identifier, optional metadata) and the `SecretSource` behaviour's declarative surface (the data side; the Elixir behaviour itself is an E-25 artefact).
   - The worked example includes the three-case deliberate-leak fixture from E-25 M-RUNTIME-03 (direct logger leak; pack-op stringify-return; split-across-fields unrecoverable case) with the expected outcome for each.
   - The primary reference is Radar's API key configuration (existing); the secondary reference is admin-pack's Gmail credentials, cited with a specific file + section anchor under `admin-pack/v2/docs/architecture/`.

8. **Anchored-citation discipline holds for every secondary reference**
   - For each of the five ADRs, the secondary admin-pack reference is a specific file + section anchor inside `admin-pack/v2/docs/architecture/` (e.g. `bookkeeping-pack-on-liminara.md §4.2 — per-receipt lifecycle`), not a generic "see admin-pack" reference.
   - The reviewer follows every such citation, reads the cited section, and judges whether the ADR's design genuinely satisfies the cited need. Unanchored citations are rejected at review and block ADR merge per the parent sub-epic's anchored-citation success criterion.

9. **Reference implementations are concrete per the named-scheduled-reference rule**
   - Existing references cite a specific file path or module. Scheduled references cite a specific milestone ID (not just a sub-epic letter), point at a matching acceptance criterion in that milestone's spec, and describe the reference's shape concretely. The reviewer's rubric (parent sub-epic Technical direction §4) is applied to each reference.

10. **All fixtures pass `cue vet`; the schema-evolution loop passes against the new fixtures**
    - Every valid fixture committed in this milestone passes `cue vet` against its paired schema.
    - Every invalid fixture committed in this milestone fails `cue vet` with the expected rejection (the `<fixture path> fails against <topic>.cue at <schema path>: <CUE error>` message documents which constraint each invalid fixture exercises).
    - The schema-evolution loop (shipped in M-CONTRACT-01 and exercised first in M-CONTRACT-02) walks every historical fixture under `docs/schemas/*/fixtures/v*/` against the HEAD schemas — including the five new schemas this milestone introduces — and exits zero.
    - Pre-commit runs both checks on the merge branch; both pass.

11. **Contract-matrix rows are landed**
    - The five new contract-matrix rows specified under "Contract matrix changes" below are present in `docs/architecture/indexes/contract-matrix.md` at merge, with correct live-source paths and cross-references to their ADRs.

## Constraints

- **No runtime code moves.** This milestone produces only ADRs, CUE schemas, fixtures, worked examples, and contract-matrix rows. PackLoader, TriggerManager, SurfaceRenderer, the FS-scope enforcer, and `SecretSource` implementations all belong to E-25.
- **ADRs document shape, not behaviour.** Each ADR specifies the contract surface a runtime component must respect; it does not prescribe the component's internals. The parent sub-epic's risk row ("ADR scope creeps into runtime design") applies — reviewers reject ADR text that prescribes PackLoader / TriggerManager / SurfaceRenderer internals.
- **`examples/file_watch_demo` is scheduled, not built here.** ADR-FILEWATCH-01 cites it as a scheduled reference; the milestone that actually authors the demo is **E-26 M-DX-03**. This milestone's reviewer verifies M-DX-03's spec contains a matching acceptance criterion binding the demo's shape to ADR-FILEWATCH-01; the demo files themselves are not produced here.
- **No code changes to `liminara_core`, `liminara_observation`, `liminara_web`, or any pack module.** The validation pipeline (`mix format`, `mix credo`, `mix dialyzer`, app suites) for those apps is not exercised by this milestone; only `cue vet` and the schema-evolution loop are exercised.
- **No compatibility shims.** Per repo policy, any exception requires a named removal trigger in the spec; none are anticipated for this milestone.
- **No main-branch work.** Executed on `epic/E-21-pack-contribution-contract` per the parent epic's branching rule; spec is drafted on `main` with `status: draft`.

## Design Notes

- **ADR numbering.** Per D-2026-04-23-030, ADR numbers are 4-digit zero-padded and claimed monotonically from the next free integer at write time. The author of each ADR greps `docs/decisions/*.md` for the next free number and claims it; M-CONTRACT-02's last assigned number plus one is the starting point. Frontmatter `id:` is `ADR-NNNN`; filename is `NNNN-<slug>.md` (no `ADR-` prefix on disk); the keyword placeholder ID (`ADR-SURFACE-01`, etc.) is preserved in the ADR's frontmatter as a `renamed_from:` cross-reference.

- **Schema topic slugs.** Locked at this milestone's review:
  - ADR-SURFACE-01 → `surface-declaration` (or `surface`); reviewer picks the slug that matches the contract-matrix row name from the parent sub-epic ("surface-declaration").
  - ADR-TRIGGER-01 → `trigger`.
  - ADR-FILEWATCH-01 → `file-watch`.
  - ADR-FSSCOPE-01 → `fs-scope`.
  - ADR-SECRETS-01 → `secrets`.
  - The reviewer cross-checks each chosen slug against `docs/architecture/indexes/contract-matrix.md` row names so the matrix row, schema directory, and ADR cross-reference share a consistent name.

- **Invalid-fixture convention.** AC 2 requires invalid fixtures alongside valid ones. The convention (subdirectory `invalid/` versus filename suffix versus separate `<topic>/fixtures/v1.0.0/invalid/<name>.yaml`) is locked at this milestone's review by the first ADR author and applied uniformly across the five schemas; the chosen convention is documented in each ADR's worked-example section.

- **Cross-references this milestone establishes.**
  - **D-2026-04-01-008** (GenServer scheduler, not system cron) and **D-2026-04-02-017** (Oban deferred to platform generalization, GenServer scheduler for Radar v1) — ADR-TRIGGER-01's upstream basis for fire-and-forget cron.
  - **D-2026-04-02-011** (Layered sandbox for Python ops) — ADR-FSSCOPE-01's upstream basis for Surface B implementation choice (Layer 2 audit hooks vs Layer 3 Landlock).
  - **E-12 (Op Sandbox)** — ADR-FSSCOPE-01 Surface B implementation home.
  - **E-14 (Postgres + Oban)** — ADR-TRIGGER-01 escalation path for richer catch-up semantics.
  - **E-19's warning contract** (`Liminara.Warning`, the `:suspected_secret_leak` warning code) — ADR-SECRETS-01 Boundary 2 emission channel.
  - **E-25 M-RUNTIME-03 three-case leak fixture** — ADR-SECRETS-01's worked example pulls from this fixture's three cases; the milestone's reviewer verifies the fixture's shape is described concretely in M-RUNTIME-03's spec at this milestone's review (or the description is added to M-RUNTIME-03's spec as a matching acceptance criterion if not already present).
  - **E-25 M-RUNTIME-04 advisory FS-scope check** — ADR-FSSCOPE-01 Surface A's MVP implementation; the milestone's reviewer verifies M-RUNTIME-04's spec binds the advisory check's shape to ADR-FSSCOPE-01.
  - **E-26 M-DX-03 `examples/file_watch_demo`** — ADR-FILEWATCH-01's primary reference (scheduled).
  - **`work/gaps.md` "Op sandbox: layered isolation not implemented"** — ADR-FSSCOPE-01 Surface B's gap-tracking home.
  - **`work/gaps.md` "Secret-management maturity — pluggable SecretSource adapters + secret-observability hardening"** — ADR-SECRETS-01's gap-tracking home for further hardening (Vault / Key Vault / Doppler adapters; capability-proxy approaches).

- **Two-surface and two-boundary framing supersession.** ADR-FSSCOPE-01's two-surface framing supersedes any earlier draft framing that described "advisory is an intermediate contract, not a shim" or "same surface, warning → block." The Consequences section retracts those framings explicitly. ADR-SECRETS-01 similarly does not adopt a single "secrets are scrubbed" framing; both boundaries are first-class.

- **Authoring order within the milestone.** ADR-TRIGGER-01 should be authored before ADR-FILEWATCH-01 because the latter binds to the former's `:file_watch` discriminant. ADR-SURFACE-01, ADR-FSSCOPE-01, and ADR-SECRETS-01 are independent of each other and of the trigger pair; they may be authored in any order. All five ADRs' schemas must be present when the schema-evolution loop is run for the merge.

- **Anchored-citation review pass.** A single reviewer pass at end-of-milestone walks every secondary admin-pack citation across the five ADRs, opens the cited file + section, and confirms the ADR's design genuinely satisfies the cited need. This pass is the anti-ceremony gate that closes the time-displaced-admin-pack risk; missing or generic citations block merge.

## Out of Scope

- **Runtime code.** PackLoader, TriggerManager, SurfaceRenderer, file-watch loop, FS-scope enforcer, `SecretSource` behaviour implementation, `Liminara.Secrets.Registry` — all in E-25.
- **SDK or scaffolder.** `liminara-pack-sdk` (Python and Elixir), widgets, scaffolder, test harness — all in E-26.
- **Building `examples/file_watch_demo`.** Cited as scheduled here; built in E-26 M-DX-03.
- **Radar extraction.** ADR-LAYOUT-01 and the actual move to a `radar-pack` submodule are E-27.
- **Other ADRs in E-24.** ADR-EXECUTOR-01, ADR-EVOLUTION-01, ADR-LAYOUT-01, ADR-BOUNDARY-01, ADR-CONTENT-01, ADR-LA-01, ADR-REGISTRY-01, ADR-MULTIPLAN-01 — all in M-CONTRACT-04.
- **Pluggable `SecretSource` adapters beyond `EnvVar`.** Vault, Azure Key Vault, Doppler — demand-driven per `work/gaps.md`. ADR-SECRETS-01 specifies the behaviour shape; concrete adapters are future work.
- **Capability-proxy secret delivery (Approach D).** Runtime-mediated HTTP / SMTP / subprocess proxies that resolve opaque handles at send time — tracked in `work/gaps.md`, deferred until a pack actually requires Boundary-2 guarantee rather than best-effort signal.
- **E-12 Surface B implementation.** ADR-FSSCOPE-01 specifies the contract; the runtime implementation (Landlock or audit-hook based) lands in E-12.
- **Per-payload CUE schemas for content-types.** Owned by ADR-CONTENT-01 in M-CONTRACT-04 (and even there the per-payload schemas are explicitly demand-driven, not in-scope).
- **Repo-wide CI integration of `cue vet` + schema-evolution loop.** Tracked as `work/gaps.md` "E-24 CI alignment"; M-CONTRACT-01 and the present milestone rely on local + pre-commit enforcement.

## Dependencies

- **M-CONTRACT-02 complete and merged** (foundational shapes — manifest, plan, opspec, replay, wire — and the schema-evolution loop's first contentful run). ADR-OPSPEC-01 in particular is a dependency for ADR-SECRETS-01: the warning event shape `:suspected_secret_leak` rides on the warning contract OPSPEC codifies, and ADR-OPSPEC-01 must be locked before ADR-SECRETS-01 references it concretely. ADR-TRIGGER-01 depends on ADR-MANIFEST-01 because trigger declarations live inside `pack.yaml`.
- **E-19 (Warnings & Degraded Outcomes) merged** — `Liminara.Warning`, the warning emission channel, and the `run_partial` terminal event taxonomy are referenced by ADR-SECRETS-01's Boundary 2 description. (E-19 is a transitive dependency through M-CONTRACT-02's ADR-OPSPEC-01.)
- **M-CONTRACT-01 complete and merged** — the CUE toolchain, local + pre-commit `cue vet` invocation, the schema-evolution loop, and the fixture-library directory layout are all required to land this milestone's schemas and fixtures. (Transitive through M-CONTRACT-02.)

## Contract matrix changes

Per `.ai-repo/rules/liminara.md` Contract matrix discipline.

- **Rows added:**
  - `surface-declaration` — Live source: paired CUE schema at `docs/schemas/surface-declaration/schema.cue` + ADR-SURFACE-01. Approved next: `runtime/apps/liminara_web/` `SurfaceRenderer` implementation in E-25. Drift guard: surface declarations validate against the schema; new widgets land via catalog edits, not ad-hoc declaration shapes.
  - `trigger` — Live source: paired CUE schema at `docs/schemas/trigger/schema.cue` + ADR-TRIGGER-01. Approved next: `TriggerManager` implementation in E-25 plus existing `runtime/apps/liminara_radar/lib/liminara/radar/scheduler.ex` for the cron path. Drift guard: trigger declarations validate against the schema; cron restart-recovery is fire-and-forget per the ADR's worked example, with E-14 named as the escalation path.
  - `file-watch` — Live source: paired CUE schema at `docs/schemas/file-watch/schema.cue` + ADR-FILEWATCH-01. Approved next: file-watch loop in E-25 plus `examples/file_watch_demo` in E-26 M-DX-03 as the named reference implementation. Drift guard: file-watch declarations validate against the schema; debounce / coalesce / scan-on-startup / dedup / rescan-on-restart semantics are fixed by the ADR.
  - `fs-scope` — Live source: paired CUE schema at `docs/schemas/fs-scope/schema.cue` + ADR-FSSCOPE-01. Approved next: **two surfaces** — Surface A (declaration integrity) live in `runtime/apps/liminara_core/lib/liminara/executor.ex` advisory check landed by E-25 M-RUNTIME-04; Surface B (runtime conformance) deferred to E-12 (Landlock or Layer 2 audit hooks). The matrix row text cites both surfaces; Surface B's live-source field reads "deferred to E-12" until that epic merges, at which point the same row is updated with the live source path. Drift guard: declaration integrity is checked advisory-only in MVP and emits a warning on violation; runtime conformance is enforced when E-12 lands.
  - `secrets` — Live source: paired CUE schema at `docs/schemas/secrets/schema.cue` + ADR-SECRETS-01. Approved next: `Liminara.Secrets.Registry` + `SecretSource` behaviour + `EnvVar` adapter in E-25 M-RUNTIME-03; `:suspected_secret_leak` warning emission per E-19's warning contract. Drift guard: secret declarations validate against the schema; Boundary 1 scrubbing is a runtime guarantee; Boundary 2 is best-effort signal with documented unrecoverable cases.

- **Rows updated:** none expected. The reviewer cross-checks the existing matrix at this milestone's review to confirm no row name in the parent sub-epic's plan-time list ("rows added") collides with an existing row. If a collision is found, the spec is amended at review.

- **Rows retired:** none.

## References

- Parent sub-epic: `work/epics/E-21-pack-contribution-contract/E-24-contract-design.md` (in particular the "ADRs produced" table, the "Per-ADR content requirements beyond the default set" subsection, and the anchored-citation success criterion).
- Parent epic: `work/epics/E-21-pack-contribution-contract/epic.md`.
- Predecessor milestone: `work/epics/E-21-pack-contribution-contract/M-CONTRACT-01-contract-tdd-tooling.md`.
- Successor milestones depending on this work: `work/epics/E-21-pack-contribution-contract/E-25-runtime-pack-infrastructure.md` (M-RUNTIME-03 SecretSource + Registry + scrub; M-RUNTIME-04 advisory FS-scope check), `work/epics/E-21-pack-contribution-contract/E-26-pack-dx.md` (M-DX-03 `examples/file_watch_demo`).
- Decisions: D-2026-04-01-008 (GenServer scheduler), D-2026-04-02-011 (layered sandbox), D-2026-04-02-017 (Oban deferred / GenServer scheduler reaffirmed), D-2026-04-23-030 (ADR filename / ID convention).
- E-12 epic spec: `work/epics/E-12-op-sandbox/epic.md`.
- E-14 epic (Postgres + Oban): roadmap entry at `work/roadmap.md`.
- E-19: `work/done/E-19/epic.md` and `M-WARN-01-runtime-warning-contract.md`.
- Contract matrix: `docs/architecture/indexes/contract-matrix.md`.
- Shim policy: `docs/governance/shim-policy.md`.
- Gaps: `work/gaps.md` ("Op sandbox: layered isolation not implemented"; "Secret-management maturity — pluggable SecretSource adapters + secret-observability hardening").
- Admin-pack architecture: `admin-pack/v2/docs/architecture/bookkeeping-pack-on-liminara.md`, `admin-pack/v2/docs/architecture/repo-layout.md`.
- CUE documentation: https://cuelang.org/.
