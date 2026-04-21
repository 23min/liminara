---
id: E-21c-pack-dx
parent: E-21-pack-contribution-contract
phase: 5c
status: planning
depends_on: E-21a-contract-design
---

# E-21c: Pack Developer Experience

## Goal

Ship everything an external pack author installs and uses. When E-21c is done, a developer who knows Python and has never seen Liminara's source can run `pipx run liminara-new-pack my-pack`, edit the scaffolded files, run `liminara-test-harness run -- pytest`, and watch their pack execute against a local Liminara runtime — without cloning Liminara.

Concretely this sub-epic produces:
- **`liminara-pack-sdk`** on PyPI — the primary SDK.
- **`liminara_pack_sdk`** on Hex — small optional sugar for Elixir-authored packs.
- **`liminara_ui`** — the generic A2UI widget library (Elixir Catalog + JS bundle) with `data_grid`, `json_viewer`, and `dag_map` embedder, each with a working demo, none referencing Liminara domain types. `pdf_viewer` and `timeline` are deferred until a named consumer (admin-pack receipts, process-mining pack) demands them — see the parent epic's "Explicitly deferred" table.
- **`liminara-new-pack`** — pipx-installable scaffolder that emits a conventional pack repo layout per ADR-LAYOUT-01.
- **`liminara-test-harness`** — pipx-installable CLI that boots a local Liminara runtime with a local pack mounted from an arbitrary path. Supports `run` (drive integration tests) and `dev` (launch UI for interactive debugging).
- **`LiminaraTest.Harness` + `A2UICapture`** — Elixir-side test helpers used by the runtime's own tests and by pack-repo in-tree Elixir tests (for mixed-language packs).
- **`e2e-harness` skill** — documents the Playwright-based full-stack test pattern for pack authors.
- **`examples/file_watch_demo`** — a pure-Python pack that exercises `:file_watch` end-to-end, serving as:
  - the reference implementation for `:file_watch` (since Radar uses `:cron`),
  - a live regression test that the DX works for a minimal pack,
  - documentation-by-example for the pack authoring guide.

What does NOT land in E-21c: runtime internals (E-21b), Radar extraction (E-21d), admin-pack itself (E-22).

## Context

E-21a gives us the contract; E-21b gives us a runtime that can load it. E-21c is the half that determines whether *external* pack authors can actually build against the contract in reasonable time. It is the measure of whether the language-agnostic, data-first framing pays off in practice.

The sub-epic is organized around the audience: a pack author in their own GitHub repo on their own laptop. Every deliverable is "what they install" or "what the scaffolder produces" or "what the harness lets them do." Liminara's own committers do not need most of this for day-to-day work; the SDK and tooling exist to let non-committers build packs.

## Scope

### In scope

- **`liminara-pack-sdk` (Python, PyPI-shape)**: op runner protocol client (speaks the wire protocol from ADR-WIRE-01), typed artifact helpers, plan builder DSL, content-type helpers (namespace construction + validation), `test` submodule with fake `ExecutionContext`, `run_op` helper, `assert_decision`, `assert_warning` matchers, `tmp_pack_instance` fixture. Versioned independently of the Liminara runtime; follows semver.
- **`liminara_pack_sdk` (Elixir, Hex-shape)**: `use LiminaraPackSdk.Plan` for ergonomic plan-building in Elixir; `ok/1`, `ok_with_warnings/2`, `error/1` result sugar; `LiminaraPackSdk.Test` with fake context + assertions. **Deliberately small.** Optional for packs that choose to author plans/ops in Elixir. Packs can equivalently use `@behaviour Liminara.Pack.API.Op` + hand-written callbacks.
- **`liminara_ui` (Elixir Catalog + JS renderer bundle)**: generic A2UI custom components. MVP widgets: `data_grid`, `json_viewer`, `dag_map` embedder. Each widget ships with a working demo surface and no reference to Liminara domain types (Artifact, Run, Decision). Scope rule enforced by Credo + review. `pdf_viewer` and `timeline` are deferred per the parent epic's "Explicitly deferred" table — they are added when a named consumer demands them.
- **`liminara-new-pack` (Python CLI, pipx-installable)**: scaffolds a pack repo conforming to ADR-LAYOUT-01. Emits `pack.yaml`, `pyproject.toml`, `src/<pack_name>/ops/`, `src/<pack_name>/plan.py`, `surfaces/dashboard.yaml`, `tests/`, `fixtures/`, `README.md`. Runs `liminara-test-harness run` successfully out of the box. Templates live in the CLI package's own `data/` directory, not in a runtime dep.
- **`liminara-test-harness` (Python CLI, pipx-installable)**: boots a local Liminara runtime — either by downloading a pinned release binary or via a Docker image — with a pack from the current working directory mounted. Two modes: `run -- <command>` (spin up runtime, run command against it, tear down) for CI and scripted tests; `dev` (spin up runtime + web UI, browser opens, interactive) for manual debugging. Supports `trigger --input '<json>'` for manually firing a plan.
- **`LiminaraTest.Harness` + `A2UICapture` (Elixir)**: test helpers that runtime tests and mixed-language pack tests use. `LiminaraTest.Harness` starts a Liminara supervision tree in a test process with a configured pack; `A2UICapture` attaches to the A2UI socket and records wire messages for assertion. Used by the `e2e-harness` skill's reference scenario.
- **`e2e-harness` skill**: documents the Playwright-based full-stack test pattern. Skill checklist: spin runtime + pack via `liminara-test-harness`, drive with Playwright, assert on A2UI surface state, tear down. Reference scenario works end-to-end.
- **`examples/file_watch_demo`**: pure-Python pack in Liminara's repo at `examples/file_watch_demo/`. One op (emit an artifact per dropped file), one surface (show processed files in a `data_grid`), declared `:file_watch` trigger. Integration test runs under the harness and asserts end-to-end behaviour. Part of CI.

