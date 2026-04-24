---
id: E-21a-contract-design
parent: E-21-pack-contribution-contract
phase: 5c
status: draft
depends_on: E-19-warnings-degraded-outcomes
---

# E-21a: Pack Contract Design

## Goal

Produce the authoritative data contract for Liminara's pack contribution model — CUE schemas, ADRs, fixtures, worked examples, tooling — with **zero runtime code moves**. This sub-epic is the critical-path gate that every other E-21 sub-epic builds on.

When E-21a is done:
- The pack contract exists as a reviewable, testable document set.
- Schema conformance on any pack manifest or surface file can be enforced locally on demand and via pre-commit, and — when the repo-wide CI pipeline is stood up (separate initiative, explicitly deferred) — by CI using the same pinned CUE version.
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

- **Contract-TDD tooling** — a repo-level workflow that treats schemas + fixtures as the "tests" for contract designs, and ADRs + worked examples as the "specs." M-PACK-A-01 ships **only the Liminara-project-local parts**:
  - CUE toolchain in the devcontainer (pinned in a shared tool-versions file)
  - Local + pre-commit `cue vet` enforcement + schema-evolution loop
  - Fixture library directory layout established
  - **`.ai-repo/skills/design-contract.md`** — Liminara-specific project binding (references Radar, admin-pack, Liminara's contract matrix; overlays the generic framework skill if/when it exists)
  - **`.ai-repo/rules/contract-design.md`** — Liminara-specific reviewer-agent rule for CUE + fixtures + worked example review
  
  The **generic parts** — a generic `design-contract` skill skeleton for any CUE-using contract project + generic ADR template field extensions — are **upstream framework work**, tracked as [ai-workflow#37](https://github.com/23min/ai-workflow/issues/37). That upstream work does not block M-PACK-A-01; the Liminara-local `.ai-repo/` files stand alone, and if the upstream skill lands later they become overlays on it. Repo-wide CI enforcement is a separate, deferred initiative — E-21a sets up local-first tooling with a pinning mechanism that future CI will reuse verbatim.
- **All contract ADRs** listed in the parent epic, each paired with a CUE schema, fixtures (valid + invalid), and a worked example citing Radar and (where relevant) admin-pack's documented needs.
- **A named reference-implementation plan** for each ADR: which existing or near-future code validates the contract. Radar (after E-21d extraction) is the primary; `examples/file_watch_demo` (shipped in E-21c) is the secondary for `:file_watch`.
- **A schema-evolution check** — a loop over `cue vet` that validates every historical fixture against the current (HEAD) schemas. Layered on CUE, not a separate validation engine; see "Schema-evolution check — specification" below for fixture-library layout, backward-compat-not-forward scope, and failure semantics. Runnable locally and via pre-commit; wired into CI alongside `cue vet` when the repo-wide CI pipeline is stood up.

### Out of scope

- Any runtime code (PackLoader, PackRegistry, SurfaceRenderer, etc.) — that is E-21b.
- Any SDK or tooling (Python SDK, CLIs, widgets, harness) — that is E-21c.
- Radar extraction — that is E-21d.
- Admin-pack — that is E-22.
- **Per-content-type payload CUE schemas.** ADR-CONTENT-01 defines the **namespace shape** for content-type identifiers (see per-ADR requirements below); per-payload CUE schemas (what fields a specific content-type's artifact body must have) are **demand-driven** — packs author them when they want mechanical payload validation. The runtime validates the namespace string, not the payload body, in MVP.

## Constraints

All shared constraints from E-21's parent epic apply. Sub-epic-specific:

- **No code moves in this sub-epic.** The only code-like artifacts shipped are: the Liminara-local `.ai-repo/skills/design-contract.md` project binding + `.ai-repo/rules/contract-design.md` reviewer rule, shared tool-versions pin + Dockerfile wiring for CUE, pre-commit hook configuration, and schema + fixture files. Generic framework template changes are upstream (ai-workflow#37), not in this sub-epic. Anything that changes the behaviour of `liminara_core` or `liminara_web` belongs to E-21b.
- **Every ADR has a passing `cue vet` fixture set.** An ADR without fixtures is not done.
- **Every ADR names its reference implementation** — the existing or near-future code that demonstrates the contract on real work. "TBD" is not an acceptable reference.

## Success criteria

- [ ] **Liminara-local `design-contract` skill** exists at `.ai-repo/skills/design-contract.md` as a **flat `.md` file** (the `.ai-repo/skills/` convention; sync via `./.ai/sync.sh` produces the folder-per-skill output at `.claude/skills/design-contract/SKILL.md`). **Authoring note for whoever builds this:** do not hand-write the folder-form output; drop the `.md` source only, then run the sync. The skill's content is **Liminara-specific bindings only** — references to Radar, admin-pack, the Liminara contract matrix, reviewer rules for cross-pack pressure. The generic workflow skeleton (draft ADR → write CUE schema → write fixtures → write worked example → name reference implementation → review → merge) is upstream framework work (ai-workflow#37); this Liminara-local file stands alone and overlays the upstream skill if/when it lands.
- [ ] **Liminara-local `contract-design` rule** exists at `.ai-repo/rules/contract-design.md`, enforceable by the reviewer agent. Scope: Liminara-specific reviewer discipline (e.g. "every pack-level ADR needs anchored admin-pack citation," "contract-matrix rows verified at wrap," "boundary library violations block compile") — binds to Liminara's project conventions, not generic CUE workflow.
- [ ] CUE is installed in the devcontainer with a pinned version sourced from a **shared tool-versions file at repo root** (`tool-versions.env`, `.tool-versions`, or equivalent — exact format chosen in M-PACK-A-01). The Dockerfile reads this file to install `cue`; developers get the same version automatically on devcontainer rebuild.
- [ ] **Local enforcement:** `cue vet` is invocable on demand against any `.cue` file and against the full fixture set (a single make target / script so contributors don't have to remember the invocation).
- [ ] **Pre-commit enforcement:** a pre-commit hook runs `cue vet` on staged `.cue` files and blocks the commit on schema violations. Hook installation is idempotent and part of the `design-contract` skill onboarding checklist. (`--no-verify` remains a developer escape hatch; CI-level enforcement that can't be bypassed is deferred to the separate CI initiative described below.)
- [ ] **Future CI alignment (not gated by E-21a):** when the repo-wide CI pipeline is stood up, its `cue vet` job reads the CUE version from the same tool-versions file, guaranteeing zero drift between local and CI. Option-A-style alignment (running the CI job inside the devcontainer image) is a valid future evolution on top of this file; it is not required by E-21a. Tracked in `work/gaps.md` as the "E-21a CI alignment" follow-up.
- [ ] **Generic ADR template extensions are upstream framework work** ([ai-workflow#37](https://github.com/23min/ai-workflow/issues/37)) — schema path, fixtures path, worked example path, reference implementation citation fields belong in `.ai/templates/adr.md` and benefit every CUE-using contract project, not just Liminara. **M-PACK-A-01 does not ship framework template changes.** If the upstream issue lands before M-PACK-A-02a starts, ADR authors benefit directly; if it lands later, ADR authors add the fields inline per ADR and backfill the template when upstream supports them. No Liminara-local template overlay is needed.
- [ ] Every ADR listed in the *ADRs produced* table below is merged with its accompanying CUE schema, valid/invalid fixtures, and worked example. (Counting rule: the table is the source of truth; if a row is added or removed during E-21a, that change is the scope change — no separate `N` needs updating.)
- [ ] The schema-evolution check runs locally + on pre-commit per the "Schema-evolution check — specification" subsection below: loop over `cue vet` across the accumulated fixture library; fixtures organized under `docs/schemas/<topic>/fixtures/v<N>/`; backward-compat only (historical fixtures against HEAD schemas); forward-compat explicitly not tested. Same hook mechanism as `cue vet`; reuses the shared tool-versions pin. Wired into CI alongside `cue vet` as part of the deferred CI initiative.
- [ ] Pack-contract discovery is served by `docs/architecture/indexes/contract-matrix.md` — each pack-contract ADR, schema, and fixture set gets a row there rather than a separate per-family index. (Per ADR-0003 sub-decision 1, the renamed contract-matrix *is* the index.)
- [ ] Downstream sub-epic specs (E-21b, E-21c, E-21d) reference specific ADRs for every design choice they inherit.
- [ ] M-PACK-A-02a, M-PACK-A-02b, and M-PACK-A-02c each declare their contract-matrix row deltas as explicit acceptance criteria in the milestone spec (`## Contract matrix changes`), and land those rows in `docs/architecture/indexes/contract-matrix.md` as part of the milestone's merge. Rule reference: `.ai-repo/rules/liminara.md` → Contract matrix discipline.
- [ ] **Admin-pack citation discipline (anti-ceremony gate).** Every pack-level ADR (ADR-MANIFEST-01, ADR-PLAN-01, ADR-OPSPEC-01, ADR-SURFACE-01, ADR-TRIGGER-01, ADR-FILEWATCH-01, ADR-FSSCOPE-01, ADR-SECRETS-01, ADR-CONTENT-01, ADR-LAYOUT-01, ADR-REGISTRY-01, ADR-MULTIPLAN-01 — the ones whose secondary reference is an admin-pack citation) must cite a **specific file + section anchor** inside `admin-pack/v2/docs/architecture/` (e.g. `bookkeeping-pack-on-liminara.md §4.2 — per-receipt lifecycle`), not a generic "see admin-pack" reference. The M-PACK-A-02* reviewer follows every such citation, reads the cited section, and judges whether the ADR's design genuinely satisfies the cited need — not merely whether a citation is present. This is the "anti-ceremony" check that replaces the structural admin-pack-runs-in-E-21 absence (see epic risks table + Option-C fixture in E-21b). The ADR template's secondary-reference field is updated to require the anchor syntax; unanchored citations block ADR merge. (ADRs whose secondary reference is not admin-pack — ADR-LA-01, ADR-WIRE-01, ADR-BOUNDARY-01, ADR-EXECUTOR-01, ADR-EVOLUTION-01 — are not subject to this gate but still require their secondary reference to be substantive per the existing risks-table rule.)

## ADRs produced

Each ADR ships with: CUE schema, valid fixtures, invalid fixtures (demonstrating what `cue vet` rejects), worked example (one or two realistic pack snippets), and a named reference implementation citation.

| ADR | Title | Primary reference | Secondary reference |
|---|---|---|---|
| **ADR-LA-01** | Language-agnostic pack contribution | Radar (mixed), admin-pack (Python) | — |
| **ADR-MANIFEST-01** | Pack manifest schema (YAML + CUE) | Radar generated manifest | admin-pack manifest sketch |
| **ADR-PLAN-01** | Plan representation (language-agnostic data) | Radar plan output | admin-pack plan sketch |
| **ADR-OPSPEC-01** | Op execution spec CUE schema (codifies M-TRUTH-01; includes terminal event taxonomy `run_completed` / `run_partial` / `run_failed` per D-2026-04-20-025) | Radar ops | admin-pack op sketches |
| **ADR-REPLAY-01** | Run-level replay protocol: event-log walk order, decision injection, partial-run re-entry, replay `Run.Result` shape. Per-op replay semantics stay in ADR-OPSPEC-01's `determinism.replay_policy`; this ADR covers the run-wide protocol. **Pack-version skew handling is explicitly out of scope** (no code validates it today; deferred to `work/gaps.md` → "Cross-version pack replay semantics"); **provenance recording** (pack_version + git_commit_hash in run's initial event) is a separate M-PACK-B-01b acceptance criterion and is referenced here but not the ADR's concern. | Radar replay suite (`runtime/apps/liminara_core/test/liminara/run/replay_test.exs`) + `Liminara.rebuild_from_events/2` | D-2026-04-05-023 (Radar run identity from ExecutionContext) |
| **ADR-WIRE-01** | Port wire protocol schema | Radar Python ops today | — |
| **ADR-SURFACE-01** | Surface declaration schema + widget catalog | Radar runs_dashboard | admin-pack period view |
| **ADR-TRIGGER-01** | Trigger declaration (`:cron`, `:file_watch`, `:manual`) | Radar scheduler | admin-pack intake |
| **ADR-FILEWATCH-01** | File-watch trigger semantics (debounce, coalesce, scan-on-startup, dedup, in-memory queue + rescan-on-restart) | `examples/file_watch_demo` (scheduled — E-21c M-PACK-C-03) | admin-pack receipt intake |
| **ADR-FSSCOPE-01** | Pack-instance FS-scope declaration | Radar (lancedb_path) | admin-pack data_root |
| **ADR-SECRETS-01** | Secrets declaration + `SecretSource` behaviour | Radar API keys | admin-pack Gmail creds |
| **ADR-CONTENT-01** | Content-type identifier shape + namespace + collision + evolution rules (payload schemas explicitly out of scope — demand-driven per pack). Identifier form: `<pack_id>.<type_name>@<major>`. See per-ADR content requirements below. | Radar content types | admin-pack item types |
| **ADR-EXECUTOR-01** | Executor-type taxonomy + extensibility (persistent-worker stipulation) | Existing `:inline` + `:port` | future `:container` / `:wasm` |
| **ADR-EVOLUTION-01** | Schema evolution and backward-compat discipline | Kubernetes API versioning | Protobuf evolution |
| **ADR-LAYOUT-01** | Pack repo layout conventions | Radar (post-extraction) | admin-pack |
| **ADR-BOUNDARY-01** | Compile-time boundary enforcement for in-tree packs (`boundary` hex lib + OTP-app splits) | Radar | — |
| **ADR-REGISTRY-01** | Pack registration via deployment config | Radar load path | admin-pack load path |
| **ADR-MULTIPLAN-01** | Multi-workflow packs (multiple plan entrypoints per pack) | Radar (single-plan today) | admin-pack (three-plan) |

Each ADR lives under `docs/decisions/` following the existing ADR convention; the paired CUE schema lives under `docs/schemas/<topic>/schema.cue`; fixtures live under `docs/schemas/<topic>/fixtures/v<N>/`.

**Per-ADR content requirements beyond the default set:**
- **ADR-FSSCOPE-01** must specify **two distinct contract surfaces**, not one surface with a strengthened observer. The earlier "same surface, warning → block" framing was wrong on the facts — the two checks observe different properties and are complementary, not strength-ordered. The ADR must name both surfaces, name which milestone ships which, and state explicitly that E-12's check is a **surface addition**, not a strengthening.
  1. **Surface A — Declaration integrity.** Does the op's declared `runtime_read_paths` / `runtime_write_paths` (from `ExecutionSpec.Isolation`) resolve under the pack's declared FS-scope root? Source of truth: the declared data. Check time: before invocation. **Shipped in MVP** via `Liminara.Executor`'s advisory check (M-PACK-B-03); warning event on violation; op still runs. This surface is not strengthened by E-12 — declaration integrity is already fully checked in MVP.
  2. **Surface B — Runtime conformance.** Do the op's actual filesystem syscalls (`open`, `openat`, `renameat`, …) stay within the declared FS-scope root? Source of truth: runtime behaviour. Check time: during op execution. **Not shipped in MVP — added in E-12** (Landlock or equivalent kernel sandbox). Catches the case "op declares `/tmp/ok` but writes `/etc/passwd`" that Surface A cannot catch. Layer 2 Python-runner audit hooks (per `work/gaps.md` op-sandbox entry + D-2026-04-02-011) are a best-effort alternative implementation of Surface B that predates Landlock; which of Layer 2 / Layer 3 lands first is an E-12-era choice, not an E-21a choice.
  
  The ADR's shim-policy classification becomes: **neither mode is a shim** (policy test 2 holds for both — neither preserves a lie). MVP ships Surface A fully; E-12 adds Surface B; both surfaces coexist after E-12. The contract matrix row for fs-scope should therefore cite both surfaces, with their live sources updated as each lands. The ADR must **not** claim "advisory is an intermediate contract, not a shim" — that framing rested on the one-surface premise; correct framing is "both surfaces are first-class contract shapes from the start, but the runtime implementation of Surface B arrives in E-12."
  
  The ADR's test-coverage guidance must specify that Surface A's test fixture ("op declares path outside FS-scope root → warning") does not cover Surface B's test fixture ("op writes path outside FS-scope root without declaring it → Landlock kill / audit-hook warning"). E-12 will need its own fixtures.
- **ADR-EVOLUTION-01** must answer four specific questions about pack-runtime version compatibility — the ADR cannot punt any of them:
  1. **Declaration format and placement.** How does a pack's `pack.yaml` declare which manifest schema version it was authored against? (Semver string? Integer major? What key? What default if the field is absent?)
  2. **Compatibility algorithm.** When `PackLoader` encounters a pack declaring `schema_version: X` while the runtime's current schema is `Y`, what happens? Strict-major-match? Range-based? Multi-schema-dispatch? The ADR names one algorithm and justifies the choice against the design-space alternatives (see parent epic's schema-evolution section for the shortlist).
  3. **Historical-schema maintenance policy.** Does the runtime ship only the current schema or multiple historical schemas for a deprecation window? If multiple: how long is the window, and what triggers removal (Liminara major version bump? Pack-stakeholder signal?)
  4. **Deprecation-window semantics.** When a pack declares a soon-to-be-retired schema version, what does the runtime do? Load and warn? Load with a UI badge? Refuse to load N versions before removal?

  The ADR's worked example must include a pack-declared-version-vs-runtime-version skew scenario that exercises the chosen algorithm end-to-end.
- **ADR-MANIFEST-01** must specify the `schema_version` field whose shape `ADR-EVOLUTION-01` operates on — format, placement in the manifest, required-vs-optional status, default value (or error) if omitted. The two ADRs cross-reference: `ADR-MANIFEST-01` owns the field's shape in the data, `ADR-EVOLUTION-01` owns the compatibility algorithm over that field. `ADR-MANIFEST-01` cannot land without the field specified.
- **ADR-TRIGGER-01** must codify `:cron` trigger restart-recovery semantics as **fire-and-forget**: on runtime restart, next-fire time is recomputed from wall clock; fire times that passed during downtime are not backfilled. Rationale and upstream decisions: matches current Radar `Scheduler` behaviour per D-008 / D-017; requires no new persistence infrastructure (durable state is explicitly out of E-21's scope). The ADR's worked example must include a simulated-restart scenario spanning a missed fire time, asserting no catch-up run is emitted. The ADR cross-references **E-14** (Postgres + Oban) as the escalation path: richer catch-up semantics (catch-up-once, catch-up-all, manual-catch-up-only) require durable scheduling state and are decided by E-14's epic when that work lands. File-watch restart semantics are separately specified by ADR-FILEWATCH-01 (rescan-on-startup + pack-instance-state ledger) and are independent of the cron decision.
- **ADR-SECRETS-01** must specify **two distinct contract boundaries**, not a single "secrets are scrubbed" rule. The framing mirrors ADR-FSSCOPE-01's two-surface model: both boundaries are first-class; the MVP implementation covers them differently.
  1. **Boundary 1 — Liminara-internal scrubbing (reliable).** Every observation emitter (event log writer, A2UI message builder, logger) runs outbound strings through `Liminara.Secrets.Registry` (a per-run registry of resolved secret values). Matches are redacted to `[REDACTED:<name>]`. This boundary is a runtime *guarantee*.
  2. **Boundary 2 — Pack-code discipline (best-effort signal).** Pack code receives resolved secrets as plaintext env vars (or whatever shape `SecretSource` produces). If pack code stringifies a secret into op results, exception messages, or logs, the runtime's registry-driven scrub *catches it best-effort at emission time* and emits a `:suspected_secret_leak` warning event (per E-19's warning contract) attributing the leak to the emitting op. This is a *signal*, not a guarantee — the scrub works on exact-match strings and does not catch split, base64-encoded, hashed, or otherwise-transformed leaks.
  
  The ADR must state explicitly which failure modes are caught (direct logger leak via marker; pack-op stringify-return; exception message containing secret) and which are not (split across fields; base64-encoded; hashed). The ADR's authoring-guide section codifies the pack-code discipline rule: "never `str(secret)` or include secrets in exception messages; use the SDK-provided `scrub_secrets(text)` helper when you must render a string that might touch them." The ADR must **not** claim runtime-enforced secret safety — that framing would require Approach-D-style runtime-mediated capability proxies that are out of scope (and tracked in `work/gaps.md` under "Pluggable SecretSource adapters + secret-observability maturity"). The `SecretSource` behaviour itself is the plumbing for *secret delivery* (where secrets come from — env var in MVP, Vault / Key Vault / Doppler as future adapters); secret observability is a separate concern.
  
  The ADR's worked example must include the three-case deliberate-leak fixture from E-21b M-PACK-B-02 (direct, pack-stringify-return, split-unrecoverable) with the expected outcome for each.
- **ADR-CONTENT-01** scope is the **content-type namespace**, not per-payload schemas. The ADR must specify:
  1. **Identifier shape.** Content-type IDs follow the form `<pack_id>.<type_name>@<major_version>` (e.g. `radar.cluster_summary@1`, `admin.receipt_candidate@2`). Dot separates pack_id from type_name; `@` marks the version boundary; the version is a **single major-version integer**, not full semver (minor/patch changes are backward-compat by CUE unification per ADR-EVOLUTION-01 and not part of type identity — two artifacts emitted at `@1` must be interchangeable regardless of intra-major schema drift). Rationale for dot+at over colon-delimiter (`<pack_id>:<type_name>:<version>`): filesystem-path safety (colons are invalid in Windows paths), URL-reserved-character avoidance, distinct delimiters make each field's role visually distinct, and explicit `@` marker gives mechanically-parseable error messages.
  2. **Validity rules.** Regex / CUE validator for the string itself. `pack_id` is a lowercase identifier matching `[a-z][a-z0-9_]*` (flat — no dots; hierarchical pack_ids are explicitly out of scope). `type_name` same shape. Version is a positive integer. The full ID validates as: `^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*@[1-9][0-9]*$` or CUE equivalent.
  3. **Cross-pack collision rules.** A pack may only emit artifacts whose content-type IDs start with its declared `pack_id`. The runtime validates at artifact emission time (in `PackLoader`/`Executor`); an op that tries to emit `radar.cluster_summary@1` from `admin-pack` fails with a structured error. Reserved `pack_id` values (e.g. `runtime`, `liminara`, `system`) are blocked from pack-level emission.
  4. **Evolution rules.** Additive changes to a content-type's payload schema (new optional fields, widened types) stay at the same `@<major>`. Breaking changes bump to a new `@<major+1>` (e.g. `radar.cluster_summary@1` → `radar.cluster_summary@2`); both versions may coexist in the content-type registry until the pack declares a deprecation removal trigger. This rule is a *binding* from ADR-EVOLUTION-01 applied to content-types.
  5. **Out of scope: per-payload CUE schemas.** What fields `radar.cluster_summary@1` actually carries is the *pack's* concern, not the runtime's. Per-payload schemas are demand-driven — authored by packs when they want mechanical payload validation (useful for contract-matrix rows, cross-pack interop, debugging). The MVP runtime validates the namespace string shape at emission time; payload validation at the content-type level is deferred.
  
  The ADR's worked example must include at least four content-type IDs from real packs (two from Radar, two from admin-pack's documented item types) plus one deliberate-invalid fixture (collision attempt, reserved pack_id, wrong shape) showing the expected error.

## Milestones

| ID | Title | Summary |
|---|---|---|
| **M-PACK-A-01** | Liminara-project Contract-TDD tooling | Ship **Liminara-project-local parts only**: CUE in devcontainer (pinned via shared tool-versions file), local + pre-commit `cue vet` hook, schema-evolution check loop, fixture library directory layout, Liminara-local `.ai-repo/skills/design-contract.md` (project bindings) + `.ai-repo/rules/contract-design.md` (reviewer rule). **Not in scope**: generic framework skill skeleton or ADR template extensions — those are upstream framework work ([ai-workflow#37](https://github.com/23min/ai-workflow/issues/37)) and do not gate this milestone. Repo-wide CI integration is also deferred; the shared tool-versions file is the mechanism by which future CI will match local without drift. One-sitting milestone. |
| **M-PACK-A-02a** | Foundational contracts (5 ADRs) | Ship ADR-MANIFEST-01, ADR-PLAN-01, ADR-OPSPEC-01, ADR-REPLAY-01, ADR-WIRE-01 with CUE schemas + fixtures + worked examples. These are the hot path — every other sub-epic blocks on their shape. Ship the schema-evolution compat check (local + pre-commit) in this milestone — it runs against these first schemas and every one that follows. Lands contract-matrix rows for `manifest`, `plan-as-data`, `op-execution-spec`, `replay-protocol`, `wire-protocol`. Refresh the existing warning-contract row to reflect E-19's shipped `Liminara.Warning` + `run_partial` terminal event. |
| **M-PACK-A-02b** | Packs-as-running-systems (5 ADRs) | Ship ADR-SURFACE-01, ADR-TRIGGER-01, ADR-FILEWATCH-01, ADR-FSSCOPE-01, ADR-SECRETS-01 with CUE schemas + fixtures + worked examples. These define how a loaded pack interacts with the world (UI, triggers, filesystem, secrets). Unblocks the bulk of E-21b's runtime plumbing. Lands contract-matrix rows for `surface-declaration`, `trigger`, `file-watch`, `fs-scope`, `secrets`. |
| **M-PACK-A-02c** | Governance (8 ADRs) | Ship ADR-REGISTRY-01, ADR-MULTIPLAN-01, ADR-EXECUTOR-01, ADR-EVOLUTION-01, ADR-LAYOUT-01, ADR-BOUNDARY-01, ADR-CONTENT-01, ADR-LA-01 with CUE schemas + fixtures + worked examples. These govern how packs are registered, composed, extended, and bounded. **Partial parallelism with M-PACK-A-02b**: once M-PACK-A-02a's foundational shapes are frozen, five of these eight can start in parallel with M-PACK-A-02b authoring — ADR-EXECUTOR-01, ADR-EVOLUTION-01, ADR-BOUNDARY-01, ADR-CONTENT-01, ADR-LA-01 (all independent of 02b's specific shapes). The remaining three must wait for M-PACK-A-02b to freeze: ADR-REGISTRY-01 (needs 02b's declarable shapes for config entries), ADR-MULTIPLAN-01 (binds to ADR-TRIGGER-01), ADR-LAYOUT-01 (depends on ADR-SURFACE-01's surface-file shape). Lands contract-matrix rows for the governance contracts that have live sources (`registry`, `executor-taxonomy`, `layout`, `boundary` at minimum; authors evaluate whether meta-ADRs like `schema-evolution`, `language-agnostic`, `multi-plan`, `content-namespace` warrant rows when drafting the milestone spec). |

## Schema-evolution check — specification

The schema-evolution check is **not a separate test harness**. It is a convention layered on `cue vet`: a loop that walks the accumulated fixture library and invokes `cue vet` once per fixture against HEAD schemas. CUE is the validator; the loop is ~20 lines of shell or elixir that every CUE shop writes some variant of. This subsection specifies the layered conventions so M-PACK-A-02a's author ships an unambiguous check, not the test implementation itself (which is trivial once the conventions are pinned).

- **Fixture library layout.** Fixtures live under `docs/schemas/<topic>/fixtures/v<N>/<name>.yaml` (version = the schema version the fixture was authored against, e.g. `v1.0.0`). Adding a new fixture under a new `v<N>/` directory is how the library grows.
- **What "historical fixtures" means.** Every fixture ever committed to the library. Fixtures are never rewritten retroactively when a schema evolves — they stay frozen at their authored version. (If a fixture genuinely needs to change, it moves to a new `<version>/` directory.)
- **What the check does on every commit touching `.cue` or `fixtures/`.** Walk the library; for each fixture, run `cue vet <topic>.cue <fixture>` against the HEAD schema for that topic. If any fixture fails, the check fails.
- **Backward compatibility is the goal; forward compatibility is not.** Old fixtures must validate against the current (HEAD) schema — that is the "additive changes stay backward-compatible" property, enforced mechanically by CUE unification. **Current fixtures against historical schemas is explicitly not tested** — bumping a schema is always additive unless a deliberate major-version bump + deprecation ADR is declared. Forward-compat is not a contract Liminara promises.
- **Failure semantics.** The check outputs `<fixture path> fails against <topic>.cue at <schema path>: <CUE error>`. Fix path for the ADR author / contributor: either (a) amend the schema change to be additive (CUE unification-compatible), or (b) bump the schema's major version and land a deprecation ADR naming the breaking change. (See ADR-EVOLUTION-01 for which path applies to which class of change.)
- **How fixtures get labelled with versions.** M-PACK-A-02a lands the first schemas at `v1.0.0`; fixtures committed alongside them live under `.../<topic>/v1.0.0/`. When a schema bumps to `v1.1.0` (additive) or `v2.0.0` (breaking), new fixtures authored against that shape go into the matching `<version>/` directory. Old fixtures under `v1.0.0/` continue to exist and continue to be checked against HEAD — that's the whole point of the evolution check.
- **Why "harness" language is deliberately avoided.** Earlier drafts called this a "schema-evolution harness," which implied a separate validation engine. It is not. CUE does the validation; the loop is iteration + error formatting. M-PACK-A-02a's author implements the loop (~20 lines) and the fixture-library directory layout; no new tooling is built.

## Technical direction

1. **CUE as the source of truth for manifest, plan, surfaces, and execution spec.** YAML/JSON are on-the-wire representations; CUE is the authoritative schema. `cue vet` is the validation boundary.
2. **ADRs cite both Radar and admin-pack** wherever the contract touches pack-level concerns. Contracts derived from Radar alone are explicitly flagged as one-pack abstractions and require secondary review.
3. **The schema-evolution discipline is set here, not later.** Every CUE schema file carries a `schema_version`. Breaking changes bump major version + add deprecation ADR. Additive changes stay compatible by CUE unification. The compat check (specified under "Schema-evolution check — specification" above) runs locally + on pre-commit on every commit touching a `.cue` file or a fixture, and picks up CI enforcement when the CI pipeline lands.
4. **Reference implementations are named at ADR-writing time**, either **existing** or **scheduled-to-exist in a specific named milestone**. TBD is not acceptable; "something demo-ish later" is not acceptable; "`examples/file_watch_demo` built in M-PACK-C-03" is acceptable. The distinction the rule protects: **ADRs citing vaporware** — implementations that may never materialize or may materialize differently than the ADR envisions — are too abstract. ADRs citing a scheduled reference with a named owning milestone, a defined shape bindable to the ADR, and a matching acceptance criterion in that milestone are **not** too abstract — they have an owner, a deadline, and a specification-to-implementation binding. Examples of acceptable scheduled references in E-21: `examples/file_watch_demo` (E-21c M-PACK-C-03; ADR-FILEWATCH-01's primary ref); the admin-pack-shape proxy pack (E-21b M-PACK-B-01b load + M-PACK-B-03 execute; secondary validator for multi-trigger + multi-plan ADRs); Radar generated `pack.yaml` shim (E-21b M-PACK-B-01b; validator of ADR-MANIFEST-01's CUE schema against Radar's real shape). Reviewer rubric: for a scheduled reference, (a) is the owning milestone named specifically (not just "E-21c")? (b) is there a matching acceptance criterion in that milestone spec binding the reference's shape to the ADR? (c) is the reference's shape concrete (described, not gestured at)? If any answer is no, the reference is still too abstract and the ADR is rejected.
5. **Pack repo layout (ADR-LAYOUT-01)** prescribes conventional paths but allows deviation if manifest entrypoints resolve. The scaffolder (E-21c) produces the conventional layout; non-conventional packs are supported but not blessed.

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| The full ADR set is a lot to merge sequentially | Low | Split across three clustered milestones (M-PACK-A-02a foundational, M-PACK-A-02b running-systems, M-PACK-A-02c governance). **Partial parallelism**: once 02a's foundations freeze, five of 02c's eight ADRs (ADR-EXECUTOR-01, ADR-EVOLUTION-01, ADR-BOUNDARY-01, ADR-CONTENT-01, ADR-LA-01) can run in parallel with 02b; the other three (ADR-REGISTRY-01, ADR-MULTIPLAN-01, ADR-LAYOUT-01) wait for 02b to freeze because they bind to 02b's trigger / surface / declarable-config shapes. See M-PACK-A-02c row for the dependency rationale. No one milestone carries more than eight ADRs. |
| ADRs pushed to close the sub-epic before admin-pack's needs are honestly reflected (admin-pack as forcing function is **time-displaced** — it runs in E-22, after E-21 wraps) | High | Defense in depth: (1) anchored-citation success criterion above — every pack-level ADR's admin-pack citation is a specific file + section anchor inside `admin-pack/v2/docs/architecture/`, reviewer follows each citation to the cited section and judges substance. (2) E-21b's admin-pack-shape proxy pack — three plan entrypoints, mixed triggers, pack-instance state, declared secrets — loads in M-PACK-B-01b (manifest-shape validation) and executes end-to-end in M-PACK-B-03 (dispatch validation, the forcing-function capstone). At least one live second pack exercises the contract's pressure shape during E-21b itself, not just at E-22. See the "Admin-pack-shape proxy" notes in E-21b's success criteria (split across B-01b loaded / B-03 executed). |
| CUE toolchain learning curve slows ADR authoring | Low | M-PACK-A-01 ships the `design-contract` skill that embodies the workflow; authors follow the skill's checklist rather than re-deriving. |
| Pre-commit bypass (`--no-verify`) lets invalid CUE land on a branch before CI exists to catch it | Med | Interim control: reviewer checklist in the `design-contract` skill requires a clean `cue vet` + schema-evolution run on the branch before approving any PR touching `.cue` files. Named removal: when the CI pipeline is stood up and runs the same checks unbypassable, this reviewer duty drops back to normal spot-checking. Drift risk between local and CI is eliminated by construction because both sides read the same tool-versions pin. |
| Schema-evolution test fails on historical fixtures | Low | Fixtures written during E-21a start as the historical baseline; every schema change runs the test. No prior fixtures exist to be incompatible with at M-PACK-A-02 landing time. |
| ADR scope creeps into runtime design | Med | ADR template includes a "non-implementation" reminder: ADRs specify shape, not runtime behaviour. PackLoader design is E-21b; ADRs cannot prescribe its internals. |

## Dependencies

- **E-19 must merge before M-PACK-A-01 starts.** ADR-OPSPEC-01 codifies the warning/degraded-outcome contract; it cannot land before E-19 finalizes that contract.
- **M-TRUTH-01 must be referenced** — ADR-OPSPEC-01 is the CUE codification of M-TRUTH-01's ExecutionSpec.

## What downstream sub-epics get from E-21a

- **E-21b** (runtime) inherits: ADR-MANIFEST-01, ADR-PLAN-01, ADR-WIRE-01, ADR-REPLAY-01, ADR-TRIGGER-01, ADR-FILEWATCH-01, ADR-FSSCOPE-01, ADR-SECRETS-01, ADR-EXECUTOR-01, ADR-REGISTRY-01, ADR-SURFACE-01, ADR-MULTIPLAN-01, **ADR-EVOLUTION-01** (PackLoader's compat-check algorithm). These constrain PackLoader, TriggerManager, SurfaceRenderer, SecretSource, the runtime's replay walker, etc.
- **E-21c** (DX) inherits: ADR-MANIFEST-01, ADR-PLAN-01, ADR-OPSPEC-01, ADR-WIRE-01, ADR-SURFACE-01, ADR-LAYOUT-01, ADR-CONTENT-01. These constrain the Python SDK shape, widget catalog, scaffolder output.
- **E-21d** (extraction) inherits: ADR-LAYOUT-01, ADR-BOUNDARY-01, ADR-REGISTRY-01, plus effectively all others (Radar's extracted form must be a valid pack per every schema).

## References

- Parent epic: `work/epics/E-21-pack-contribution-contract/epic.md`
- M-TRUTH-01 spec: `work/done/E-20-execution-truth/M-TRUTH-01-execution-spec-outcome-design.md`
- E-19: `work/epics/E-19-warnings-degraded-outcomes/epic.md`
- Admin-pack architecture: `admin-pack/v2/docs/architecture/bookkeeping-pack-on-liminara.md`, `repo-layout.md`
- CUE documentation: https://cuelang.org/
