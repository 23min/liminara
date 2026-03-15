# Liminara

## What this is

Liminara is **a runtime for reproducible nondeterministic computation**. It records every nondeterministic choice — LLM responses, human approvals, stochastic selections — so any run can be replayed exactly, audited completely, and cached intelligently. Technically: a DAG of operations producing immutable, content-addressed artifacts, with nondeterminism captured as decision records, supervised by Elixir/OTP. Five concepts (Artifact, Op, Decision, Run, Pack), one scheduler loop, one event log as source of truth.

## Project structure

- `docs/brainstorm/` — Original ChatGPT-generated specs (core only). Treat as brainstorming, not blueprints.
  - `01-03` — Architecture brief, umbrella vision, core runtime spec
- `docs/domain_packs/` — Domain pack specs (brainstormed, not validated)
  - `01-03` — Active packs: Radar, House Compiler, Software Factory
  - `04-05` — Related packs: FlowTime Integration, Process Mining
  - `06-10` — Far-horizon packs: Agent Fleets, Population Sim, Behavior DSL, Evolutionary Factory, LodeTime
  - `11-13` — Toy/test packs: Report Compiler, Ruleset Lab, GA Sandbox
- `docs/architecture/` — Core architecture and build plan. Start here.
  - `01_CORE.md` — The runtime architecture (five concepts, scheduler, OTP mapping, caching)
  - `02_PLAN.md` — Living build plan (current phase, sequencing, deferral triggers)
- `docs/analysis/` — Strategic analysis and landscape research
  - `02_Fresh_Analysis.md` — What Liminara is, landscape, viability, MVP strategy, Burr/ControlFlow/Crosser comparison
  - `03_EU_AI_Act_and_Funding.md` — EU AI Act Article 12 mapping, funding paths (EIC, Vinnova, Horizon Europe)
  - `01_First_Analysis.md` — Initial honest review of the original specs
- `docs/research/` — Supporting research (build-vs-buy, artifact stores, A2UI, house compiler, project origins)

## Five core concepts

- **Artifact**: immutable, content-addressed blob. The edges in the DAG (data flowing between ops).
- **Op**: typed function (artifacts in → artifacts out) with a determinism class (pure, pinned_env, recordable, side_effecting).
- **Decision**: recorded nondeterministic choice (LLM response, GA selection, human approval, random seed). Enables replay.
- **Run**: an execution = an append-only event log + a plan (DAG of op-nodes). Events are the source of truth.
- **Pack**: a module providing op definitions, a `plan/1` function, and optional `init/0` for reference data. Callbacks: `id`, `version`, `ops`, `plan`, `init`.

## Key design principles

- **Discovery vs Replay**: first run builds DAG by making choices; replay injects stored decisions. After all decisions are recorded, every run is a deterministic build.
- **Agent = any supervised capability provider**: LLM, computation engine, geometry kernel, rule engine, human gate, optimizer. The runtime doesn't care what's inside — it cares about the contract.
- **Event sourcing**: the event log IS the run. All state is derived from events.
- **Caching = memoization**: `cache_key = hash(op, version, input_hashes, env_hash?)`. Determinism class controls caching behavior.
- **Zero external dependencies for the core**: ETS + filesystem + OTP. Add Postgres/Oban when needed, not before.

## Tech stack

- Elixir/OTP for control plane and orchestration
- ETS for hot metadata (artifact index, cache, run state) — rebuilt from event files on startup
- Filesystem for artifact blobs (content-addressed, Git-style)
- JSONL files for event logs (one per run, canonical JSON per RFC 8785, hash-chained)
- ex_a2ui (Bandit + WebSock) for observation UI — no Phoenix needed
- Ports/containers/NIFs for compute plane (heavy ops stay off the BEAM scheduler)
- Oban + Postgres when scheduling is needed (not in walking skeleton)
- Rust NIFs (via Rustler) for geometry kernels (house compiler, future)

## Domain packs (target)

1. **Report Compiler** (toy) — first pack. Test fixture that exercises every core concept: pure/recordable/side-effecting ops, gates, binary artifacts, caching, replay.
2. **Radar (omvärldsbevakning)** — first real pack. Pipeline mode. Validates scheduling, caching, LLM decisions, delivery.
3. **House compiler** — second real pack. Pipeline mode with fan-out. Validates binary artifacts, non-LLM ops, heterogeneous executors. Has a buyer.
4. **Software factory** — third real pack. Discovery mode. Validates dynamic DAG expansion, long decision chains.

## Development approach

See `docs/architecture/02_PLAN.md` for the full build plan (Phase 0–7) with done-when criteria and dependencies.

## Workflow conventions

### Directory layout
- `docs/` — pre-work: research, analysis, brainstorming. Input material, not specs.
- `work/` — the pipeline: roadmap, active epics/milestones, decisions, templates.
  - `work/epics/` — active epics. Each epic is a folder with `epic.md` + milestone files + session logs.
  - `work/done/` — completed epics (whole epic folder moves here when all milestones are done).
  - `work/decisions/` — Architecture Decision Records (ADRs).
  - `work/_templates/` — templates for epics, milestones, logs, ADRs.

