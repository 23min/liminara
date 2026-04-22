---
id: E-21b-runtime-pack-infrastructure
parent: E-21-pack-contribution-contract
phase: 5c
status: planning
depends_on: E-21a-contract-design
---

# E-21b: Runtime Pack Infrastructure

## Goal

Implement the runtime-internal plumbing that loads packs from manifests, dispatches their ops, renders their surfaces, manages their triggers, and injects their secrets — all while Radar continues to run end-to-end without modification to pack code.

When E-21b is done:
- `liminara_core` can load any pack conforming to ADR-MANIFEST-01 from a deployment config entry, call its plan entrypoints, dispatch its ops, and render its surfaces.
- Radar is loaded through the generic `PackLoader` (via a generated manifest for Radar-as-it-is) instead of hard-coded references. Radar's behaviour is unchanged.
- Multi-workflow packs with multiple plan entrypoints work end-to-end.
- `ex_a2ui` ships MultiProvider dispatch.
- `TriggerManager` fires `:cron`, `:file_watch`, and `:manual` triggers per manifest.
- Advisory FS-scope enforcement wraps op execution.
- `SecretSource` behaviour exists with an env-var adapter.

What does NOT land in E-21b: the Python SDK, `liminara_ui` widgets, CLIs, test harness, the file-watch demo pack (all E-21c), and the extraction of Radar to a submodule (E-21d).

## Context

E-21a ships the contract as data. E-21b is the runtime half of "can Liminara actually load a pack from a manifest?" — the validator of E-21a's design choices. If the schemas in E-21a cannot be loaded by a realistic runtime implementation without heroic effort, the schemas are wrong.

The most important design property of E-21b: **Radar continues to work throughout**. The way to validate a new pack-loader is to load Radar through it (via a generated manifest) and watch the existing Radar e2e test pass. E-21d extracts Radar to its own repo later; E-21b uses Radar as in-tree ground truth.

This sub-epic also establishes the `Liminara.Pack.API.*` namespace inside `liminara_core` as the Elixir language binding of the contract — not the contract itself, but a peer to the Python SDK. Future language SDKs bind the same contract differently.

## Scope

### In scope

