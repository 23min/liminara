---
id: E-26
parent: E-21
phase: 5c
status: planning
depends_on: E-24
---

# E-26: Pack Developer Experience

## Goal

Ship everything an external pack author installs and uses. When E-26 is done, a developer who knows Python and has never seen Liminara's source can run `pipx run liminara-new-pack my-pack`, edit the scaffolded files, run `liminara-test-harness run -- pytest`, and watch their pack execute against a local Liminara runtime — without cloning Liminara.

Concretely this sub-epic produces:
- **`liminara-pack-sdk`** on PyPI — the primary SDK.
- **`liminara_pack_sdk`** on Hex — small optional sugar for Elixir-authored packs.
- **`liminara_widgets`** — the generic A2UI widget library (Elixir Catalog + JS bundle) with **five MVP widgets**: `data_grid`, `json_viewer`, `dag_map` embedder, `content_card`, `banner`. Each ships with a working demo, none referencing Liminara domain types. Every widget is named-consumer justified (see `liminara_widgets` scope bullet below). `pdf_viewer` and `timeline` remain deferred until a named consumer demands them — see the parent epic's "Explicitly deferred" table.
- **`liminara-new-pack`** — pipx-installable scaffolder that emits a conventional pack repo layout per ADR-LAYOUT-01.
- **`liminara-test-harness`** — pipx-installable CLI that boots a local Liminara runtime with a local pack mounted from an arbitrary path. Supports `run` (drive integration tests) and `dev` (launch UI for interactive debugging).
- **`LiminaraTest.Harness` + `A2UICapture`** — Elixir-side test helpers used by the runtime's own tests and by pack-repo in-tree Elixir tests (for mixed-language packs).
- **`e2e-harness` skill** — documents the Playwright-based full-stack test pattern for pack authors.
- **`examples/file_watch_demo`** — a pure-Python pack that exercises `:file_watch` end-to-end, serving as:
  - the reference implementation for `:file_watch` (since Radar uses `:cron`),
  - a live regression test that the DX works for a minimal pack,
  - documentation-by-example for the pack authoring guide.

What does NOT land in E-26: runtime internals (E-25), Radar extraction (E-27), admin-pack itself (E-22).

## Context

E-24 gives us the contract; E-25 gives us a runtime that can load it. E-26 is the half that determines whether *external* pack authors can actually build against the contract in reasonable time. It is the measure of whether the language-agnostic, data-first framing pays off in practice.

The sub-epic is organized around the audience: a pack author in their own GitHub repo on their own laptop. Every deliverable is "what they install" or "what the scaffolder produces" or "what the harness lets them do." Liminara's own committers do not need most of this for day-to-day work; the SDK and tooling exist to let non-committers build packs.

## Scope

### In scope

