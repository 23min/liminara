# Agent Runtime Specs (Index)

**Generated:** 2026-03-02

This folder contains the umbrella spec, the core runtime spec, and individual domain-pack specs.
All documents are ChatGPT-generated brainstorming output — treat as exploration, not blueprints.

## Structure

### `core/` — Vision and runtime design
- `00_UMBRELLA.md` — overall vision, pack sorting, competitive landscape
- `01_CORE_RUNTIME.md` — the substrate kernel (Elixir/OTP control plane)
- `ARCHITECTURE_REQUIREMENTS_BRIEF.md` — solution architecture brief

### `packs/` — Domain pack specs
- `radar.omvarldsbevakning.md` — monitor sources, cluster themes, produce briefings
- `house_compiler.md` — SketchUp → structural analysis → manufacturing outputs
- `software_factory.md` — LLM-assisted software development with gating and provenance
- `agent_fleets.md` — long-lived groups of agents, fleet semantics
- `behavior_dsl.md` — safe inspectable DSL for LLM-generated rules
- `evolutionary_factory.md` — evolutionary optimization of prompts, policies, workflows
- `flowtime.integration.md` — FlowTime flow/queue modeling integration
- `lodetime.dev_pack.md` — codebase + CI signals as flowing system
- `population_sim.md` — agent-based simulation framework
- `process_mining.md` — event log analysis, process discovery

### `toys/` — Toy/test domain packs
- `toy.report_compiler.md` — compile markdown/diagrams → PDF/HTML (test fixture)
- `toy.ruleset_lab.md` — evaluate dataset against versioned ruleset
- `toy.ga_sandbox.md` — genetic algorithm harness

## Reading order (recommended)

1. `core/00_UMBRELLA.md`
2. `core/01_CORE_RUNTIME.md`
3. `packs/radar.omvarldsbevakning.md` (first real pack)
4. `toys/toy.report_compiler.md` (first test fixture)