- **`Liminara.Pack.API.*` namespace** inside `liminara_core`: organize the canonical structs (ExecutionSpec, OpResult, Warning, ExecutionContext, Plan, Decision, FSScope) and behaviours (Pack, Op, Trigger) under the public surface.
- **`Liminara.PackLoader`**: reads a `pack.yaml` manifest from a declared path, validates against ADR-MANIFEST-01's CUE schema, builds the internal `Pack.API` representation including plan entrypoints, op list, trigger declarations, FS-scope, surfaces.
- **`Liminara.PackRegistry`**: reads `config :liminara, :packs, [...]` at boot and invokes `PackLoader` for each entry. Explicit, debuggable, no compile-time magic.
- **Generic plan invocation**: `PackRegistry` dispatches plan entrypoints to the correct executor (inline for Elixir packs, port for Python packs). Each plan entrypoint invocation returns plan-as-data that the runtime deserializes into `Liminara.Pack.API.Plan`.
- **`Liminara.TriggerManager`**: interprets trigger declarations from loaded packs; runs a cron scheduler (replacing Radar's bespoke scheduler), a file-watcher (watches declared FS-scope sub-paths with debounce + dedup semantics per ADR-FILEWATCH-01), and a manual-trigger API. Fires runs of the appropriate plan entrypoint when triggers fire.
- **`Liminara.SurfaceRenderer`**: reads surface declarations (YAML per ADR-SURFACE-01), translates widget layouts into A2UI wire messages, binds declared data sources (run state, event log, pack-instance artifacts) to widget props.
- **`Liminara.SecretSource` behaviour**: small contract — `fetch(name, deployment_config) :: {:ok, value} | {:error, reason}`. Ship one adapter (`Liminara.SecretSource.EnvVar`) for MVP. Runtime injects resolved secrets as env vars to ops at invocation time; log scrubbing ensures secret values never appear in observation events.
- **Advisory FS-scope enforcement**: `Liminara.Executor` wraps op invocations with a scope check — validates that declared `runtime_read_paths` and `runtime_write_paths` in the op's ExecutionSpec resolve under the pack's declared FS-scope root. Enforcement is advisory in MVP (warning event on violation); hard enforcement is E-12.
- **A2UI MultiProvider dispatch in `ex_a2ui`**: server-side routing by surface-id prefix (e.g., `radar:runs_dashboard`, `bookkeeping:gate_queue`). Wire format stays A2UI v0.9. This is work in the `ex_a2ui` submodule repo; E-21b lands the submodule bump.
- **Multi-workflow plan dispatch**: when a pack declares N plan entrypoints, the `TriggerManager` invokes the correct one based on the trigger source. Validated by a test pack with two plans + two triggers.
- **Radar-as-manifest migration**: Radar gets a generated `pack.yaml` in-tree that represents its current shape. `PackLoader` loads it. Radar's existing e2e, replay, and briefing UI tests all pass. This is the validator for the entire sub-epic.

### Out of scope

- Python SDK / Elixir SDK / widget libraries / scaffolder / harness — E-21c.
- Moving Radar to an external submodule — E-21d.
- Custom JS widget bundles — the runtime supports the declaration shape (manifest references `custom-widgets/`), but building widget bundles is E-21c's problem.
- Hard FS enforcement via Landlock — E-12.
- Durable trigger queue — E-14 (deferred; MVP is in-memory with file-watch recovery via directory rescan).
- Port executor process pooling — tracked in `work/gaps.md`; not E-21b.
- Additional secret-source adapters beyond env-var — demand-driven.
- Fan-out / dynamic DAGs — E-16.

## Constraints

Shared E-21 constraints apply. Sub-epic-specific:

- **Radar must work at every merge point.** Every M-PACK-B-* milestone includes running the Radar e2e + replay test. If it fails, the milestone is not done.
- **No public API additions that bypass E-21a's schemas.** If E-21b needs a shape E-21a didn't specify, the correct action is to amend an E-21a ADR (+ its CUE schema + fixtures) first. No backdoor contracts.
- **The `Liminara.Pack.API.*` namespace is the Elixir language binding, not the contract.** Moving M-TRUTH-01's structs under this namespace is naming/organization only — no semantic changes to struct shapes or fields. The CUE schemas in E-21a are the ground truth; `Pack.API.*` is the Elixir manifestation.

## Success criteria

- [ ] `Liminara.Pack.API.*` namespace exists in `liminara_core` with the canonical structs and behaviours from M-TRUTH-01 organized under it. No struct-shape changes; pure reorganization.
- [ ] `Liminara.PackLoader` loads a `pack.yaml` from a given path, validates against the ADR-MANIFEST-01 CUE schema, and returns a `Pack.API` representation.
- [ ] `Liminara.PackRegistry` reads `config :liminara, :packs` at boot, loads each pack via `PackLoader`, and exposes a lookup API (`PackRegistry.get(pack_id)`).
- [ ] A multi-workflow test pack (two plan entrypoints, two triggers) round-trips: deploy-config → load → trigger fires → correct plan runs.
- [ ] Radar has a generated `pack.yaml` in-tree; Radar is loaded through `PackLoader`; Radar's e2e, replay, and briefing UI tests all pass.
- [ ] `Liminara.TriggerManager` supports `:cron`, `:file_watch`, `:manual`. File-watch semantics (debounce, coalesce, scan-on-startup, dedup) match ADR-FILEWATCH-01. Radar's scheduler is replaced by `TriggerManager`.
- [ ] `TriggerManager` exposes an observation API sufficient to replace today's `Liminara.Radar.Scheduler.next_run_at/1`, `last_run_at/1`, and `run_now/1` — i.e. every consumer must be able to ask "when does this trigger next fire?", "when did it last fire?", and "fire it now." Exact function signatures per ADR-TRIGGER-01. Radar's UI is migrated onto this API in the same milestone; the existing `Scheduler` GenServer is deleted.
- [ ] `Liminara.SurfaceRenderer` loads surface declarations for a pack, translates to A2UI wire messages, and binds declared data sources. Radar's existing surfaces (once declared as YAML) render identically.
- [ ] `Liminara.SecretSource` behaviour exists; `Liminara.SecretSource.EnvVar` adapter resolves manifest-declared secrets from the deployment's env. Secret values are scrubbed from observation events and logs.
- [ ] Advisory FS-scope enforcement: `Liminara.Executor` emits a warning event on FS-scope violation; does not block the op. Tested with a deliberate-violation fixture. Advisory enforcement is the MVP contract, not a shim — E-12 hardens the observer (warning → block) on the same contract surface without changing its shape. Classification rationale and escalation path documented in ADR-FSSCOPE-01 per the "Enforcement escalation" section required by E-21a.
- [ ] `ex_a2ui` MultiProvider dispatch ships in the submodule repo (PR merged there); the Liminara repo updates the submodule pointer.
- [ ] Existing `liminara_core`, `liminara_observation`, and `liminara_web` tests all pass against the new infrastructure.
- [ ] Boundary enforcement at compile time per ADR-BOUNDARY-01: the `boundary` hex library is added as a runtime dep; `use Boundary` declarations land on `Liminara.Pack.API` and on the runtime/pack cross-cuts identified by the ADR. In-tree pack code can only reference `Liminara.Pack.API.*`; `mix compile` fails on a deliberate-violation fixture. OTP-app boundaries (`liminara_core` vs `liminara_observation` vs `liminara_web`) continue to enforce deployment-aligned cross-app access via `mix.exs` deps — the two mechanisms together cover all boundaries.

## Milestones

| ID | Title | Summary |
|---|---|---|
| **M-PACK-B-01** | PackLoader + PackRegistry | `Liminara.Pack.API.*` namespace organized. `PackLoader` + `PackRegistry` land. Multi-workflow test pack round-trips. Radar gets a generated manifest and loads through `PackLoader`. Radar e2e + replay green. |
| **M-PACK-B-02** | SurfaceRenderer + SecretSource + A2UI MultiProvider | `SurfaceRenderer` translates surface YAML to A2UI wire messages. `SecretSource` behaviour + env-var adapter. Secret scrubbing in logs/events. `ex_a2ui` MultiProvider merged in the submodule + pointer bumped. Radar's surfaces declared as YAML and rendered via `SurfaceRenderer`. Radar's observation UI unchanged from a user perspective. |
| **M-PACK-B-03** | TriggerManager + FS-scope enforcement | `TriggerManager` supports `:cron`, `:file_watch`, `:manual`. Radar's scheduler replaced. File-watch semantics per ADR-FILEWATCH-01. Advisory FS-scope enforcement in `Executor`. Radar e2e + replay green. |

## Technical direction

1. **Radar is the live validator.** If any M-PACK-B-* milestone breaks Radar, the milestone is not done. The staged-loading approach (manifest → loader → registry; then surface renderer; then trigger manager) means each milestone tests against Radar incrementally.
2. **Generated manifest for Radar is temporary scaffolding.** It exists in-tree during E-21b to prove the pack-loader works. E-21d replaces it with Radar's own canonical manifest when Radar moves to its submodule.
3. **`Liminara.Pack.API.*` is a namespace reorganization, not a rewrite.** Structs from M-TRUTH-01 keep their fields, defaults, and semantics; only their module paths change. Existing call sites update via module aliases.
4. **No compile-time magic in pack registration.** `config :liminara, :packs` is explicit; `PackRegistry.start_link/1` reads the config and loads packs. Tests can start the registry with an in-memory config.
5. **File-watch trigger MVP is advisory + recoverable.** File-watcher emits trigger events; dispatcher queues runs in-memory. On runtime restart, file-watcher rescans its declared path and re-emits for files not yet marked processed in pack-instance state. Durable queue is E-14.
6. **MultiProvider in `ex_a2ui` is server-side dispatch only.** Wire format stays A2UI v0.9. Surface IDs gain pack prefixes; Lit renderer needs no changes.
7. **Secret scrubbing is non-negotiable.** Every event emitter (event log writer, A2UI message builder, logger) filters values marked as secret-sourced. Tested with a deliberate-leak fixture.

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Radar's existing code has implicit assumptions that break when loaded through the generic pack-loader | High | M-PACK-B-01 lands with Radar loading through the new path. Every subsequent milestone re-runs Radar e2e. Issues surface immediately, not at E-21d. |
| `ex_a2ui` MultiProvider ships out of sync with Liminara's consumer code | Med | Submodule-first discipline: PR merges in `ex_a2ui` repo, submodule bump in Liminara is a separate PR with test coverage. |
| `SurfaceRenderer` design leaks Liminara domain types into widget bindings | Med | ADR-SURFACE-01 specifies binding shapes that are data-only (event IDs, artifact hashes, pack-instance-path queries) — no runtime object graphs passed to widgets. Reviewer checks at wrap. |
| Secret values leak into observation events or logs | **High** | Explicit deliberate-leak test fixture; CI asserts no secret value appears in any emitted event or log line. |
| Trigger-manager's in-memory queue loses bursts on crash | Med | Known gap, documented in `work/gaps.md` and ADR-FILEWATCH-01. File-watch recovers by rescan. E-14 closes it. |
| File-watch debounce/coalesce semantics are wrong for admin-pack | Low | ADR-FILEWATCH-01 reviewed against admin-pack's documented requirements; settings are per-trigger configurable, not a single global tuning. |

## Dependencies

- **E-21a must merge first.** Every public surface of E-21b is constrained by an E-21a ADR + CUE schema.
- **E-19 must be merged** (parent-epic constraint). ExecutionSpec codifies E-19's warning contract.
- **No dependency on E-21c.** E-21b validates against Radar and the multi-workflow test pack; it does not require the Python SDK or external-author tooling.

## Hand-off to E-21c

E-21c consumes the shapes E-21b produces:

- `Pack.API.*` structs are what the SDKs construct and the test harness asserts against.
- Wire protocol handshake from `PackLoader`-dispatched invocations is what `liminara-pack-sdk` (Python) implements client-side.
- `SurfaceRenderer`'s widget-binding shapes are what `liminara_ui` widgets consume.
- `TriggerManager`'s trigger types are what manifests declare and what the test harness exercises.

## References

- Parent epic: `work/epics/E-21-pack-contribution-contract/epic.md`
- E-21a (prerequisite): `work/epics/E-21-pack-contribution-contract/E-21a-contract-design.md`
- Port executor current implementation: `runtime/apps/liminara_core/lib/liminara/executor/port.ex`
- Run.Server current implementation: `runtime/apps/liminara_core/lib/liminara/run/server.ex`
- `ex_a2ui` submodule: `ex_a2ui/`
- Radar current code (the validator): `runtime/apps/liminara_radar/`, `runtime/python/src/ops/radar_*.py`, `runtime/apps/liminara_web/lib/liminara_web/live/radar_live/`
