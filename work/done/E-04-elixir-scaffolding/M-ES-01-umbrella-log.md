# M-ES-01 Session Log

## 2026-03-18 — Devcontainer + Umbrella scaffolding

**Milestone:** M-ES-01-umbrella
**Outcome:** Done

### What was done

1. Devcontainer already existed from prior work — verified smoke tests pass (Elixir 1.18.4, OTP 27, Python 3.11.2, uv, Node 22, Hex, Rebar).
2. Created umbrella project at `runtime/` with `mix new runtime --umbrella`.
3. Created `apps/liminara_core/` with `mix new liminara_core`.
4. TDD: wrote failing test for `LiminaraCore.version/0` (red), then implemented (green).
5. Configured root `mix.exs` with deps: jason, ex_doc, credo, dialyxir, quokka.
6. Configured `.formatter.exs` with Quokka plugin (all rewrite categories).
7. Configured `.credo.exs` in strict mode, 28 Quokka-overlapping checks disabled, umbrella-aware paths.
8. Full validation pipeline passes: `mix format --check-formatted`, `mix credo`, `mix dialyzer`, `mix test`.

### Decisions

- **Python 3.11 vs 3.12**: Debian bookworm ships Python 3.11.2. Accepted as-is — sufficient for our needs. Noted in acceptance criteria.
- **Credo file paths**: Umbrella requires `apps/*/lib/` and `apps/*/test/` in the Credo config `included` paths, not just `lib/` and `test/`.
- **Dialyzer PLT apps**: Added `:mix` and `:ex_unit` to `plt_add_apps` for broader coverage.

### Open items

- None. Ready for M-ES-02 (golden fixtures).