### Out of scope

- Runtime pack-loader / registry / surface renderer / trigger manager / secret source — E-21b.
- Moving Radar to a submodule — E-21d.
- Admin-pack — E-22.
- Additional SDK languages (Rust, Go, Java, TypeScript) — demand-driven.
- Additional widgets beyond the MVP three (including deferred `pdf_viewer` and `timeline`) — demand-driven.
- A published pack marketplace or registry — out of scope indefinitely.
- Pack-shipped custom JS bundle examples — the runtime supports them (E-21b honors the manifest reference); an example bundle can be deferred.

## Constraints

Shared E-21 constraints apply. Sub-epic-specific:

- **`liminara_ui` ships zero Liminara domain types.** Widgets accept A2UI-standard props + declared data bindings. No `%Run{}`, no `%Artifact{}`, no `%Decision{}` in widget signatures. This is the scope (i) discipline from the parent epic.
- **Scaffolder output must run.** `liminara-new-pack my-pack && cd my-pack && liminara-test-harness run -- pytest` is green at the end of E-21c. If that command fails at any point, a milestone is blocked.
- **Python SDK does not import `anthropic`, `openai`, or LLM-provider SDKs.** The SDK is orchestration + contract plumbing; LLM calls happen inside pack ops. This keeps the SDK dependency-light and multi-purpose.
- **The Elixir SDK is small.** If `liminara_pack_sdk` (Elixir) grows beyond a few hundred lines of meaningful code, something is wrong — packs don't need it; it's sugar. Resist scope creep.
- **Harness startup is fast.** `liminara-test-harness run` latency (boot + pack load + ready for first trigger) under ~5 seconds on developer hardware. Slow harness = slow test loop = developer pain.

## Success criteria

- [ ] `liminara-pack-sdk` (Python) published to a test index and importable; its test suite passes; a minimal op file written against it runs end-to-end via the harness.
- [ ] `liminara_pack_sdk` (Elixir) published to a test Hex index; an Elixir pack authored with it runs end-to-end; the sugar is documented with hand-written-callback equivalents in the README.
- [ ] `liminara_ui` builds as an Elixir library + JS bundle; each of the three MVP widgets (`data_grid`, `json_viewer`, `dag_map` embedder) has a working demo surface; none reference Liminara domain types (verified by Credo + JS lint).
- [ ] `liminara-new-pack` installs via `pipx` and scaffolds a pack that passes `liminara-test-harness run -- pytest` immediately.
- [ ] `liminara-test-harness` installs via `pipx`; `run` mode drives a pack's integration test and returns a proper exit code; `dev` mode opens a browser on a pack's surfaces.
- [ ] `examples/file_watch_demo` in-tree, passes CI, is referenced from the pack authoring guide as the canonical `:file_watch` reference.
- [ ] `LiminaraTest.Harness` + `A2UICapture` land in `liminara_core/test/support/` (or a dedicated test-helpers app if scope warrants) and are used by at least one runtime test + one pack test.
- [ ] `e2e-harness` skill documented at `.ai-repo/skills/e2e-harness.md` (synced); reference scenario in `examples/file_watch_demo/tests/e2e/` exercises the full loop.
- [ ] Pack authoring guide draft at `docs/guides/pack-authoring.md` (finalized in E-21d) walks from zero to a running pack in under one page of commands, in Python.

## Milestones

| ID | Title | Summary |
|---|---|---|
| **M-PACK-C-01** | Python SDK + Elixir sugar | `liminara-pack-sdk` (Python) + `liminara_pack_sdk` (Elixir) shipped. Includes wire-protocol client, artifact helpers, plan builder, content-type helpers, test submodule with fake context + assertions. Both published to test indices. |
| **M-PACK-C-02** | `liminara_ui` widgets + Elixir test harness | `liminara_ui` Elixir Catalog + JS bundle with the three MVP widgets (`data_grid`, `json_viewer`, `dag_map` embedder); each has a working demo. `LiminaraTest.Harness` + `A2UICapture` land. `e2e-harness` skill documented with a reference scenario. |
| **M-PACK-C-03** | Scaffolder + test harness CLI + file_watch demo | `liminara-new-pack` and `liminara-test-harness` CLIs, both pipx-installable. `examples/file_watch_demo` pure-Python pack lands + passes CI. The scaffolder-to-harness-to-passing-test loop is validated end-to-end. |

## Technical direction