- **`liminara-pack-sdk` (Python, PyPI-shape)**: op runner protocol client (speaks the wire protocol from ADR-WIRE-01), typed artifact helpers, plan builder DSL, content-type helpers (namespace construction + validation), `test` submodule with fake `ExecutionContext`, `run_op` helper, `assert_decision`, `assert_warning` matchers, `tmp_pack_instance` fixture. Versioned independently of the Liminara runtime; follows semver.
- **`liminara_pack_sdk` (Elixir, Hex-shape)**: `use LiminaraPackSdk.Plan` for ergonomic plan-building in Elixir; `ok/1`, `ok_with_warnings/2`, `error/1` result sugar; `LiminaraPackSdk.Test` with fake context + assertions. **Deliberately small.** Optional for packs that choose to author plans/ops in Elixir. Packs can equivalently use `@behaviour Liminara.Pack.API.Op` + hand-written callbacks.
- **`liminara_widgets` (Elixir Catalog + JS renderer bundle)**: generic A2UI custom components. Each widget ships with a working demo surface and no reference to Liminara domain types (Artifact, Run, Decision). Scope rule enforced by Credo + review. Every widget in the MVP set is justified by at least two named consumers — no widget earns its place on Radar alone (the one-pack-abstraction hazard the parent epic is designed to avoid). **MVP widgets (5):**
  - `data_grid` — tabular data with declarative columns. Named consumers: Radar briefings list, Radar sources list, admin-pack period ledger.
  - `json_viewer` — structured-data inspection. Named consumers: run detail inspectors, admin-pack transaction drill-down.
  - `dag_map` embedder — graph visualization via the `dag_map` submodule. Named consumers: Radar DAG, admin-pack intake-to-posting DAG, every pack's plan DAG.
  - `content_card` — narrative content container: title, optional summary/body (markdown or rich-text shape specified by ADR-SURFACE-01), optional list of items with per-item links. Named consumers: Radar per-cluster briefing cards, admin-pack receipt summaries, VSME narrative report sections.
  - `banner` — alert/notice with severity level, title, optional count, optional list of notes, optional collapsible detail. Named consumers: Radar degraded-briefing banner (from M-WARN-03), admin-pack dunning alerts, runtime degraded-outcome surfacing from E-19's warning contract.
  
  **Explicitly NOT in the MVP catalog (CSS primitives / layout, not widgets):**
  - `status_pill` — inline-styled status indicator. Why not a widget: `data_grid` columns style values as pills via declarative props; promoting to a widget is over-engineering. If a named second consumer emerges that can't use a `data_grid` column, revisit.
  - `definition_list` — key/value metadata block. Why not a widget: `data_grid` with two columns covers this semantically; stretching is cheaper than a new widget.
  - `collapsible_section` — `<details>`-style wrapper. Why not a widget: wrapping is an ADR-SURFACE-01 layout primitive (composition), not a content widget.
  
  `pdf_viewer` and `timeline` remain deferred per the parent epic's "Explicitly deferred" table; added when a named consumer demands them.
- **`liminara-new-pack` (Python CLI, pipx-installable)**: scaffolds a pack repo conforming to ADR-LAYOUT-01. Emits `pack.yaml`, `pyproject.toml`, `src/<pack_name>/ops/`, `src/<pack_name>/plan.py`, `surfaces/dashboard.yaml`, `tests/`, `fixtures/`, `README.md`. Runs `liminara-test-harness run` successfully out of the box. Templates live in the CLI package's own `data/` directory, not in a runtime dep.
- **`liminara-test-harness` (Python CLI, pipx-installable)**: boots a local Liminara runtime from a pinned, cross-platform native binary (see "Harness deployment model" below) with a pack from the current working directory mounted. Two modes: `run -- <command>` (spin up runtime, run command against it, tear down) for CI and scripted tests; `dev` (spin up runtime + web UI, browser opens, interactive) for manual debugging. Supports `trigger --input '<json>'` for manually firing a plan.
- **`LiminaraTest.Harness` + `A2UICapture` (Elixir)**: test helpers that runtime tests and mixed-language pack tests use. `LiminaraTest.Harness` starts a Liminara supervision tree in a test process with a configured pack; `A2UICapture` attaches to the A2UI socket and records wire messages for assertion. Used by the `e2e-harness` skill's reference scenario.
- **`e2e-harness` skill**: documents the Playwright-based full-stack test pattern. Skill checklist: spin runtime + pack via `liminara-test-harness`, drive with Playwright, assert on A2UI surface state, tear down. Reference scenario works end-to-end.
- **`examples/file_watch_demo`**: pure-Python pack in Liminara's repo at `examples/file_watch_demo/`. One op (emit an artifact per dropped file), one surface (show processed files in a `data_grid`), declared `:file_watch` trigger. Integration test runs under the harness and asserts end-to-end behaviour. Part of CI.

### Out of scope

- Runtime pack-loader / registry / surface renderer / trigger manager / secret source — E-25.
- Moving Radar to a submodule — E-27.
- Admin-pack — E-22.
- Additional SDK languages (Rust, Go, Java, TypeScript) — demand-driven.
- Additional widgets beyond the MVP five (including deferred `pdf_viewer` and `timeline`) — demand-driven.
- A published pack marketplace or registry — out of scope indefinitely.
- Pack-shipped custom JS bundle examples — the runtime supports them (E-25 honors the manifest reference); an example bundle can be deferred.
- **Production deployment packaging.** E-26 decides only the *pack-development* (DX) distribution model for the harness. How Liminara is packaged for production deployment (Docker image, `mix release` under systemd, cloud-provider-specific images, etc.) is a separate concern owned by later platform-generalization work (Phase 7 / E-14 territory) and is explicitly not prejudiced by the DX choice. An external pack author never touches Docker; a production operator's packaging story is decided when production deployments actually matter.

