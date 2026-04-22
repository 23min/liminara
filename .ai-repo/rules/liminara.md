# Liminara — Project Rules

## What this is

Liminara is **a runtime for reproducible nondeterministic computation**. It records every nondeterministic choice — LLM responses, human approvals, stochastic selections — so any run can be replayed exactly, audited completely, and cached intelligently. Technically: a DAG of operations producing immutable, content-addressed artifacts, with nondeterminism captured as decision records, supervised by Elixir/OTP.

## Five core concepts

- **Artifact**: immutable, content-addressed blob (SHA-256). The edges in the DAG.
- **Op**: typed function (artifacts in → artifacts out) with a determinism class (pure, pinned_env, recordable, side_effecting).
- **Decision**: recorded nondeterministic choice (LLM response, GA selection, human approval, random seed). Enables replay.
- **Run**: an execution = an append-only event log + a plan (DAG of op-nodes). Events are the source of truth.
- **Pack**: a module providing op definitions and a `plan/1` function. (Reference-data callback `init/0` is approved-next; see `docs/architecture/01_CORE.md`.)

## Tech stack

- Elixir/OTP for control plane and orchestration
- ETS for hot metadata, filesystem for artifact blobs, JSONL for event logs
- ex_a2ui (Bandit + WebSock) for A2UI observation — no Phoenix needed
- Phoenix LiveView for primary web UI
- Ports/containers for compute plane (Python ops, external tools)
- Python ops via `:port` — uv for package management, ruff for linting, ty for type checking, pytest for tests

## Working rules

- **Never make assumptions on ambiguous decisions.** If something is unclear, could go multiple ways, or has downstream consequences — stop and ask.

## Truth discipline

- `work/roadmap.md` is the only current sequencing and build-plan source.
- `.ai-repo/config/artifact-layout.json` is the canonical artifact layout source for roadmap, epic, milestone, and tracking paths. Generated assistant surfaces must mirror it rather than redefine it.
- `docs/architecture/` contains only live or decided-next architecture. Historical material belongs in `docs/history/`.
- `docs/history/` is context, not authority.
- If current behavior is disputed, live code, tests, and canonical persistence specs win.
- If approved next-state behavior is disputed, the active epic or milestone spec plus decided-next architecture docs win.
- Compatibility shims are banned by default. Any exception needs a named removal trigger in the milestone spec and tracking doc.
- To change AI instruction behavior, edit `.ai-repo/` and run `./.ai/sync.sh`. Do not hand-edit generated instruction files except for the preserved `CLAUDE.md` Current Work section.

## Contract matrix discipline

`docs/architecture/contracts/01_CONTRACT_MATRIX.md` is the live ownership/status index for every first-class contract surface in the runtime. Drift here is silent failure: new contracts ship without rows, retired contracts leave stale rows, live-source paths rot. The following rules apply to every milestone that touches a contract surface.

- **Plan-time declaration.** Any milestone that creates, modifies, or retires a contract surface **must** include a `## Contract matrix changes` section in its spec with three bullets: rows added, rows updated, rows retired. If none apply, write "None — this milestone does not touch contract surfaces." Missing section blocks spec approval.
- **Wrap-time check.** Before wrapping a milestone that declared matrix changes, the reviewer verifies that the declared rows are present in `01_CONTRACT_MATRIX.md` with correct live-source paths. Row absence blocks wrap.
- **Live-source accuracy.** When a live-source file in a matrix row is renamed, moved, deleted, or extracted to a submodule, the same PR updates the row. Finding drift after merge is a reviewer miss and should be noted in agent history.
- **Boundary with ADRs.** A matrix row points at *what the contract is and where its live source lives*; an ADR under `docs/decisions/` explains *why the contract has that shape*. The two always cross-reference but never overlap.

Until framework issue [ai-workflow#20](https://github.com/23min/ai-workflow/issues/20) lands plan-time template support + wrap-time doc-lint enforcement, this discipline is enforced by spec review and reviewer agent attention.

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

Co-Authored-By: GitHub Copilot <noreply@github.com>
```
Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `ci`, `build`
Always include Co-Authored-By when GitHub Copilot contributed.

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
- `docs/architecture/` — active architecture, contract docs, approved next-state plans
- `docs/history/` — archived architecture and superseded design material
- `docs/analysis/` — strategic analysis, compliance, pack plans
- `docs/decisions/` — Architecture Decision Records (ADRs)
- `runtime/` — Elixir umbrella (liminara_core, liminara_observation, liminara_web)
- `work/` — epics, milestones, tracking, roadmap
- `work/done/` — completed epics

## Domain packs (target sequence)

1. **Radar** (omvärldsbevakning) — daily intelligence briefing. Next to build.
2. **VSME** — SME sustainability reporting (first compliance pack)
3. **House Compiler** — design → manufacturing.
4. **DPP** — Digital Product Passport (Feb 2027 enforcement)

