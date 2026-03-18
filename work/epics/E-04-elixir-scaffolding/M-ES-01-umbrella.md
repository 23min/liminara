---
id: M-ES-01-umbrella
epic: E-04-elixir-scaffolding
status: done
---

# M-ES-01: Umbrella Project + Tooling

## Goal

Create a devcontainer providing the full development environment (Elixir, Python, Node), then create the Elixir umbrella project with `liminara_core` as the first app, configure all development tooling (Quokka, Credo, Dialyxir), and verify the full validation pipeline passes on a minimal codebase.

## Acceptance criteria

### Devcontainer (`.devcontainer/`)

A VS Code devcontainer providing the full development environment. No system-wide installs required.

**Dockerfile** (base: `hexpm/elixir` with Elixir 1.20+ / OTP 27+):

- [x] Elixir 1.18+ and OTP 27+ (from base image; upgrade to 1.20 when stable images ship with OTP 27)
- [x] Hex and Rebar pre-installed (`mix local.hex --force && mix local.rebar --force`)
- [x] Python 3.11+ (system package — Debian bookworm ships 3.11.2)
- [x] `uv` installed (Astral package manager — `integrations/python/` uses it)
- [x] Node.js LTS (for MCP tools: hexdocs-mcp, context7)
- [x] `git` installed (for devcontainer Git integration)

**devcontainer.json** (VS Code):

- [x] Workspace mounted at repo root (both `runtime/` and `integrations/python/` accessible)
- [x] `postCreateCommand` runs: `cd runtime && mix deps.get` and `cd integrations/python && uv sync`
- [x] VS Code extensions:
  - `jakebecker.elixir-ls` — Elixir language server (ElixirLS; switch to Expert when stable)
  - `ms-python.python` — Python language support
  - `charliermarsh.ruff` — Ruff linter/formatter for Python
  - `phoenixframework.phoenix` — Phoenix snippets (useful later, low cost now)
- [x] VS Code settings:
  - Elixir formatter on save
  - Python formatter set to Ruff
  - Ruff as Python linter

**Smoke tests** (verified manually after first build):

- [x] `elixir --version` shows 1.18+
- [x] `erl -eval 'io:format("~s~n", [erlang:system_info(otp_release)]), halt().' -noshell` shows 27+
- [x] `python3 --version` shows 3.11+ (Debian bookworm ships 3.11.2)
- [x] `uv --version` works
- [x] `node --version` works
- [x] `mix hex.info` works (Hex installed)
- [x] `mix local.rebar --force` works (Rebar installed)

### Umbrella structure

- [x] Umbrella project at repo root path `runtime/` (Elixir code lives here, separate from `integrations/python/`)
- [x] `runtime/apps/liminara_core/` app created with `mix new`
- [x] Root `mix.exs` targets Elixir `~> 1.18` and OTP 27+ (bump to `~> 1.20` when available)
- [x] `liminara_core/mix.exs` declares app dependencies

### Dependencies

- [x] `jason` `~> 1.4` — JSON encoding/decoding
- [x] `ex_doc` `~> 0.35` — documentation (dev only)
- [x] `credo` `~> 1.7` — linting (dev/test only)
- [x] `dialyxir` `~> 1.4` — type checking (dev/test only)
- [x] `quokka` `~> 2.12` — format plugin (dev/test only)
- [x] `mix deps.get` and `mix compile` succeed with zero warnings

### Formatter and linter config

- [x] Root `.formatter.exs` configures Quokka plugin with all rewrite categories enabled
- [x] Root `.credo.exs` disables the 28 checks that overlap with Quokka (see `docs/guides/elixir_tooling.md`)
- [x] `mix format --check-formatted` passes
- [x] `mix credo` passes with no issues

### Type checking

- [x] `mix dialyzer` passes (initial PLT build + zero warnings)

### Placeholder module and test

- [x] `LiminaraCore` module exists with a `@moduledoc` and a placeholder function (e.g., `version/0` returning the app version)
- [x] At least one test exists and passes via `mix test`

## Tests

This milestone is primarily about project scaffolding, so "tests" are really validation checks:

- `liminara_core_test.exs`:
  - `LiminaraCore.version/0` returns a version string matching SemVer format
  - Module compiles and is loadable

The real test of this milestone is the validation pipeline itself — all four commands must pass cleanly.

## TDD sequence

1. **Impl agent** builds the devcontainer (`Dockerfile` + `devcontainer.json`). Human reviews.
2. Human opens the repo in VS Code → "Reopen in Container". Verifies smoke tests.
3. All subsequent steps run inside the devcontainer (Claude Code terminal inside VS Code).
4. **Test agent** reads this spec, writes the placeholder test. Test fails (red) because the module doesn't exist.
5. Human reviews test.
6. **Impl agent** reads this spec + test, creates the umbrella project, configures tooling, implements `LiminaraCore` until the test passes (green).
7. Human reviews implementation.
8. Full validation pipeline: `mix format --check-formatted && mix credo && mix dialyzer && mix test`

## Out of scope

- Any runtime modules (Artifact, Event, Op, Run, Pack) — those are E-05+
- Phoenix or web dependencies
- Oban or Postgres
- Mix.exs metadata for Hex publishing (description, package, homepage)
- README (project-level concern, not scaffolding)

## Spec reference

- `docs/guides/elixir_tooling.md` — Elixir tooling: Quokka config, Credo overlaps, Dialyxir, validation pipeline, MCP tools
- `docs/guides/python_tooling.md` — Python tooling: uv, Ruff, ty, pytest, validation pipeline
- `docs/architecture/01_CORE.md` § OTP supervision tree (for app naming context)
