# Liminara

Liminara is a runtime for reproducible nondeterministic computation.

It extends the build-system model to work that includes real choices: LLM responses, human approvals, stochastic selection, and other steps that are not purely deterministic. Instead of pretending those steps are stable, Liminara records them as first-class runtime data so a run can be replayed, audited, and reasoned about later.

In short: immutable artifacts, typed operations, recorded decisions, append-only run logs, and domain packs that compose those pieces into real workflows.

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

The current implementation is built around Elixir/OTP supervision, append-only event logs, filesystem-backed artifacts, and Python ops executed via ports when the ecosystem is useful.

## Core Concepts

- Artifact: immutable, content-addressed data
- Op: a typed transformation with a determinism and execution contract
- Decision: a recorded nondeterministic choice
- Run: an execution represented by an append-only event log
- Pack: a domain module that defines ops and produces plans

## Current Status

This repository is under active private development.

Current sequencing is tracked in [work/roadmap.md](work/roadmap.md). The project is currently in Phase 5c, Radar hardening, with the execution-truth workstream active.

Current near-term sequence:

1. Radar correctness
2. Radar hardening
3. VSME
4. Platform generalization

## Repository Layout

- [runtime](runtime): Elixir umbrella runtime (`liminara_core`, `liminara_web`, `liminara_radar`, observation/runtime apps)
- [runtime/python](runtime/python): Python op runner and Python-based ops
- [docs](docs): architecture, analysis, domain-pack research, and references
- [work](work): roadmap, epics, milestone tracking, and decisions
- [dag-map](dag-map): DAG visualization submodule
- [ex_a2ui](ex_a2ui): A2UI integration submodule
- [integrations](integrations): language and external integration experiments
- [test_fixtures](test_fixtures): reusable fixtures and golden data

## Getting Started

### Prerequisites

- Elixir `~> 1.18`
- Python `>= 3.12`
- `uv` for the Python runtime project
- Git submodules initialized if you need local work on bundled subprojects

### Bootstrap

Initialize submodules if needed:

```bash
git submodule update --init --recursive
```

Fetch Elixir dependencies:

```bash
cd runtime
mix deps.get
```

Sync the Python op environment:

```bash
cd runtime/python
uv sync
```

### Run the App

Start the Phoenix application from the umbrella root:

```bash
cd runtime
mix phx.server
```

### Useful Validation Commands

Core runtime tests:

```bash
cd runtime
mix test apps/liminara_core/test
```

Python tests:

```bash
cd runtime/python
uv run pytest
```

Python lint and format checks:

```bash
cd runtime/python
uv run ruff check .
uv run ruff format --check .
```

## Domain Direction

The planned pack sequence is:

1. Radar
2. VSME
3. House Compiler
4. DPP

Radar is the current proving ground for replay integrity, warning/degraded-outcome handling, and execution hardening. House Compiler is the deliberate proof that Liminara is not only an LLM workflow system.

## Docs Map

If you are new to the repository, start here:

- [docs/liminara.md](docs/liminara.md): comprehensive project reference
- [docs/guides/pack_design_and_development.md](docs/guides/pack_design_and_development.md): pack authoring rules, ownership boundaries, and persistent-data guidance
- [docs/guides/devcontainer_operations.md](docs/guides/devcontainer_operations.md): local devcontainer lifecycle, persistence, cleanup, and rebuild guidance
- [work/roadmap.md](work/roadmap.md): current sequencing and status
- [work/decisions.md](work/decisions.md): active architectural decisions
- [docs/architecture/contracts/00_TRUTH_MODEL.md](docs/architecture/contracts/00_TRUTH_MODEL.md): execution-truth foundation
- [docs/architecture/contracts/01_CONTRACT_MATRIX.md](docs/architecture/contracts/01_CONTRACT_MATRIX.md): contract overview
- [docs/architecture/contracts/02_SHIM_POLICY.md](docs/architecture/contracts/02_SHIM_POLICY.md): rules for temporary compatibility shims

## Licensing

This repository is private right now. No public license grant is being made through this README.

The intended public direction is Apache-2.0 once the project is ready to be released that way, but that is not finalized here yet.