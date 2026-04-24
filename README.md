# Liminara

Liminara is a runtime for reproducible nondeterministic computation.

It extends the build-system model to work that includes real choices: LLM responses, human approvals, stochastic selection, and other steps that are not purely deterministic. Instead of pretending those steps are stable, Liminara records them as first-class runtime data so a run can be replayed, audited, and reasoned about later.

In short: immutable artifacts, typed operations, recorded decisions, append-only run logs, and domain packs that compose those pieces into real workflows.

> **Status: pre-alpha.** Liminara is under active single-maintainer development. The public repository exists so the work, reasoning, and architecture history are visible. APIs, wire protocols, and schemas will change.

## What It Is

Liminara combines three things that are usually split apart:

- Content-addressed artifacts
- Recorded nondeterministic decisions
- Explicit determinism and replay policy at the op level

That makes it possible to answer questions that ordinary workflow tools usually cannot answer well:

- Why did this run produce this output?
- Which steps were replayed versus recomputed?
- Which choices came from a model, a human, or a stochastic algorithm?
- Which outputs are safe to cache, and which are not?

The current implementation is built around Elixir/OTP supervision, append-only event logs, filesystem-backed artifacts, and Python ops executed via ports when the ecosystem is useful. Future executors (container, wasm, remote) are on the roadmap; the contract is designed to be language-agnostic.

## Core Concepts

- **Artifact**: immutable, content-addressed data
- **Op**: a typed transformation with a determinism and execution contract
- **Decision**: a recorded nondeterministic choice
- **Run**: an execution represented by an append-only event log
- **Pack**: a domain module that defines ops and produces plans

## Current Status

Liminara is in Phase 5c. Completed phases cover data model, Python SDK / data model validation, Elixir walking skeleton, OTP runtime, observation layer, Radar pack (the first production-shaped domain pack), and the execution-truth rewrite.

Current near-term sequence:

1. Radar correctness — **complete**
2. Radar hardening — **in progress** (warnings & degraded outcomes, pack contribution contract, op sandbox)
3. VSME (first compliance pack) — next
4. Platform generalization (persistence, scheduling, dynamic DAGs, container executor, etc.) — downstream

Active planning and sequencing lives in [work/roadmap.md](work/roadmap.md). Active epics live in [work/epics/](work/epics/). Active architectural decisions live in [work/decisions.md](work/decisions.md).

## Repository Layout

- [runtime](runtime) — Elixir umbrella runtime (`liminara_core`, `liminara_web`, `liminara_radar`, observation/runtime apps)
- [runtime/python](runtime/python) — Python op runner and Python-based ops
- [docs](docs) — architecture, analysis, domain-pack research, and references
- [work](work) — roadmap, epics, milestone tracking, and decisions
- [dag-map](dag-map) — DAG visualization submodule
- [ex_a2ui](ex_a2ui) — A2UI integration submodule
- [integrations](integrations) — language and external integration experiments
- [test_fixtures](test_fixtures) — reusable fixtures and golden data

## Getting Started

The supported development environment is the repo's devcontainer; it ships known-good versions of Elixir, Python, Node, and tooling.

### Prerequisites (without devcontainer)

- Elixir `~> 1.18`
- Python `>= 3.12`
- `uv` for the Python runtime project
- Git submodules initialized if you need local work on bundled subprojects

### Bootstrap

```bash
git submodule update --init --recursive
cd runtime && mix deps.get
cd python && uv sync
```

### Run the App

```bash
cd runtime
mix phx.server
```

### Useful Validation Commands

```bash
# Elixir
cd runtime
mix test apps/liminara_core/test

# Python
cd runtime/python
uv run pytest
uv run ruff check .
uv run ruff format --check .
```

## Domain Direction

The planned pack sequence is:

1. **Radar** — omvärldsbevakning, daily intelligence briefing
2. **VSME** — SME sustainability reporting (first compliance pack)
3. **House Compiler** — design → manufacturing
4. **DPP** — Digital Product Passport

Radar is the current proving ground for replay integrity, warning/degraded-outcome handling, and execution hardening. House Compiler is the deliberate proof that Liminara is not only an LLM workflow system.

## Docs Map

If you are new to the repository, start here:

- [docs/liminara.md](docs/liminara.md) — comprehensive project reference
- [docs/guides/pack_design_and_development.md](docs/guides/pack_design_and_development.md) — pack authoring rules, ownership boundaries, persistent-data guidance
- [docs/guides/devcontainer_operations.md](docs/guides/devcontainer_operations.md) — local devcontainer lifecycle, persistence, cleanup, rebuild guidance
- [work/roadmap.md](work/roadmap.md) — current sequencing and status
- [work/decisions.md](work/decisions.md) — active architectural decisions
- [docs/governance/truth-model.md](docs/governance/truth-model.md) — execution-truth foundation
- [docs/architecture/indexes/contract-matrix.md](docs/architecture/indexes/contract-matrix.md) — contract overview
- [docs/governance/shim-policy.md](docs/governance/shim-policy.md) — rules for temporary compatibility shims

## Discussions

Discussions are welcome via GitHub Issues — especially architectural pushback, design questions, and pointers to prior art.

## License

Liminara is licensed under the [Apache License, Version 2.0](LICENSE). You may use the runtime under the terms of that license. Submodules have their own licenses; check each submodule's repository.
