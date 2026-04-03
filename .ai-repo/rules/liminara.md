# Liminara — Project Rules

## What this is

Liminara is **a runtime for reproducible nondeterministic computation**. It records every nondeterministic choice — LLM responses, human approvals, stochastic selections — so any run can be replayed exactly, audited completely, and cached intelligently. Technically: a DAG of operations producing immutable, content-addressed artifacts, with nondeterminism captured as decision records, supervised by Elixir/OTP.

## Five core concepts

- **Artifact**: immutable, content-addressed blob (SHA-256). The edges in the DAG.
- **Op**: typed function (artifacts in → artifacts out) with a determinism class (pure, pinned_env, recordable, side_effecting).
- **Decision**: recorded nondeterministic choice (LLM response, GA selection, human approval, random seed). Enables replay.
- **Run**: an execution = an append-only event log + a plan (DAG of op-nodes). Events are the source of truth.
- **Pack**: a module providing op definitions, a `plan/1` function, and optional `init/0` for reference data.

## Tech stack

- Elixir/OTP for control plane and orchestration
- ETS for hot metadata, filesystem for artifact blobs, JSONL for event logs
- ex_a2ui (Bandit + WebSock) for A2UI observation — no Phoenix needed
- Phoenix LiveView for primary web UI
- Ports/containers for compute plane (Python ops, external tools)
- Python ops via `:port` — uv for package management, ruff for linting, ty for type checking, pytest for tests

## Working rules

- **Never make assumptions on ambiguous decisions.** If something is unclear, could go multiple ways, or has downstream consequences — stop and ask.

## Validation pipeline (per language)

Before any commit, the appropriate validation must pass:

- **Elixir**: `mix format`, `mix credo`, `mix dialyzer`, `mix test`
- **Python**: `uv run ruff check .`, `uv run ruff format --check .`, `uv run ty check`, `uv run pytest`
- **JavaScript/TypeScript**: `prettier`, `eslint`, test runner
- **dag-map** (submodule): `npm test` (274 tests)

## Commit convention

Follow Conventional Commits v1.0.0:
```
<type>(<scope>): <short summary>

<optional body>

Co-Authored-By: Claude <noreply@anthropic.com>
```
Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `ci`, `build`
Always include Co-Authored-By when Claude contributed.

## Git workflow

- One worktree per epic, not per milestone
- Epic branch: `epic/<slug>`, milestone branch: `milestone/<id>` from epic branch
- Agents never push without human approval
- Merge strategy: squash per milestone (or per epic if milestones are small)

## Submodules

- `dag-map` — DAG visualization library (github.com/23min/DAG-map)
- `ex_a2ui` — A2UI protocol library (github.com/23min/ex_a2ui)
- `proliminal.net` — Company website (github.com/23min/proliminal.net)

## Project structure

- `docs/` — research, analysis, architecture, brainstorming
- `docs/architecture/` — core architecture and build plan
- `docs/analysis/` — strategic analysis, compliance, pack plans
- `docs/decisions/` — Architecture Decision Records (ADRs)
- `runtime/` — Elixir umbrella (liminara_core, liminara_observation, liminara_web)
- `work/` — epics, milestones, tracking, roadmap
- `work/done/` — completed epics

## Domain packs (target sequence)

1. **Radar** (omvärldsbevakning) — daily intelligence briefing. Next to build.
2. **VSME** — SME sustainability reporting (first compliance pack)
3. **House Compiler** — design → manufacturing. Has a buyer.
4. **DPP** — Digital Product Passport (Feb 2027 enforcement)

