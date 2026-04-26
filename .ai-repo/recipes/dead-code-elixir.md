---
name: elixir
fileExts: [.ex, .exs]
excludePaths:
  - runtime/_build/
  - runtime/deps/
  - runtime/cover/
  - runtime/apps/*/priv/static/
  - dag-map/
  - ex_a2ui/
  - proliminal.net/
  - admin-pack/
  - .scratch/
  - .ai-repo/scratch/
tool: exunused
toolCmd: "cd runtime && mix exunused > /tmp/exunused.out 2>&1; cat /tmp/exunused.out"
---

# Dead-code recipe: Elixir (ExUnused)

ExUnused is a hex package: `{:exunused, "~> 0.4", only: :dev, runtime: false}` in `runtime/mix.exs`. The audit's first run will produce a `tool-failed` section until that dep is added and `mix deps.get` has run.

## Things to look out for in this stack

OTP and Phoenix invoke many functions by name at runtime; they look unused to any static tool. The LLM should NOT mark these as confirmed-dead without grep-confirming no live caller:

- **GenServer callbacks** — `init/1`, `handle_call/3`, `handle_cast/2`, `handle_info/2`, `terminate/2`, `code_change/3`, `handle_continue/2`. Anything in a module with `use GenServer` or `@behaviour GenServer`.
- **Phoenix LiveView callbacks** — `mount/3`, `render/1`, `handle_event/3`, `handle_info/2`, `handle_params/3`, `update/2`.
- **`@impl true` functions** — declares a behaviour callback; ExUnused honors this when present, but a missing `@impl` annotation on a real callback gets flagged.
- **Pack op entrypoints** — functions registered via `pack.yaml` or returned from `plan/1` are runtime-resolved by string. Any function in a module under `runtime/apps/liminara_*/lib/.../packs/` or `runtime/apps/liminara_*/lib/.../ops/` is suspect for false-flagging.
- **Mix tasks** — `Mix.Tasks.*` modules are invoked by task name (`mix <name>`); never confirm-dead.
- **`apply/3` and `Application.get_env(:app, :module)` dispatch** — Liminara's executor taxonomy (`:inline` + `:port`) resolves modules from config; grep the change-set for `apply(`, `Module.concat(`, `Code.ensure_loaded?(` before flagging.
- **`__using__/1` and macros** — modules with `defmacro __using__` generate functions in callers; the macro itself or its helpers may look unused.
- **ExUnit setup helpers** — `setup/1`, `setup_all/1`, `on_exit/1`, fixture functions in test support files.
- **ex_a2ui WebSocket handlers** — provider callbacks consumed by the `ex_a2ui` submodule's runtime.

## Public surface notes

- **`liminara_core` public modules** — `Liminara.Pack`, `Liminara.Op`, `Liminara.Decision`, `Liminara.Run`, `Liminara.Artifact` and their public functions are the pack-author API. Treat as live unless cross-pack grep confirms no callers.
- **`liminara_observation` A2UI provider** — consumed by the `ex_a2ui` submodule. Public functions on the provider module are external surface.
- **Behaviours declared in core** — any module with `@callback` definitions defines a contract; the `@callback` declarations themselves may look unused (they're consumed by `@behaviour` and `@impl` clauses elsewhere).
- **Schema-derived code** — anything generated from `docs/schemas/*/schema.cue` (CUE → Elixir) is contract-bound; the live source is the schema, not the generated `.ex`.

## Tool-specific notes

- ExUnused's confidence levels: weight `:high` and `:medium` heavily; `:low` is noisy on OTP code.
- ExUnused respects `@impl true`; missing `@impl` on real callbacks is itself a finding (lint-grade, file as needs-judgement if the function name matches a known behaviour callback).
- Run from `runtime/` (the umbrella root), not the repo root. The composite `cd runtime && mix exunused` handles this.

## Blind-spot families to sweep manually

- **Orphan fixtures** — `.json`, `.yaml`, `.cue` fixtures under `docs/schemas/*/fixtures/` or `runtime/apps/*/test/support/fixtures/` with no test referencing them.
- **Stale ADRs** — `docs/decisions/NNNN-*.md` citing modules/functions absent from the change-set's HEAD tree.
- **Helpers retained "for stability"** — exported functions with zero callers and a comment indicating compat-only retention.
- **Schema fields with no consumers** — fields in `docs/schemas/*/schema.cue` with no producer or consumer in Elixir code.
- **Deprecated module aliases** — `defmodule` re-exports tolerated by the compiler but unused.