### Planning hierarchy

Three levels, each with a clear role:

- **Phase** (`docs/architecture/02_PLAN.md`) — strategic sequencing. *Why* this order, what blocks what, deferral triggers. Architecture-level. Rarely changes.
- **Roadmap** (`work/roadmap.md`) — operational status. Maps phases → epics → current status. The dashboard you check at the start of a session. Updated as epics progress.
- **Epic** (`work/epics/E-NN-slug/epic.md`) — a capability you can ship and demonstrate. 2–5 milestones. Goal, scope, success criteria.
- **Milestone** (`M-{ABR}-{NN}-{slug}.md`) — a testable vertical slice within an epic. Spec an agent works from.
- **Milestone log** (`M-{ABR}-{NN}-{slug}-log.md`) — append-only session provenance.

A phase contains multiple epics. An epic contains 2–5 milestones. If an epic needs more than 5 milestones, split the epic.

### Status values (used in frontmatter)
`draft` → `ready` → `active` → `review` → `done`

### TDD workflow
1. Each milestone is a single Claude session. Write failing tests first, get human approval, then implement.
2. Within a session: read milestone spec → write tests (red) → human says "looks good" → implement until tests pass (green).
3. Human reviews diff before any commit.
4. Validation pipeline must pass before commit. Use the tools appropriate for the language/technology touched:
   - **Elixir**: `mix format`, `mix credo`, `mix dialyzer`, `mix test`
   - **Python**: `uv run ruff check .`, `uv run ruff format --check .`, `uv run ty check`, `uv run pytest`
   - **JavaScript/TypeScript**: `prettier`, `eslint`, test runner (jest/vitest)
   - **.NET/C#**: `dotnet format`, `dotnet build`, `dotnet test`
   - Add entries here as new languages are introduced to the project.

### Python toolchain (standard for all Python projects)
- **uv** — package manager, virtualenv, and script runner
- **ruff** — linter (extended rules: B, C4, E, F, I, PT, RUF, SIM, UP, W) and formatter
- **ty** — type checker (Astral, Rust-based)
- **pytest + pytest-cov** — test runner with coverage reporting
- All four are in the Astral ecosystem (uv, ruff, ty) for consistency and performance.

### Git workflow
- One worktree per epic, not per milestone. All milestones in an epic share the same worktree and branch.
- New Claude session per milestone, same worktree. Start each session by reading the milestone spec.
- Agents never push. Human reviews and commits.
- Merge strategy: squash per milestone (or per epic if milestones are small).

### Commit message convention (Conventional Commits)

Follow [Conventional Commits](https://www.conventionalcommits.org/) v1.0.0:

```
<type>(<scope>): <short summary>

<optional body — what and why, not how>

Co-Authored-By: Claude <noreply@anthropic.com>
```

**Types:** `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `ci`, `build`
**Scope:** the area affected — `core`, `artifact-store`, `event-store`, `radar`, `plan`, `docs`, etc.
**Co-Authored-By:** Always include when Claude contributed to the commit. Use `Claude <noreply@anthropic.com>`.

Examples:
```
feat(artifact-store): content-addressed blob storage with SHA-256
docs: initial project structure and architecture documents
test(event-store): hash chain integrity verification
refactor(core): extract scheduler loop into Run.Server
```

### Milestone completion checklist

Every milestone completion MUST include these steps — they are part of the work, not optional cleanup:

- [ ] All acceptance criteria checked (`[x]`) in the milestone spec
- [ ] Milestone frontmatter `status` → `done`
- [ ] Epic milestone table updated (status column)
- [ ] Roadmap updated (`work/roadmap.md`)
- [ ] Session log entry appended to `M-{ABR}-{NN}-{slug}-log.md`
- [ ] Validation pipeline passes (lint, format, tests)

Do not declare a milestone done until all of these are complete.

### Session provenance
After each significant work session on a milestone, append an entry to the milestone log file.
Use the template in `work/_templates/milestone-log.md`.
Record: decisions made, alternatives tried and abandoned, outcome, open items.

### Architecture Decision Records
When a significant architectural decision is made, create an ADR in `work/decisions/`.
Use the template in `work/_templates/ADR.md`.
Reference ADRs from the relevant milestone or epic doc.

## What's deferred

See `docs/architecture/01_CORE.md` § "What's deferred" and `docs/analysis/10_Synthesis.md` § 8 for full rationale.

- Multi-tenancy enforcement (`tenant_id = "default"`, schema ready, enforcement waits)
- Distributed execution (single BEAM node)
- Discovery mode (pipeline mode first)
- Wasm executor
- Budget enforcement (track costs, don't enforce)
- Complex replay modes (discovery + replay is sufficient)
