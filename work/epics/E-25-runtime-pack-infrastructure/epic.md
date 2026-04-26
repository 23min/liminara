---
id: E-25
parent: E-21
phase: 5c
status: planning
depends_on: E-24
---

# E-25: Runtime Pack Infrastructure

## Goal

Implement the runtime-internal plumbing that loads packs from manifests, dispatches their ops, renders their surfaces, manages their triggers, and injects their secrets — all while Radar continues to run end-to-end without modification to pack code.

When E-25 is done:
- `liminara_core` can load any pack conforming to ADR-MANIFEST-01 from a deployment config entry, call its plan entrypoints, dispatch its ops, and render its surfaces.
- Radar is loaded through the generic `PackLoader` (via a generated manifest for Radar-as-it-is) instead of hard-coded references. Radar's behaviour is unchanged.
- Multi-workflow packs with multiple plan entrypoints work end-to-end.
- `ex_a2ui` ships MultiProvider dispatch.
- `TriggerManager` fires `:cron`, `:file_watch`, and `:manual` triggers per manifest.
- Advisory FS-scope enforcement wraps op execution.
- `SecretSource` behaviour exists with an env-var adapter.

What does NOT land in E-25: the Python SDK, `liminara_widgets` widgets, CLIs, test harness, the file-watch demo pack (all E-26), and the extraction of Radar to a submodule (E-27).

## Context

E-24 ships the contract as data. E-25 is the runtime half of "can Liminara actually load a pack from a manifest?" — the validator of E-24's design choices. If the schemas in E-24 cannot be loaded by a realistic runtime implementation without heroic effort, the schemas are wrong.

The most important design property of E-25: **Radar continues to work throughout**. The way to validate a new pack-loader is to load Radar through it (via a generated manifest) and watch the existing Radar e2e test pass. E-27 extracts Radar to its own repo later; E-25 uses Radar as in-tree ground truth.

This sub-epic also establishes the `Liminara.Pack.API.*` namespace inside `liminara_core` as the Elixir language binding of the contract — not the contract itself, but a peer to the Python SDK. Future language SDKs bind the same contract differently.

## Scope

### In scope