1. **Python SDK is the primary SDK.** It is what most pack authors install. Every ergonomic choice is made with Python-first users in mind; other languages get equivalent ergonomics later via their own SDKs.
2. **Elixir SDK is optional sugar.** Its purpose is to make Radar-style mixed-language packs pleasant, not to be required. `@behaviour Liminara.Pack.API.Op` + hand-written callbacks is always a valid alternative.
3. **Widgets are declarative-binding-friendly.** Each widget exposes props that can be populated from ADR-SURFACE-01 data bindings (run IDs, artifact hashes, pack-instance-path queries). No runtime object graphs passed in. This keeps widgets portable outside Liminara.
4. **Harness is a standalone deployable, not a library.** `liminara-test-harness` bundles a pinned Liminara runtime (via Docker image or bundled binary) so pack authors never `git clone liminara`. Updating the harness is how pack authors get newer runtimes.
5. **Scaffolder is opinionated.** It emits the conventional layout from ADR-LAYOUT-01 verbatim. Pack authors who want non-conventional layouts hand-edit; no flags to configure layout.
6. **File-watch demo is the canonical reference pack.** Small enough to read in one sitting; exercises manifest, plan, op, trigger, surface, FS-scope, and content-type helpers. Referenced by the pack authoring guide and by every pack-level ADR as the "see it working" citation.

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Python SDK API drifts from wire protocol as ergonomic features accumulate | High | Every Python SDK public function maps to a wire-protocol operation from ADR-WIRE-01. Code review enforces: "if this ergonomic cannot be expressed in the wire protocol, it does not belong in the SDK." |
| `liminara_ui` widgets end up coupled to Liminara types (e.g., event-log-specific data shapes) | Med | Scope rule in Constraints; Credo + JS lint; reviewer wrap check. Widgets accept generic shapes; bindings are the Liminara-specific layer. |
| Harness boot latency creeps past 5s, killing dev-loop feel | Med | Dockerized runtime image is prebuilt and pulled once; harness's `run` mode reuses it across invocations when possible. Boot-time measurement is part of CI. |
| Scaffolder templates drift from the schema (schema moves; scaffolder emits old shape) | Med | Scaffolder output is part of CI: scaffold a pack, `cue vet` its `pack.yaml`, run the harness. Drift fails CI. |
| `liminara-test-harness` needing admin (root) to mount things breaks on locked-down developer laptops | Low | No elevated-privilege requirements. File-watching uses OS notify APIs accessible without root. Tested on macOS, Linux, WSL. |
| Python SDK and Elixir SDK fall out of sync on shared concepts (content-type strings, plan shape) | Med | Both SDKs consume the CUE schemas from E-21a for their fixtures and type derivations. A "drift test" in CI re-generates type stubs from CUE and checks for divergence. |
| The Elixir SDK grows too large because Radar benefits from more sugar | Med | Explicit LoC ceiling in the sub-epic: if the SDK passes ~500 lines of hand-written code, reviewer escalates. Radar-specific helpers belong in the radar-pack repo, not in the generic SDK. |

## Dependencies

- **E-21a must merge first.** Every SDK public surface is constrained by an E-21a ADR + CUE schema; the scaffolder emits layouts from ADR-LAYOUT-01; the widget catalog binds via ADR-SURFACE-01.
- **E-21b does not have to be fully merged** before E-21c starts, as long as the wire protocol from E-21a is stable. In practice M-PACK-C-01 can run concurrent with M-PACK-B-01/02/03 once the wire protocol ADRs are frozen. M-PACK-C-02 and M-PACK-C-03 need E-21b's runtime available to validate against (at least M-PACK-B-01).
- **No dependency on E-21d.** Radar extraction happens after; E-21c validates against the `file_watch_demo` pack, not Radar.

## Hand-off to E-21d

E-21d uses E-21c's outputs:
- Radar's extracted form will use `liminara_pack_sdk` (Elixir) for plan ergonomics.
- Radar's Python ops continue to use the same protocol; `liminara-pack-sdk` (Python) is available but Radar's existing op code doesn't require it.
- Radar's surfaces become YAML declarations rendered by `liminara_ui` widgets (the MVP three cover Radar's needs; `dag_map` embedder is the critical one).
- Radar's tests use `LiminaraTest.Harness` + `A2UICapture`.
- The pack authoring guide (drafted here, finalized in E-21d) cites Radar as a "mixed-language advanced pack" alongside `file_watch_demo` as the "pure-Python simple pack."

## References

- Parent epic: `work/epics/E-21-pack-contribution-contract/epic.md`
- E-21a (prerequisite): `work/epics/E-21-pack-contribution-contract/E-21a-contract-design.md`
- E-21b (parallel): `work/epics/E-21-pack-contribution-contract/E-21b-runtime-pack-infrastructure.md`
- Port wire protocol (current): `runtime/apps/liminara_core/lib/liminara/executor/port.ex`
- Current Python op runner: `runtime/python/src/liminara_op_runner.py`
- Admin-pack architecture (consumers of this SDK in E-22): `admin-pack/v2/docs/architecture/bookkeeping-pack-on-liminara.md`
