# Project Origins: How Liminara Evolved

**Date:** 2026-03-02
**Source:** User's ChatGPT conversation that led to the spec generation

---

## The evolution

The project started as an exploratory conversation about what language to use for LLM-assisted generative programming, then narrowed through several key decisions:

1. **Language choice:** Elixir, specifically for OTP supervision trees, fault tolerance, and lightweight processes for agent coordination. ChatGPT ranked Elixir as viable but niche (#6 behind TS, Python, Go, C#, Rust) — the user chose it deliberately for BEAM's strengths.

2. **Architecture direction:** An "agent runner" with durable event log, checkpoint/resume, and distributed execution. ChatGPT recommended Oban for the job queue backbone and Postgres for persistence.

3. **Hybrid interaction model:** Not purely autonomous or purely interactive — agents should support both modes via a "gate" system where some runs auto-proceed and others pause for human input.

4. **A2UI discovery:** The user brought A2UI (https://a2ui.org/) to the conversation. ChatGPT confirmed it as a good fit for declarative, streaming agent UIs.

5. **Tools and workspaces:** The conversation explored IDE-like platform tools (read/edit/search/exec), workspace models (ephemeral per-run vs persistent per-project), and sandboxing requirements.

6. **Scope reduction:** ChatGPT pushed back on the full scope, recommending a "niche runner" focused on one use case first. The user chose **Radar/Omvärldsbevakning** — monitoring websites and sources for developments, using Haiku for cost efficiency.

7. **Cost consciousness:** The user explicitly flagged that LLM costs matter. The architecture evolved toward "mostly data pipeline, LLM only on cluster representatives" to minimize token usage.

## Key ChatGPT recommendations adopted in the specs

- Oban for durable job scheduling
- Append-only event log for replay/debugging
- Gate system for hybrid HITL
- Ephemeral workspaces per run + persistent per project
- Context management with hot/warm/retrieval tiers
- Budget enforcement per tenant/run
- Start with Radar as first use case (cheapest model, highest daily utility)

## Key tension: platform vs product

The conversation reveals a recurring tension:
- The user wants to build something useful for themselves (product: Radar)
- But also wants a reusable platform (the runtime substrate)
- ChatGPT warned: "general agent OS is too ambitious for v1 solo"
- The specs ended up describing the full platform anyway

This tension is the core risk. The critique in `01_First_Analysis.md` recommends resolving it by building Radar first and extracting the platform from it.