- **`Liminara.Pack.API.*` namespace** inside `liminara_core`: organize the canonical structs (ExecutionSpec, OpResult, Warning, ExecutionContext, Plan, Decision) and behaviours (Pack, Op, Trigger) under the public surface. **`FSScope` is a net-new struct, not a reorganization**; it lands in M-RUNTIME-04 alongside the advisory enforcer that consumes it (shape per ADR-FSSCOPE-01).
- **`Liminara.PackLoader`**: reads a `pack.yaml` manifest from a declared path, validates against ADR-MANIFEST-01's CUE schema, builds the internal `Pack.API` representation including plan entrypoints, op list, trigger declarations, FS-scope, surfaces.
- **`Liminara.PackRegistry`**: reads `config :liminara, :packs, [...]` at boot and invokes `PackLoader` for each entry. Explicit, debuggable, no compile-time magic.
- **Generic plan invocation**: `PackRegistry` dispatches plan entrypoints to the correct executor (inline for Elixir packs, port for Python packs). Each plan entrypoint invocation returns plan-as-data that the runtime deserializes into `Liminara.Pack.API.Plan`.
- **`Liminara.TriggerManager`**: interprets trigger declarations from loaded packs; runs a cron scheduler (replacing Radar's bespoke scheduler), a file-watcher (watches declared FS-scope sub-paths with debounce + dedup semantics per ADR-FILEWATCH-01), and a manual-trigger API. Fires runs of the appropriate plan entrypoint when triggers fire.
- **`Liminara.SurfaceRenderer`**: reads surface declarations (YAML per ADR-SURFACE-01), translates widget layouts into A2UI wire messages, binds declared data sources (run state, event log, pack-instance artifacts) to widget props.
- **`Liminara.SecretSource` behaviour**: small contract — `fetch(name, deployment_config) :: {:ok, value} | {:error, reason}`. Ship one adapter (`Liminara.SecretSource.EnvVar`) for MVP. Runtime injects resolved secrets as env vars to ops at invocation time. **Secret observability is a two-boundary concern per ADR-SECRETS-01:** Boundary 1 (Liminara-internal) — resolved values go into `Liminara.Secrets.Registry` (per-run); every observation emitter scrubs outbound strings against the registry; reliable. Boundary 2 (pack-code discipline) — pack code receives plaintext env vars and can leak them by stringifying into op results, logs, or exception messages; the registry-driven scrub catches this best-effort and emits a `:suspected_secret_leak` warning event (E-19 shape) attributing the leak to the emitting op. This is not a runtime *guarantee*, it is a *best-effort signal*; the discipline rule is documented in ADR-SECRETS-01's authoring-guide section and the SDK ships a `scrub_secrets(text)` helper for pack authors who explicitly want a scrub point.
- **Advisory FS-scope enforcement** (Surface A per ADR-FSSCOPE-01's two-surface model): `Liminara.Executor` wraps op invocations with a **declaration-integrity check** — validates that declared `runtime_read_paths` and `runtime_write_paths` in the op's ExecutionSpec resolve under the pack's declared FS-scope root. Check source: the op's declaration (data). Warning event on violation; op still runs. **This is the complete MVP implementation of Surface A, not a weak version of a stronger check.** Surface B (runtime conformance — do actual syscalls stay inside the scope?) is added in E-12 and is a different observable; it does not supersede or strengthen the advisory check, it adds a second check.
- **A2UI MultiProvider dispatch in `ex_a2ui`**: server-side routing by surface-id prefix (e.g., `radar:runs_dashboard`, `bookkeeping:gate_queue`). Wire format stays A2UI v0.9. This is work in the `ex_a2ui` submodule repo; E-25 lands the submodule bump.
- **Multi-workflow plan dispatch**: when a pack declares N plan entrypoints, the `TriggerManager` invokes the correct one based on the trigger source. Validated by an **admin-pack-shape proxy pack** (see "Admin-pack-shape proxy" below): three plan entrypoints, mixed triggers (`:file_watch` + `:cron` + `:manual`), pack-instance state, declared secrets. Purpose is contract validation from a second live source, not domain functionality — the proxy is not admin-pack (which ships in E-22) and does not attempt admin-pack's bookkeeping domain.
- **Radar-as-manifest migration**: Radar gets a generated `pack.yaml` in-tree that represents its current shape. `PackLoader` loads it. Radar's existing e2e, replay, and briefing UI tests all pass. This is the validator for the entire sub-epic.

### Out of scope

- Python SDK / Elixir SDK / widget libraries / scaffolder / harness — E-26.
- Moving Radar to an external submodule — E-27.
- Custom JS widget bundles — the runtime supports the declaration shape (manifest references `custom-widgets/`), but building widget bundles is E-26's problem.
- Hard FS enforcement via Landlock — E-12.
- Durable trigger queue — E-14 (deferred; MVP is in-memory with file-watch recovery via directory rescan).
- Port executor process pooling — tracked in `work/gaps.md`; not E-25.
- Additional secret-source adapters beyond env-var — demand-driven.
- Fan-out / dynamic DAGs — E-16.

## Constraints

Shared E-21 constraints apply. Sub-epic-specific:

- **Radar must work at every merge point.** Every M-RUNTIME-* milestone includes running the Radar e2e + replay test. If it fails, the milestone is not done.
- **No public API additions that bypass E-24's schemas.** If E-25 needs a shape E-24 didn't specify, the correct action is to amend an E-24 ADR (+ its CUE schema + fixtures) first. No backdoor contracts.
- **The `Liminara.Pack.API.*` namespace is the Elixir language binding, not the contract.** Moving M-TRUTH-01's structs under this namespace is naming/organization only — no semantic changes to struct shapes or fields. The CUE schemas in E-24 are the ground truth; `Pack.API.*` is the Elixir manifestation.

## Success criteria

Success criteria are grouped by owning milestone to make the split explicit. The first phase is split across **M-RUNTIME-01 (namespace reorg + boundary)** and **M-RUNTIME-02 (loader + registry + Radar-through-pipeline + proxy-loaded)** — originally planned as one milestone, separated at plan-time per the 2026-04-23 ultrareview sizing analysis. See "Milestones" table below.

**M-RUNTIME-01 — Pack.API namespace + boundary enforcement:**
- [ ] `Liminara.Pack.API.*` namespace exists in `liminara_core` with the canonical structs and behaviours from M-TRUTH-01 organized under it. No struct-shape changes; pure reorganization. Old module paths (`Liminara.ExecutionSpec`, `Liminara.OpResult`, `Liminara.Warning`, `Liminara.ExecutionContext`, `Liminara.Plan`, `Liminara.Decision`) are **deleted** — no alias modules, no `defdelegate` re-exports, no `use` shims. Every call site is updated in the same milestone. The `ex_a2ui` submodule has zero `Liminara.*` references today (verified 2026-04-23); deletion cannot break it by construction. (`Liminara.Pack.API.FSScope` is net-new and lands in M-RUNTIME-04 — it is not a rename and has nothing to delete.)
- [ ] Boundary enforcement at compile time per ADR-BOUNDARY-01 lands **in M-RUNTIME-01** alongside the namespace reorg (the two together are the "shape before everything downstream" milestone): the `boundary` hex library is added as a runtime dep; `use Boundary` declarations land on `Liminara.Pack.API` and on the runtime/pack cross-cuts identified by the ADR. In-tree pack code can only reference `Liminara.Pack.API.*`; `mix compile` fails on a deliberate-violation fixture. OTP-app boundaries (`liminara_core` vs `liminara_observation` vs `liminara_web`) continue to enforce deployment-aligned cross-app access via `mix.exs` deps — the two mechanisms together cover all boundaries.
- [ ] All existing `liminara_core`, `liminara_observation`, `liminara_web`, `liminara_radar` test suites pass against the reorganized namespace (no behaviour changes; Radar still runs through its current hard-coded path — `PackLoader` does not yet exist).

**M-RUNTIME-02 — PackLoader + PackRegistry + Radar through the pipeline:**
- [ ] `Liminara.PackLoader` loads a `pack.yaml` from a given path, validates against the ADR-MANIFEST-01 CUE schema, and returns a `Pack.API` representation.
- [ ] **Pack-runtime schema-version compatibility check.** `PackLoader` reads the manifest's `schema_version` field (shape per ADR-MANIFEST-01), compares it against the runtime's current manifest schema version per the algorithm defined in ADR-EVOLUTION-01, and refuses to load incompatible packs. The error message names both versions explicitly, cites the compatibility rule that was violated, and points the pack author at the migration guidance in `docs/governance/schema-evolution-policy.md` (authored in E-27). Tested with a deliberate-skew fixture — at minimum: (a) a pack at the current version loads cleanly; (b) a pack declaring a supported older version loads or fails per the ADR's algorithm; (c) a pack declaring an unsupported version fails with the defined error shape.
- [ ] `Liminara.PackRegistry` reads `config :liminara, :packs` at boot, loads each pack via `PackLoader`, and exposes a lookup API (`PackRegistry.get(pack_id)`).
- [ ] **Provenance recording (pack identity in the event log).** `PackLoader` captures, at load time, the loaded pack's `pack_version` (from `pack.yaml`) and `git_commit_hash` (from the pack's checked-out submodule / git tree, or `"unversioned"` for in-tree dev packs whose commit is ambiguous). Each run's initial event (the run-start event) carries these two fields alongside `pack_id`. Purpose: the event log records *what code produced this run* as a recorded fact, independent of replay capability. Unlocks compliance / audit workflows ("VSME report in dispute — this run was produced by `radar-pack @ 1.2.0, git-hash abc123`; inspect the source by that hash") without requiring the runtime to re-execute old pack versions. Provenance is orthogonal to replayability: today's replay works only against the currently-loaded pack version (single-version semantics, Finding 17); cross-version replay is tracked as a separate gaps.md concern. Tested with a fixture: load a pack, start a run, assert the run-start event carries the expected `pack_version` + `git_commit_hash`.
- [ ] **Admin-pack-shape proxy pack — shape validation (loaded in B-01b, executed in B-03).** An in-tree example pack at `examples/admin_shape_proxy/` (or equivalent; exact path fixed by M-RUNTIME-02) with **three plan entrypoints** (intake / reconcile / export, shape-borrowed from admin-pack's documented three-workflow structure in `admin-pack/v2/docs/architecture/bookkeeping-pack-on-liminara.md`), **three trigger declarations** in its manifest (`:file_watch` intake, `:cron` reconcile, `:manual` export), declared pack-instance state, declared (mock) secrets. **M-RUNTIME-02 validates shape only**: `PackLoader` validates the manifest against CUE, `PackRegistry.get/1` returns a pack with three plans and three trigger declarations; the proxy's *manifest shape* exercises the contract from a second live source. **Dispatch (actually firing each trigger and running each plan end-to-end) lands in M-RUNTIME-04** when `TriggerManager` exists. **Explicitly not admin-pack** — no bookkeeping domain, no real PDFs, no real GL codes; this fixture exercises the contract's *shape pressures* alone while admin-pack's domain work remains E-22. Rationale: E-21's forcing-function argument (`roadmap.md:94`) requires a second live pack during E-21 — this fixture provides it without pulling admin-pack's domain work forward (see E-24's Admin-pack citation discipline success criterion for the paired mechanism).
- [ ] Radar has a generated `pack.yaml` in-tree; Radar is loaded through `PackLoader`; Radar's e2e, replay, and briefing UI tests all pass.
**M-RUNTIME-03 — SurfaceRenderer + SecretSource + A2UI MultiProvider:**
- (The SurfaceRenderer / SecretSource / MultiProvider criteria in this section are owned by M-RUNTIME-03.)

**M-RUNTIME-04 — TriggerManager + FSScope + FS-scope enforcement + proxy execution:**
- [ ] `Liminara.TriggerManager` supports `:cron`, `:file_watch`, `:manual`. File-watch semantics (debounce, coalesce, scan-on-startup, dedup) match ADR-FILEWATCH-01. Radar's scheduler is replaced by `TriggerManager`.
- [ ] **Cron restart-recovery semantics: fire-and-forget.** On runtime restart, `TriggerManager` recomputes each `:cron` trigger's next-fire time from the current wall clock. **Fire times that passed during downtime are not backfilled** (no catch-up runs emitted). This matches current Radar `Scheduler` behaviour per D-008 / D-017 and requires no new persistence infrastructure. The proxy pack's `:cron` execution test (see proxy-execution criterion below) includes a simulated-restart case that asserts no catch-up run fires for times passed during the downtime window. Richer catch-up semantics (once, all, manual) require durable scheduling state and are explicitly deferred to **E-14** (Postgres + Oban) — the E-14 epic owns the eventual policy decision there. ADR-TRIGGER-01 codifies fire-and-forget as the MVP contract and cross-references E-14 as the escalation path.
- [ ] `TriggerManager` exposes an observation API sufficient to replace today's `Liminara.Radar.Scheduler.next_run_at/1`, `last_run_at/1`, and `run_now/1` — i.e. every consumer must be able to ask "when does this trigger next fire?", "when did it last fire?", and "fire it now." Exact function signatures per ADR-TRIGGER-01. Radar's UI is migrated onto this API in the same milestone; the existing `Scheduler` GenServer is deleted.
- [ ] **Admin-pack-shape proxy pack — execution validation.** The proxy pack (loaded in M-RUNTIME-02) is now executed end-to-end: each of its three trigger declarations fires correctly (`:file_watch` on file drop, `:cron` on schedule, `:manual` on API call), dispatches to the correct plan entrypoint, runs the pack-instance-state mutations + mock-secret-resolution op, and produces the expected artifacts. **Cron fire-and-forget restart semantics test:** the suite also exercises a simulated-restart case — `TriggerManager` is stopped and restarted with wall-clock advanced past a scheduled cron fire time; assertion: no catch-up run is emitted, next-fire is computed from post-restart wall clock (matches ADR-TRIGGER-01's fire-and-forget semantics). This is the **forcing-function capstone**: a second live pack (not just Radar) running through the full contract, proving the contract can host admin-pack's shape when E-22 lands.
- [ ] `Liminara.SurfaceRenderer` loads surface declarations for a pack, translates to A2UI wire messages, and binds declared data sources. Radar's existing surfaces (once declared as YAML) render identically.
- [ ] `Liminara.SecretSource` behaviour exists; `Liminara.SecretSource.EnvVar` adapter resolves manifest-declared secrets from the deployment's env. **`Liminara.Secrets.Registry` (per-run state) tracks every resolved secret value**; every observation emitter (event log writer, A2UI message builder, logger) runs outbound strings through a registry-driven scrub that redacts matches to `[REDACTED:<name>]`. **On scrub-match, the runtime emits a `:suspected_secret_leak` warning event** (per E-19's warning contract) attributing the leak to the emitting op — this turns Boundary-2 best-effort scrubbing into an operational signal pack authors can see in the observation UI. Tested with a three-case deliberate-leak fixture: (a) direct logger leak (marker-based path — caught reliably); (b) pack-op stringify-return leak (registry-based path — caught best-effort with warning emitted); (c) split/base64-encoded leak (documented as NOT caught — warning contract matrix honestly records the best-effort boundary). See ADR-SECRETS-01 for the two-boundary classification.
- [ ] `Liminara.Pack.API.FSScope` struct lands as **net-new** in M-RUNTIME-04 (not a rename of anything existing). Shape per ADR-FSSCOPE-01 — represents the pack-instance FS-scope root that ops' paths must resolve under. `ExecutionSpec.Isolation.runtime_read_paths` / `runtime_write_paths` remain as-is (per-op path declarations); FSScope is the pack-level container they resolve within.
- [ ] **Advisory FS-scope enforcement — Surface A (declaration integrity).** `Liminara.Executor` checks that each op's declared `runtime_read_paths` / `runtime_write_paths` resolve under the pack's declared FS-scope root before invocation. Emits a warning event on violation; does not block the op. Tested with a deliberate-declaration-violation fixture (op declares a path outside the scope root → warning event emitted, op still runs). **This is the full implementation of Surface A**, not a weakened form of a stronger check. Surface B (runtime conformance: actual syscalls stay inside the scope root — Layer 2 audit hooks or Layer 3 Landlock) is added in E-12 and requires its own test fixtures ("op writes outside the scope root *without* declaring the path"). Two-surface model rationale + Layer 2/3 choice deferred to E-12 are documented in ADR-FSSCOPE-01 per the per-ADR content requirement in E-24.
- [ ] `ex_a2ui` MultiProvider dispatch ships in the submodule repo (PR merged there); the Liminara repo updates the submodule pointer. Upstream work item: [ex_a2ui#8](https://github.com/23min/ex_a2ui/issues/8). Coordination rule: `ex_a2ui` PR merges first, Liminara submodule-pointer bump is a separate PR with its own tests.
- [ ] All existing per-app test suites remain green at every milestone boundary (restated here because Radar's e2e + replay is the load-bearing signal across the whole sub-epic, per Technical direction "Radar is the live validator"). Boundary enforcement (now owned by M-RUNTIME-01) continues to hold; any violation introduced by later milestones fails compile.

## Milestones

| ID | Title | Summary |
|---|---|---|
| **M-RUNTIME-01** | Pack.API namespace + boundary | `Liminara.Pack.API.*` namespace organized; six old module paths deleted; 23 call-sites across `liminara_core` / `liminara_observation` / `liminara_web` / `liminara_radar` + test suites updated in-place. `boundary` hex library added as runtime dep; `use Boundary` declarations land on `Liminara.Pack.API` + runtime/pack cross-cuts per ADR-BOUNDARY-01; `mix compile` fails on a deliberate-violation fixture. **No new runtime features** — Radar still runs through its current hard-coded path. Every existing per-app test suite green. Comparable in size to M-TRUTH-02. |
| **M-RUNTIME-02** | PackLoader + PackRegistry + Radar migrates to pipeline | `Liminara.PackLoader` loads `pack.yaml` (CUE-validated), applies schema-version compat check per ADR-EVOLUTION-01, returns `Pack.API` representation. `Liminara.PackRegistry` reads `config :liminara, :packs` at boot. Radar gets a generated `pack.yaml` in-tree with the SHIM header comment; Radar loads through `PackLoader`; Radar e2e + replay + briefing UI tests green. **Admin-pack-shape proxy pack loads** (three plans + three trigger declarations in manifest; `PackRegistry.get/1` returns it with the declared shape) — proxy execution is deferred to M-RUNTIME-04 when `TriggerManager` exists. **M-RUNTIME-02's spec must include a `## Compatibility shims` section carrying the Radar-generated-manifest shim record (see sub-epic's Compatibility shims section); spec review blocks if absent. The shim file lands with the required SHIM header comment, and `work/gaps.md` gains an active entry at merge.** |
| **M-RUNTIME-03** | SurfaceRenderer + SecretSource + A2UI MultiProvider | `SurfaceRenderer` translates surface YAML to A2UI wire messages. `SecretSource` behaviour + env-var adapter. Secret scrubbing in logs/events. `ex_a2ui` MultiProvider merged in the submodule + pointer bumped. Radar's surfaces declared as YAML and rendered via `SurfaceRenderer`. Radar's observation UI unchanged from a user perspective. |
| **M-RUNTIME-04** | TriggerManager + FSScope + FS-scope enforcement + proxy execution | `TriggerManager` supports `:cron`, `:file_watch`, `:manual`. Radar's scheduler replaced. File-watch semantics per ADR-FILEWATCH-01. **`Liminara.Pack.API.FSScope` struct lands (net-new, shape per ADR-FSSCOPE-01).** Advisory FS-scope enforcement in `Executor` consumes the FSScope struct. **Admin-pack-shape proxy pack (loaded in B-01b) is now executed end-to-end**: each of its three triggers fires, the correct plan runs, pack-instance state mutates, mock secrets resolve — this is the forcing-function capstone. Radar e2e + replay green. |

## Technical direction

1. **Radar is the live validator.** If any M-RUNTIME-* milestone breaks Radar, the milestone is not done. The staged-loading approach (namespace reorg + boundary → loader + registry + Radar-through-pipeline → surface renderer → trigger manager + FSScope + proxy execution) means each milestone tests against Radar incrementally. The M-RUNTIME-01 / M-RUNTIME-02 split separates "Pack.API shape" from "runtime pack-loading" so each has its own green signal; this matches the repo's milestone cadence (see E-19 / E-20 precedents).
2. **Generated manifest for Radar is a declared compatibility shim** under `docs/governance/shim-policy.md`. It exists in-tree during E-25 to prove the pack-loader works. E-27 replaces it with Radar's own canonical authored manifest when Radar moves to its submodule. Full shim record: see "Compatibility shims" section below.
3. **`Liminara.Pack.API.*` is a namespace reorganization, not a rewrite.** Structs from M-TRUTH-01 keep their fields, defaults, and semantics; only their module paths change. Existing call sites are rewritten to the new paths in the same milestone — old module paths are deleted, not aliased.
4. **No compile-time magic in pack registration.** `config :liminara, :packs` is explicit; `PackRegistry.start_link/1` reads the config and loads packs. Tests can start the registry with an in-memory config.
5. **File-watch trigger MVP is advisory + recoverable.** File-watcher emits trigger events; dispatcher queues runs in-memory. On runtime restart, file-watcher rescans its declared path and re-emits for files not yet marked processed in pack-instance state. Durable queue is E-14.
5a. **Cron trigger MVP is fire-and-forget.** On runtime restart, `TriggerManager` recomputes next-fire from wall clock; fire times that passed during downtime are not backfilled. Matches current Radar `Scheduler` behaviour per D-008 / D-017; no new persistence required. Richer catch-up semantics (once, all, manual) are deferred to E-14 alongside Postgres + Oban, where the policy decision is owned by that epic. ADR-TRIGGER-01 codifies fire-and-forget as the MVP contract; B-03 tests assert no catch-up on a simulated restart.
6. **MultiProvider in `ex_a2ui` is server-side dispatch only.** Wire format stays A2UI v0.9. Surface IDs gain pack prefixes; Lit renderer needs no changes.
7. **Secret scrubbing is a two-boundary concern, not a single non-negotiable rule.** Boundary 1 (Liminara-internal emitters — event log writer, A2UI message builder, logger) runs outbound strings through `Liminara.Secrets.Registry` and reliably redacts known-secret values. Boundary 2 (pack-code stringifying a secret before returning it) is caught best-effort by the same registry-driven scrub and raises a `:suspected_secret_leak` warning event so pack authors see the leak in the observation UI and can fix the op. The three-case deliberate-leak fixture documents reliably-caught / best-effort-caught / not-caught scenarios so the contract boundary is auditable. Pack-authoring-guide discipline + an SDK-shipped `scrub_secrets()` helper handle the pack-side discipline. ADR-SECRETS-01 codifies both boundaries.

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Radar's existing code has implicit assumptions that break when loaded through the generic pack-loader | High | M-RUNTIME-02 lands with Radar loading through the new path. Every subsequent milestone re-runs Radar e2e. Issues surface immediately, not at E-27. |
| `ex_a2ui` MultiProvider ships out of sync with Liminara's consumer code | Med | Submodule-first discipline: PR merges in `ex_a2ui` repo, submodule bump in Liminara is a separate PR with test coverage. |
| `SurfaceRenderer` design leaks Liminara domain types into widget bindings | Med | ADR-SURFACE-01 specifies binding shapes that are data-only (event IDs, artifact hashes, pack-instance-path queries) — no runtime object graphs passed to widgets. Reviewer checks at wrap. |
| Secret values leak into observation events or logs | **High** | Explicit deliberate-leak test fixture; CI asserts no secret value appears in any emitted event or log line. |
| Trigger-manager's in-memory queue loses bursts on crash | Med | Known gap, documented in `work/gaps.md` and ADR-FILEWATCH-01. File-watch recovers by rescan. E-14 closes it. |
| File-watch debounce/coalesce semantics are wrong for admin-pack | Low | ADR-FILEWATCH-01 reviewed against admin-pack's documented requirements; settings are per-trigger configurable, not a single global tuning. |

## Compatibility shims

E-25 declares one compatibility shim under `docs/governance/shim-policy.md`. This section is the sub-epic-level shim record; **M-RUNTIME-02's spec (the milestone where the shim file lands) must carry its own `## Compatibility shims` section with the same record** when authored (spec review blocks on absence), per the policy's "owning milestone spec names the shim explicitly" rule.

### Radar generated `pack.yaml` — temporary in-tree scaffolding

- **Identity.** A generated `pack.yaml` for Radar lives in-tree (path fixed by M-RUNTIME-02 implementation; suggested `runtime/apps/liminara_radar/pack.yaml`). It expresses Radar's *current* shape in the ADR-MANIFEST-01 schema so `PackLoader` can load Radar through the generic code path.
- **Why the shim is allowed.** Without it, Radar dies the moment `PackRegistry` requires manifests; the alternative is a big-bang Radar extraction in one milestone — exactly what E-27 avoids by staging. It adapts shape, not semantics — Radar's execution, outputs, and artifacts are identical whether loaded through the old path or via this manifest.
- **Removal trigger.** E-27 M-RADX-02 replaces this with `radar-pack`'s own authored canonical `pack.yaml` when Radar moves to its submodule. The shim file is deleted in that same milestone.
- **Required file header comment.** The generated file's first lines must be a comment block that identifies it as a shim so anyone reading the raw file sees it. Minimum format:

  ```yaml
  # SHIM — E-25 Radar generated manifest.
  # Removal trigger: E-27 M-RADX-02 (Radar extraction to radar-pack submodule).
  # Policy: docs/governance/shim-policy.md
  # Gap: work/gaps.md — "Radar generated pack.yaml shim"
  ```

  M-RUNTIME-02's reviewer verifies this header is present before approving the PR that lands the file.
- **`work/gaps.md` entry.** The shim survives beyond its owning milestone (M-RUNTIME-02); it lives through M-RUNTIME-03, M-RUNTIME-04, E-26, and into the start of E-27. That triggers the policy's "gap entry" requirement. A `work/gaps.md` entry is added as part of M-RUNTIME-02's merge and names E-27 M-RADX-02 as the removal trigger.
- **Generation mechanism.** Whether the file is emitted by a tiny generator script, hand-authored-once-and-maintained, or regenerated from Radar's current shape at test boot is an implementation choice left to M-RUNTIME-02. Whichever mechanism is chosen, the file that `PackLoader` consumes must be the version that carries the SHIM header and lives at the path M-RUNTIME-02 declares — no invisible in-memory-only generation.
- **Classification against the policy.** Preserves truth under the shim-policy review question ("Does this preserve truth while creating a bounded migration step, or does it merely postpone naming the real contract?"): it creates a bounded migration step (one milestone to insert, one milestone to remove), preserves Radar's semantics exactly, and names the real contract (the authored `pack.yaml` that lands with Radar in `radar-pack`).

## Dependencies

- **E-24 must merge first.** Every public surface of E-25 is constrained by an E-24 ADR + CUE schema.
- **E-19 must be merged** (parent-epic constraint). ExecutionSpec codifies E-19's warning contract.
- **No dependency on E-26.** E-25 validates against Radar and the admin-pack-shape proxy pack; it does not require the Python SDK or external-author tooling.

## Hand-off to E-26

E-26 consumes the shapes E-25 produces:

- `Pack.API.*` structs are what the SDKs construct and the test harness asserts against.
- Wire protocol handshake from `PackLoader`-dispatched invocations is what `liminara-pack-sdk` (Python) implements client-side.
- `SurfaceRenderer`'s widget-binding shapes are what `liminara_widgets` widgets consume.
- `TriggerManager`'s trigger types are what manifests declare and what the test harness exercises.

## References

- Parent epic: `work/epics/E-21-pack-contribution-contract/epic.md`
- E-24 (prerequisite): `work/epics/E-21-pack-contribution-contract/E-24-contract-design.md`
- Port executor current implementation: `runtime/apps/liminara_core/lib/liminara/executor/port.ex`
- Run.Server current implementation: `runtime/apps/liminara_core/lib/liminara/run/server.ex`
- `ex_a2ui` submodule: `ex_a2ui/`
- Radar current code (the validator): `runtime/apps/liminara_radar/`, `runtime/python/src/ops/radar_*.py`, `runtime/apps/liminara_web/lib/liminara_web/live/radar_live/`