## Harness deployment model

`liminara-test-harness` boots a local Liminara runtime from a **pinned, cross-platform native binary** — a `mix release` of the three runtime apps (`liminara_core`, `liminara_observation`, `liminara_web`) wrapped with [`burrito`](https://github.com/burrito-elixir/burrito) so the release extracts and execs on first run without any external BEAM install. Docker is not a harness prerequisite.

**What the binary contains:**
- Erlang/OTP runtime (erts) + Elixir + OTP stdlib
- `liminara_core`, `liminara_observation`, `liminara_web` compiled
- Runtime Elixir deps (`bandit`, `websock`, `phoenix`, `phoenix_live_view`, `plug`, `jason`, `telemetry`, `ex_a2ui`, `boundary`, etc.)
- Phoenix static assets pre-built (`priv/static/assets/`)
- `vm.args`, `runtime.exs`, release config
- (Post-E-27: `liminara_radar` is **not** in the binary — Radar is an external pack loaded via manifest, not a compiled-in app.)

**What the binary does NOT contain (and why that's fine):**
- No Python interpreter or pack-level Python deps. The harness delegates Python-op execution to `uv` in the pack author's own environment — the harness invokes `uv run python -m liminara_op_runner ...` against the pack's `pyproject.toml` + `uv.lock`. This matches how pack authors already work, avoids shipping a Python interpreter that would conflict with pack-required versions, and keeps the Liminara binary small.
- No Docker. The `:file_watch` trigger uses native OS notify APIs; `dev` mode serves A2UI over a native socket.

**Platform support:**
- **Tier 1 (shipped and tested in CI):** macOS (x86_64 + arm64), Linux (x86_64 + arm64).
- **Tier 2 (supported via WSL2):** Windows — WSL2 uses the Linux binary. Native-Windows is deferred until demand justifies the burrito-for-Windows exercise.

**CI publication:** on every runtime tag, a GitHub Actions workflow cross-compiles the four Tier-1 targets via burrito, attaches the artifacts to the GitHub release with SHA-256 checksums in the release notes. The harness downloads the binary matching the current platform on first `run`/`dev` invocation, verifies the checksum against a hash embedded in the harness version, and caches under `$XDG_CACHE_HOME/liminara-runtime/<version>/` (or OS-appropriate equivalent).

**First-run flow (authoritative):**
```
pipx install liminara-new-pack liminara-test-harness uv
liminara-new-pack my-pack
cd my-pack
liminara-test-harness run -- pytest
  → harness notices runtime binary not cached
  → downloads liminara-runtime-vX.Y.Z-<platform>.tar.gz from GitHub releases
  → verifies SHA-256
  → extracts to $XDG_CACHE_HOME/liminara-runtime/vX.Y.Z/
  → boots the runtime, mounts ./pack.yaml, runs pytest against it
  → tears down
# subsequent runs — binary already cached, ~1–2s startup
```

**Explicit non-prescription:** whether to use burrito or an equivalent mechanism (bakeware, plain `mix release` + custom launcher) is a micro-implementation choice that M-DX-03 finalizes at implementation time. The *contract* is "single platform-native binary, no external BEAM install, cross-platform from CI."

## Constraints

Shared E-21 constraints apply. Sub-epic-specific:

- **`liminara_widgets` ships zero Liminara domain types.** Widgets accept A2UI-standard props + declared data bindings. No `%Run{}`, no `%Artifact{}`, no `%Decision{}` in widget signatures. This is the scope (i) discipline from the parent epic.
- **Scaffolder output must run.** `liminara-new-pack my-pack && cd my-pack && liminara-test-harness run -- pytest` is green at the end of E-26. If that command fails at any point, a milestone is blocked.
- **Python SDK does not import `anthropic`, `openai`, or LLM-provider SDKs.** The SDK is orchestration + contract plumbing; LLM calls happen inside pack ops. This keeps the SDK dependency-light and multi-purpose.
- **The Elixir SDK is small.** If `liminara_pack_sdk` (Elixir) grows beyond a few hundred lines of meaningful code, something is wrong — packs don't need it; it's sugar. Resist scope creep.
- **Harness startup is fast — measured, not aspirational.** Startup is split into three regimes, each with its own discipline. Budgets are *calibrated from the baseline measured at M-DX-03*, not hard-coded at plan time, because the binary shape doesn't exist yet to measure.
  - **Warm startup** (binary already cached, OS file cache warm — the inner dev loop): the M-DX-03 benchmark measures this on CI hardware at milestone start; the budget is set at **baseline × 1.2** and becomes an enforced CI threshold. Rough prior from today's `mix release`-projected measurements: expect 1.5–3s on a developer laptop. If the baseline is >3s, M-DX-03 optimizes (or escalates a documented renegotiation) before locking the budget.
  - **Cold startup** (binary cached, but cold OS file cache — fresh machine boot): separate benchmark; budget at **warm-baseline × 2** as headroom. Same CI threshold enforcement.
  - **First-run initialization** (binary not yet cached — download + SHA-256 verify + burrito extract + warm boot): network-dominated; **no numeric budget**. The harness instead prints a visible `Downloading Liminara runtime vX.Y.Z (~NN MB)…` progress line so the user understands the wait. CI does not benchmark this regime.

  Slow harness = slow test loop = developer pain, but the protection is a CI gate on real numbers, not a prose wish.

## Success criteria

- [ ] `liminara-pack-sdk` (Python) published to a test index and importable; its test suite passes; a minimal op file written against it runs end-to-end via the harness.
- [ ] `liminara_pack_sdk` (Elixir) published to a test Hex index; an Elixir pack authored with it runs end-to-end; the sugar is documented with hand-written-callback equivalents in the README.
- [ ] `liminara_widgets` builds as an Elixir library + JS bundle; each of the five MVP widgets (`data_grid`, `json_viewer`, `dag_map` embedder, `content_card`, `banner`) has a working demo surface; none reference Liminara domain types (verified by Credo + JS lint). **Deployment shape: in-tree umbrella app for MVP** (`runtime/apps/liminara_widgets/` or equivalent). Not published to Hex. Extraction to a standalone submodule + Hex release is explicitly deferred — named extraction triggers in `work/gaps.md` → "`liminara_widgets` extraction — in-tree for E-26; extract when a second consumer arrives". Name chosen (`liminara_widgets` not `liminara_ui`) is honest about being a widget library and doesn't mislead readers into expecting Liminara-domain-type-aware components.
- [ ] `liminara-new-pack` installs via `pipx` and scaffolds a pack that passes `liminara-test-harness run -- pytest` immediately.
- [ ] `liminara-test-harness` installs via `pipx`; `run` mode drives a pack's integration test and returns a proper exit code; `dev` mode opens a browser on a pack's surfaces.
- [ ] **Startup benchmark landed first in M-DX-03** (before binary-size optimization or DX polish). Command: `liminara-test-harness run --benchmark -- true` boots the runtime, waits for the "ready" signal, and reports elapsed milliseconds for each regime (warm, cold) in machine-parseable form. The **measured warm baseline on CI hardware is recorded in the milestone tracking doc**, and the enforced CI threshold for warm startup is set at `warm_baseline_ms × 1.2`; the enforced threshold for cold startup is set at `warm_baseline_ms × 2`. CI fails the job if either regime regresses past its threshold. If the measured warm baseline exceeds 3s, M-DX-03 either optimizes before locking the budget or escalates a documented renegotiation with rationale (tracked in `work/decisions.md`).
- [ ] **First-run initialization UX.** When the runtime binary is not cached, the harness prints a visible `Downloading Liminara runtime vX.Y.Z (~NN MB)…` progress line before boot, and cleanly exits with a helpful error (not a stack trace) on checksum or network failure. No numeric budget applies to this regime; the test covers the UX contract only.
- [ ] `examples/file_watch_demo` in-tree, passes CI, is referenced from the pack authoring guide as the canonical `:file_watch` reference. **Binding to ADR-FILEWATCH-01**: the demo exercises every semantic the ADR specifies (debounce, coalesce, scan-on-startup, dedup, in-memory queue, rescan-on-restart) with a named test per semantic. This satisfies E-24's reference-implementation rule for scheduled references (per E-24 Technical direction 4): the ADR cites this demo as its primary reference; this milestone is the named owning milestone; the acceptance criterion here binds the reference's shape to the ADR's semantics. If the demo ships missing any ADR-specified semantic, M-DX-03 is not complete.
- [ ] `LiminaraTest.Harness` + `A2UICapture` land in `liminara_core/test/support/` (or a dedicated test-helpers app if scope warrants) and are used by at least one runtime test + one pack test.
- [ ] `e2e-harness` skill documented at `.ai-repo/skills/e2e-harness.md` (synced); reference scenario in `examples/file_watch_demo/tests/e2e/` exercises the full loop.
- [ ] Pack authoring guide draft at `docs/guides/pack-authoring.md` (finalized in E-27) walks from zero to a running pack in under one page of commands, in Python.

## Milestones

| ID | Title | Summary |
|---|---|---|
| **M-DX-01** | Python SDK + Elixir sugar | `liminara-pack-sdk` (Python) + `liminara_pack_sdk` (Elixir) shipped. Includes wire-protocol client, artifact helpers, plan builder, content-type helpers, test submodule with fake context + assertions. Both published to test indices. |
| **M-DX-02** | `liminara_widgets` widgets + Elixir test harness | `liminara_widgets` Elixir Catalog + JS bundle with the five MVP widgets (`data_grid`, `json_viewer`, `dag_map` embedder, `content_card`, `banner`); each has a working demo and two-named-consumer justification (see scope). `LiminaraTest.Harness` + `A2UICapture` land. `e2e-harness` skill documented with a reference scenario. |
| **M-DX-03** | Scaffolder + test harness CLI + file_watch demo | `liminara-new-pack` and `liminara-test-harness` CLIs, both pipx-installable. **Liminara CI publishes cross-platform runtime binaries (macOS x86_64/arm64, Linux x86_64/arm64) on runtime tags; harness downloads, checksum-verifies, and caches on first run.** `examples/file_watch_demo` pure-Python pack lands + passes CI (invokes pack Python via `uv`). The scaffolder-to-harness-to-passing-test loop is validated end-to-end. |

## Technical direction

1. **Python SDK is the primary SDK.** It is what most pack authors install. Every ergonomic choice is made with Python-first users in mind; other languages get equivalent ergonomics later via their own SDKs.
2. **Elixir SDK is optional sugar.** Its purpose is to make Radar-style mixed-language packs pleasant, not to be required. `@behaviour Liminara.Pack.API.Op` + hand-written callbacks is always a valid alternative.
3. **Widgets are declarative-binding-friendly.** Each widget exposes props that can be populated from ADR-SURFACE-01 data bindings (run IDs, artifact hashes, pack-instance-path queries). No runtime object graphs passed in. This keeps widgets portable outside Liminara.
4. **Harness is a standalone deployable, not a library.** `liminara-test-harness` fetches a pinned Liminara runtime binary on first use (see "Harness deployment model") so pack authors never `git clone liminara`. Updating the harness (and the pinned runtime version it references) is how pack authors get newer runtimes.
5. **Scaffolder is opinionated.** It emits the conventional layout from ADR-LAYOUT-01 verbatim. Pack authors who want non-conventional layouts hand-edit; no flags to configure layout.
6. **File-watch demo is the canonical reference pack.** Small enough to read in one sitting; exercises manifest, plan, op, trigger, surface, FS-scope, and content-type helpers. Referenced by the pack authoring guide and by every pack-level ADR as the "see it working" citation.

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Python SDK API drifts from wire protocol as ergonomic features accumulate | High | Every Python SDK public function maps to a wire-protocol operation from ADR-WIRE-01. Code review enforces: "if this ergonomic cannot be expressed in the wire protocol, it does not belong in the SDK." |
| `liminara_widgets` widgets end up coupled to Liminara types (e.g., event-log-specific data shapes) | Med | Scope rule in Constraints; Credo + JS lint; reviewer wrap check. Widgets accept generic shapes; bindings are the Liminara-specific layer. |
| Harness boot latency regresses past the budget, killing dev-loop feel | Med | Native binary (no container boundary) + warm cache after first download keeps startup dominated by BEAM cold-start. The startup budget is **measured, not guessed**: M-DX-03 lands a `--benchmark` mode that records warm/cold regimes on CI hardware, and the enforced thresholds are `warm_baseline × 1.2` / `warm_baseline × 2` (see Constraints → "Harness startup is fast"). CI fails on regression. If the initial baseline is unacceptably slow (>3s warm), M-DX-03 either optimizes or escalates a documented renegotiation rather than silently shipping a slow harness. |
| Cross-compilation of the runtime binary from CI fails on a dep that pulls in a platform-specific NIF | Med | Audit deps at M-DX-03 scope-lock; the current dep set (bandit, websock, phoenix, phoenix_live_view, plug, jason, telemetry, ex_a2ui, boundary) is pure Elixir. If a future dep adds a NIF, either pin a burrito-compatible variant or surface the constraint in `work/gaps.md`. |
| Scaffolder templates drift from the schema (schema moves; scaffolder emits old shape) | Med | Scaffolder output is part of CI: scaffold a pack, `cue vet` its `pack.yaml`, run the harness. Drift fails CI. |
| `liminara-test-harness` needing admin (root) to mount things breaks on locked-down developer laptops | Low | No elevated-privilege requirements. File-watching uses OS notify APIs accessible without root. Tested on macOS, Linux, WSL. |
| Python SDK and Elixir SDK fall out of sync on shared concepts (content-type strings, plan shape) | Med | Both SDKs consume the CUE schemas from E-24 for their fixtures and type derivations. A "drift test" in CI re-generates type stubs from CUE and checks for divergence. |
| The Elixir SDK grows too large because Radar benefits from more sugar | Med | Explicit LoC ceiling in the sub-epic: if the SDK passes ~500 lines of hand-written code, reviewer escalates. Radar-specific helpers belong in the radar-pack repo, not in the generic SDK. |

## Dependencies

- **E-24 must merge first.** Every SDK public surface is constrained by an E-24 ADR + CUE schema; the scaffolder emits layouts from ADR-LAYOUT-01; the widget catalog binds via ADR-SURFACE-01.
- **E-25 does not have to be fully merged** before E-26 starts, as long as the wire protocol from E-24 is stable. In practice M-DX-01 can run concurrent with M-RUNTIME-01 / B-01b / B-02 / B-03 once the wire protocol ADRs are frozen. M-DX-02 and M-DX-03 need E-25's runtime available to validate against (at least M-RUNTIME-02, so that PackLoader + PackRegistry + Radar-through-pipeline are green).
- **No dependency on E-27.** Radar extraction happens after; E-26 validates against the `file_watch_demo` pack, not Radar.

## Hand-off to E-27

E-27 uses E-26's outputs:
- Radar's extracted form will use `liminara_pack_sdk` (Elixir) for plan ergonomics.
- Radar's Python ops continue to use the same protocol; `liminara-pack-sdk` (Python) is available but Radar's existing op code doesn't require it.
- Radar's surfaces become YAML declarations rendered by `liminara_widgets` widgets (the MVP five cover Radar's needs, per the widget-catalog gap analysis; `content_card` is the critical one for briefing content, `dag_map` for plan visualization, `banner` for degraded alerts).
- Radar's tests use `LiminaraTest.Harness` + `A2UICapture`.
- The pack authoring guide (drafted here, finalized in E-27) cites Radar as a "mixed-language advanced pack" alongside `file_watch_demo` as the "pure-Python simple pack."

## References

- Parent epic: `work/epics/E-21-pack-contribution-contract/epic.md`
- E-24 (prerequisite): `work/epics/E-21-pack-contribution-contract/E-24-contract-design.md`
- E-25 (parallel): `work/epics/E-21-pack-contribution-contract/E-25-runtime-pack-infrastructure.md`
- Port wire protocol (current): `runtime/apps/liminara_core/lib/liminara/executor/port.ex`
- Current Python op runner: `runtime/python/src/liminara_op_runner.py`
- Admin-pack architecture (consumers of this SDK in E-22): `admin-pack/v2/docs/architecture/bookkeeping-pack-on-liminara.md`
